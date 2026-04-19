import SwiftUI
import SwiftData
import Foundation
import TenderCore

/// 「障害切り分けビュー」。設計メモの Phase 4 本丸。
///
/// 1画面に以下を集約する:
/// - label / 状態バッジ / 推定次回実行
/// - 実行ファイル存在 + 実行可能属性
/// - PATH / WorkingDirectory / EnvironmentVariables
/// - StandardOutPath / StandardErrorPath 設定の有無警告
/// - ログ末尾（40 行）
/// - 秘密情報検出
/// - TCC / Full Disk Access 注意喚起
/// - Intent の「復旧手順」
struct TroubleshootingSheet: View {
    let agent: LaunchAgent
    let status: AgentStatus
    let onClose: () -> Void

    @Query private var matchingIntents: [Intent]

    init(agent: LaunchAgent, status: AgentStatus, onClose: @escaping () -> Void) {
        self.agent = agent
        self.status = status
        self.onClose = onClose
        let label = agent.label
        _matchingIntents = Query(filter: #Predicate<Intent> { $0.label == label })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    executableSection
                    environmentSection
                    outputsSection
                    logsSection
                    unifiedLogSection
                    secretsSection
                    nextRunSection
                    intentRecoverySection
                    tccSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("障害切り分け")
                    .font(.title3).bold()
                Text(agent.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            AgentStatusBadge(status: status)
            Button("閉じる", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.md)
    }

    // MARK: - Sections

    private var statusSection: some View {
        sectionCard(title: "状態") {
            Text(statusText)
                .textSelection(.enabled)
        }
    }

    private var statusText: String {
        switch status {
        case .enabled: "有効。launchctl print-disabled に含まれていません。"
        case .disabled: "無効 (launchctl disable で無効化されている状態)。"
        case .missingExecutable(let path): "実行ファイルが見つかりません: \(path)"
        case .notExecutable(let path): "実行ファイルに実行可能属性が立っていません: \(path)"
        case .noProgramArguments: "ProgramArguments / Program が未設定です。"
        }
    }

    private var executableSection: some View {
        sectionCard(title: "実行ファイル") {
            if let executablePath = resolvedExecutablePath {
                VStack(alignment: .leading, spacing: 6) {
                    row(label: "パス", value: executablePath, mono: true)
                    row(
                        label: "存在",
                        value: FileManager.default.fileExists(atPath: executablePath) ? "あり" : "なし（要確認）"
                    )
                    row(
                        label: "実行可能",
                        value: FileManager.default.isExecutableFile(atPath: executablePath) ? "はい" : "いいえ（chmod +x が必要かも）"
                    )
                }
            } else {
                Text("ProgramArguments / Program が未設定のため実行ファイルを決定できません。")
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private var resolvedExecutablePath: String? {
        if let first = agent.programArguments.first, !first.isEmpty { return first }
        if let program = agent.program, !program.isEmpty { return program }
        return nil
    }

    private var environmentSection: some View {
        sectionCard(title: "環境") {
            VStack(alignment: .leading, spacing: 6) {
                row(label: "WorkingDirectory", value: agent.workingDirectory ?? "(未設定)", mono: agent.workingDirectory != nil)
                if agent.environmentVariables.isEmpty {
                    row(label: "EnvironmentVariables", value: "(なし)")
                } else {
                    Text("EnvironmentVariables")
                        .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                    ForEach(agent.environmentVariables.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(alignment: .firstTextBaseline) {
                            Text(key).font(.body.monospaced().bold())
                            Text("=").foregroundStyle(.secondary)
                            Text(value).font(.body.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var outputsSection: some View {
        sectionCard(title: "出力設定") {
            VStack(alignment: .leading, spacing: 6) {
                outputRow(label: "StandardOutPath", value: agent.standardOutPath)
                outputRow(label: "StandardErrorPath", value: agent.standardErrorPath)
                if agent.standardOutPath == nil && agent.standardErrorPath == nil {
                    Text("両方とも未設定のため、ログは Unified Log (`log show --predicate 'process == \"\(executableName)\"'`) で追う必要があります。")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    @ViewBuilder
    private func outputRow(label: String, value: String?) -> some View {
        if let value {
            row(label: label, value: value, mono: true)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Text("(未設定)").foregroundStyle(.yellow)
            }
        }
    }

    private var logsSection: some View {
        sectionCard(title: "ログ末尾 (各 40 行)") {
            VStack(alignment: .leading, spacing: 10) {
                if let path = agent.standardOutPath {
                    LogTailView(title: "StandardOutPath", path: path)
                }
                if let path = agent.standardErrorPath {
                    LogTailView(title: "StandardErrorPath", path: path)
                }
                if agent.standardOutPath == nil && agent.standardErrorPath == nil {
                    Text("(出力パス未設定。上のセクション参照)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var unifiedLogSection: some View {
        sectionCard(title: "Unified Log (log show)") {
            UnifiedLogView(agent: agent)
        }
    }

    private var secretsSection: some View {
        let detections = SecretDetector.detect(in: agent)
        return sectionCard(title: "秘密情報検出") {
            if detections.isEmpty {
                Text("既知 prefix にマッチする値はありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                SecretWarningCard(detections: detections)
            }
        }
    }

    private var nextRunSection: some View {
        sectionCard(title: "次回実行（推定）") {
            if let nextRun = NextRunCalculator.nextRun(for: agent) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nextRun.formatted(date: .abbreviated, time: .shortened))
                    if !agent.startCalendarInterval.isEmpty {
                        Text("StartCalendarInterval:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(StartCalendarFormatter.format(agent.startCalendarInterval), id: \.self) { line in
                            Text("• " + line)
                                .font(.caption.monospaced())
                        }
                    }
                    if let interval = agent.startInterval {
                        Text("StartInterval: \(interval) 秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("StartInterval / StartCalendarInterval 未設定。RunAtLoad または WatchPaths に依存している可能性。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var intentRecoverySection: some View {
        let intent = matchingIntents.first
        let steps = intent?.recoverySteps.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sectionCard(title: "Intent: 復旧手順") {
            if steps.isEmpty {
                Text("未記入。詳細ペインの Intent エディタに手順を書くと、ここに表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(steps)
                    .textSelection(.enabled)
            }
        }
    }

    private var tccSection: some View {
        sectionCard(title: "TCC / Full Disk Access") {
            VStack(alignment: .leading, spacing: 4) {
                Text("launchd 経由で実行されるスクリプトは、ユーザー対話セッションの TCC 権限を継承しません。次のような処理は失敗することが多い:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• `~/Library` 配下の別アプリデータ参照 → Full Disk Access 要")
                Text("• スクリーンショット / 画面収録 → Screen Recording 要")
                Text("• マイク / カメラ / 位置情報の利用")
                Text("権限は「システム設定 > プライバシーとセキュリティ」で sh / 実行ファイル に個別付与が必要。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .font(.caption)
        }
    }

    // MARK: - Helpers

    private var executableName: String {
        guard let path = resolvedExecutablePath else { return "unknown" }
        return (path as NSString).lastPathComponent
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.5))
        )
    }

    @ViewBuilder
    private func row(label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(minWidth: 120, alignment: .leading)
            Text(value)
                .font(mono ? .body.monospaced() : .body)
                .textSelection(.enabled)
        }
    }
}

/// 指定 path の末尾 N 行を表示する最小ビューア。
///
/// - 非同期で読み込み
/// - ファイルが存在しない場合は「未作成」表示
/// - 大きなファイルでもファイル末尾だけ読む（`FileHandle.seekToEnd` + chunk back）
private struct LogTailView: View {
    let title: String
    let path: String
    let maxLines: Int = 40

    @State private var state: LoadState = .idle

    enum LoadState {
        case idle
        case loading
        case loaded([String])
        case notFound
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            switch state {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .notFound:
                Text("(ファイル未作成)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .loaded(let lines):
                if lines.isEmpty {
                    Text("(空)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(isErrorLine(line) ? .red : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: path) { await load() }
    }

    private func isErrorLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("error") || lower.contains(" err ") || lower.hasPrefix("err:")
    }

    private func load() async {
        state = .loading
        state = await Self.readTail(path: path, maxLines: maxLines)
    }

    private static func readTail(path: String, maxLines: Int) async -> LoadState {
        await Task.detached(priority: .utility) { () -> LoadState in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                return .notFound
            }
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    return .failed("UTF-8 デコード失敗")
                }
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                let tail = lines.suffix(maxLines)
                return .loaded(Array(tail))
            } catch {
                return .failed("読み取り失敗: \(error.localizedDescription)")
            }
        }.value
    }
}
