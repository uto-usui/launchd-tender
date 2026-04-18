import SwiftUI
import SwiftData
import TenderCore

/// Keychain 管理を解除して元の plist に戻す sheet。
struct KeychainDetachSheet: View {
    let agent: LaunchAgent
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var deleteKeychainEntries: Bool = false
    @State private var phase: Phase = .preview
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case preview
        case executing
        case succeeded
        case failed
    }

    private let keychainService = "com.uto-usui.tender"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keychain 管理を解除")
                    .font(.title3).bold()
                Text(agent.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DetailBlock(title: "復元される ProgramArguments") {
                        Text(agent.tenderOriginalProgramArguments.joined(separator: " "))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }

                    if !agent.tenderWrappedEnvs.isEmpty {
                        DetailBlock(title: "関連 Keychain アカウント") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(agent.tenderWrappedEnvs, id: \.self) { env in
                                    Text("\(keychainService) / \(agent.label).\(env)")
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    DetailBlock(title: "その他") {
                        Toggle("Keychain エントリも削除する", isOn: $deleteKeychainEntries)
                            .disabled(phase != .preview)
                        Text("既定は残す。Keychain に値を置いたままなら、再度移行するときに入力不要。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    if phase == .succeeded {
                        Label("解除しました", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline).bold()
                    }
                }
            }

            Divider()

            HStack {
                if phase == .executing {
                    ProgressView().controlSize(.small)
                    Text("実行中…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { onDismiss() }
                Button {
                    Task { await execute() }
                } label: {
                    Text(phase == .succeeded ? "完了" : "解除")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(phase != .preview)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 380)
    }

    private func execute() async {
        phase = .executing
        errorMessage = nil

        do {
            let wrapperDir = try KeychainMigrationService.defaultWrapperDirectory()
            let plan = try KeychainDetachPlan.make(
                agent: agent,
                wrapperDirectory: wrapperDir,
                keychainService: keychainService,
                deleteKeychainEntries: deleteKeychainEntries
            )
            let backupsRoot = try PlistAtomicWriter.defaultBackupsRootURL()
            let plistWriter = PlistAtomicWriter(backupsRootURL: backupsRoot)
            let service = KeychainDetachService(
                keychain: ProcessKeychainClient(),
                plistWriter: plistWriter,
                fileWriter: FileSystemWrapperFileWriter()
            )
            let receipt = try await service.execute(plan: plan)

            if let backup = receipt.backup {
                let recorder = BackupRecorder(context: modelContext)
                try recorder.record(backup)
            }
            phase = .succeeded
        } catch {
            errorMessage = String(describing: error)
            phase = .failed
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0))
                if phase == .failed {
                    phase = .preview
                }
            }
        }
    }
}

private struct DetailBlock<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}
