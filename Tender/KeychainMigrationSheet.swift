import SwiftUI
import SwiftData
import TenderCore

/// 平文 env → Keychain ラッパ移行のプレビュー & 実行 sheet。
///
/// フロー:
/// 1. 検出された env をチェックボックスで選択（default: 全選択）
/// 2. タブで「plist 差分」と「生成される wrapper script」を確認
/// 3. 「実行」押下で `KeychainMigrationService.execute(plan:)` を呼ぶ
/// 4. 成功 / 失敗に応じて結果を表示、閉じると ContentView に戻る
struct KeychainMigrationSheet: View {
    let agent: LaunchAgent
    let detections: [SecretDetector.DetectedSecret]
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var selectedEnvs: Set<String>
    @State private var previewTab: PreviewTab = .diff
    @State private var phase: Phase = .preview
    @State private var errorMessage: String?

    enum PreviewTab: String, CaseIterable, Identifiable {
        case diff = "plist 差分"
        case wrapper = "wrapper script"
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case preview
        case executing
        case succeeded
        case failed
    }

    private let keychainService = "com.uto-usui.tender"

    init(agent: LaunchAgent, detections: [SecretDetector.DetectedSecret], onDismiss: @escaping () -> Void) {
        self.agent = agent
        self.detections = detections
        self.onDismiss = onDismiss
        self._selectedEnvs = State(initialValue: Set(detections.map(\.key)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    envSelection
                    if let plan = currentPlan {
                        previewSection(plan: plan)
                    } else if let message = planErrorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    if phase == .succeeded {
                        successBanner
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 520, idealHeight: 620)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keychain への移行")
                .font(.title3).bold()
            Text(agent.label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var envSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("対象の env")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(detections, id: \.key) { detection in
                Toggle(isOn: binding(for: detection.key)) {
                    HStack(spacing: 6) {
                        Text(detection.key)
                            .font(.body.monospaced().bold())
                        Text("→").foregroundStyle(.secondary)
                        Text(detection.pattern.provider)
                            .font(.caption)
                        Text("(\(detection.pattern.prefix)…)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(phase != .preview)
            }
        }
    }

    private func previewSection(plan: KeychainMigrationPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $previewTab) {
                ForEach(PreviewTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch previewTab {
            case .diff:
                diffView(plan: plan)
            case .wrapper:
                wrapperView(plan: plan)
            }
        }
    }

    private func diffView(plan: KeychainMigrationPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            diffRow(
                title: "ProgramArguments",
                before: agent.programArguments.joined(separator: " "),
                after: plan.newProgramArguments.joined(separator: " ")
            )

            let removedEnvs = agent.environmentVariables.keys.filter { plan.selectedEnvs.contains($0) }.sorted()
            if !removedEnvs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EnvironmentVariables から削除")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(removedEnvs, id: \.self) { key in
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                .font(.caption2)
                            Text(key).font(.body.monospaced())
                            Text("= ****")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("plist に追加される meta key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                metaRow("TenderManaged", value: "true")
                metaRow("TenderWrappedEnvs", value: plan.metaKeys.tenderWrappedEnvs.joined(separator: ", "))
                metaRow("TenderOriginalProgramArguments", value: plan.metaKeys.tenderOriginalProgramArguments.joined(separator: " "))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Keychain に書き込まれる項目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(plan.keychainWrites, id: \.account) { write in
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill").foregroundStyle(Color.accentColor)
                            .font(.caption2)
                        Text("\(write.service) / \(write.account)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func diffRow(title: String, before: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red).font(.caption2)
                Text(before).font(.caption.monospaced()).textSelection(.enabled)
            }
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.caption2)
                Text(after).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }

    private func metaRow(_ key: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(key).font(.caption.monospaced().bold())
            Text("=").foregroundStyle(.secondary).font(.caption)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func wrapperView(plan: KeychainMigrationPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.wrapperURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(plan.wrapperScript)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
        }
    }

    private var successBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("移行しました", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.subheadline).bold()
            Text("launchctl bootout gui/<uid>/\(agent.label) 後に bootstrap で再読込してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.green.opacity(0.1))
        )
    }

    private var footer: some View {
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
                Text(phase == .succeeded ? "完了" : "実行")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(phase != .preview || selectedEnvs.isEmpty || currentPlan == nil)
        }
    }

    // MARK: - Binding / Plan

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedEnvs.contains(key) },
            set: { isOn in
                if isOn {
                    selectedEnvs.insert(key)
                } else {
                    selectedEnvs.remove(key)
                }
            }
        )
    }

    /// 現在選択中の env で計画を組み立てる。失敗時は `planErrorMessage` に反映。
    private var currentPlan: KeychainMigrationPlan? {
        guard !selectedEnvs.isEmpty else { return nil }
        let envs = detections.map(\.key).filter { selectedEnvs.contains($0) }
        do {
            return try KeychainMigrationPlan.make(
                agent: agent,
                selectedEnvs: envs,
                wrapperDirectory: (try? KeychainMigrationService.defaultWrapperDirectory())
                    ?? FileManager.default.temporaryDirectory,
                keychainService: keychainService,
                now: Date()
            )
        } catch {
            return nil
        }
    }

    private var planErrorMessage: String? {
        if selectedEnvs.isEmpty {
            return "対象の env を少なくとも 1 つ選択してください。"
        }
        if agent.sourcePath == nil {
            return "plist の場所が不明なため移行できません。"
        }
        if agent.programArguments.isEmpty {
            return "ProgramArguments が空の plist には移行できません（wrapper で exec する元の argv がありません）。"
        }
        return nil
    }

    // MARK: - Execute

    private func execute() async {
        guard let plan = currentPlan else { return }
        phase = .executing
        errorMessage = nil

        do {
            let backupsRoot = try PlistAtomicWriter.defaultBackupsRootURL()
            let plistWriter = PlistAtomicWriter(backupsRootURL: backupsRoot)
            let service = KeychainMigrationService(
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
            // 次の実行を許すため preview に戻す
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0))
                if phase == .failed {
                    phase = .preview
                }
            }
        }
    }
}
