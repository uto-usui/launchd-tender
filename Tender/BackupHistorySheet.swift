import SwiftUI
import SwiftData
import TenderCore

/// 特定 agent の `BackupEntry` 履歴を一覧・プレビュー・復元する sheet。
///
/// - 一覧: timestamp 降順で左カラムに表示
/// - 右カラム: 選択中のバックアップファイル内容を読み込んで monospace 表示
/// - 復元: `PlistAtomicWriter` 経由で現在の plist を選択バックアップで上書き（事前に現在の状態もバックアップされる）
struct BackupHistorySheet: View {
    let agent: LaunchAgent
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [BackupEntry]

    @State private var selection: PersistentIdentifier?
    @State private var previewText: String = ""
    @State private var previewError: String?
    @State private var phase: Phase = .idle
    @State private var statusMessage: String?
    @State private var confirmingRestore: Bool = false

    enum Phase: Equatable {
        case idle
        case executing
        case succeeded
        case failed
    }

    init(agent: LaunchAgent, onDismiss: @escaping () -> Void) {
        self.agent = agent
        self.onDismiss = onDismiss
        let label = agent.label
        _entries = Query(
            filter: #Predicate<BackupEntry> { $0.label == label },
            sort: [SortDescriptor(\BackupEntry.timestamp, order: .reverse)]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if entries.isEmpty {
                ContentUnavailableView(
                    "バックアップなし",
                    systemImage: "archivebox",
                    description: Text("まだこの agent の plist が書き換えられていません。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    entryList
                        .frame(width: 260)
                    Divider()
                    preview
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 620)
        .confirmationDialog(
            "このバックアップで現在の plist を上書きしますか？",
            isPresented: $confirmingRestore,
            titleVisibility: .visible
        ) {
            Button("復元", role: .destructive) {
                Task { await restore() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在の plist は自動的に新しいバックアップとして保存されます。launchd への反映には別途「再読込」が必要です。")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("バックアップ履歴")
                .font(.title3).bold()
            Text(agent.label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var entryList: some View {
        List(entries, selection: $selection) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.timestamp.formatted(date: .numeric, time: .standard))
                    .font(.body.monospacedDigit())
                Text(entry.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .tag(entry.persistentModelID)
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, newValue in
            loadPreview(for: newValue)
        }
        .task {
            if selection == nil {
                selection = entries.first?.persistentModelID
                loadPreview(for: selection)
            }
        }
    }

    private var preview: some View {
        Group {
            if let previewError {
                ContentUnavailableView(
                    "読み込み失敗",
                    systemImage: "exclamationmark.triangle",
                    description: Text(previewError)
                )
            } else if !previewText.isEmpty {
                ScrollView {
                    Text(previewText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color.secondary.opacity(0.06))
            } else {
                Text("バックアップを選択すると内容を表示します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
    }

    private var footer: some View {
        HStack {
            if phase == .executing {
                ProgressView().controlSize(.small)
                Text("復元中…").foregroundStyle(.secondary)
            }
            if let statusMessage {
                Label(statusMessage, systemImage: phase == .succeeded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(phase == .succeeded ? .green : .red)
                    .font(.caption)
            }
            Spacer()
            Button("閉じる") { onDismiss() }
            Button {
                confirmingRestore = true
            } label: {
                Label("この状態に戻す", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selection == nil || phase == .executing || agent.sourcePath == nil)
        }
    }

    // MARK: - Logic

    private func loadPreview(for id: PersistentIdentifier?) {
        previewText = ""
        previewError = nil
        guard let id, let entry = entries.first(where: { $0.persistentModelID == id }) else {
            return
        }
        let url = URL(fileURLWithPath: entry.plistPath)
        do {
            let data = try Data(contentsOf: url)
            if let xml = makeXmlText(from: data) {
                previewText = xml
            } else if let utf8 = String(data: data, encoding: .utf8) {
                previewText = utf8
            } else {
                previewError = "ファイルをテキストとして読めません（非 UTF-8 binary plist 以外）"
            }
        } catch {
            previewError = error.localizedDescription
        }
    }

    /// binary plist を XML にフォーマット。既に XML ならそのまま。
    private func makeXmlText(from data: Data) -> String? {
        do {
            let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let xml = try PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0)
            return String(data: xml, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func restore() async {
        guard let id = selection,
              let entry = entries.first(where: { $0.persistentModelID == id }),
              let destination = agent.sourcePath else {
            return
        }

        phase = .executing
        statusMessage = nil

        do {
            let backupData = try Data(contentsOf: URL(fileURLWithPath: entry.plistPath))
            let backupsRoot = try PlistAtomicWriter.defaultBackupsRootURL()
            let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
            let preRestoreBackup = try writer.write(
                backupData, to: destination,
                label: agent.label, reason: "manual-restore"
            )
            if let preRestoreBackup {
                let recorder = BackupRecorder(context: modelContext)
                try recorder.record(preRestoreBackup)
            }
            phase = .succeeded
            statusMessage = "復元しました。再読込で launchd に反映できます。"
        } catch {
            phase = .failed
            statusMessage = String(describing: error)
        }
    }
}
