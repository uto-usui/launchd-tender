import SwiftUI
import TenderCore

/// 指定 agent の実行ファイル basename で `log show` をかけ、Unified Log を一覧表示する。
///
/// - StandardOut/ErrorPath に出ない情報（dyld エラー、sanitizer 出力、system-level failure）を補完
/// - エラー行は red tint、`messageType == Fault` は bold
/// - 「更新」ボタンで再 fetch、期間は 1h 固定（TroubleshootingSheet スコープで十分）
struct UnifiedLogView: View {
    let agent: LaunchAgent

    @State private var lines: [LogLine] = []
    @State private var phase: Phase = .idle
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private let lastSeconds = 3600
    private let maxLines = 100

    /// `programArguments[0]` または `program` から basename を抽出。
    private var processName: String? {
        if let first = agent.programArguments.first, !first.isEmpty {
            return (first as NSString).lastPathComponent
        }
        if let p = agent.program, !p.isEmpty {
            return (p as NSString).lastPathComponent
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .task { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let name = processName {
                Text("process == \"\(name)\" の直近 1h")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(phase == .loading || processName == nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("log show 実行中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Text(errorMessage ?? "不明なエラー")
                .font(.caption)
                .foregroundStyle(.red)
        case .loaded:
            if processName == nil {
                Text("ProgramArguments / Program が空のため絞り込めません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if lines.isEmpty {
                Text("該当ログなし。process 名の不一致か、実行されていない可能性があります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                linesView
            }
        }
    }

    private var linesView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(line.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let cat = line.category {
                        Text(cat)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(line.message)
                        .font(.caption.monospaced())
                        .foregroundStyle(line.level.isError ? Color.red : .primary)
                        .fontWeight(line.level == .fault ? .bold : .regular)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func refresh() async {
        guard let name = processName else {
            phase = .loaded
            lines = []
            return
        }
        phase = .loading
        errorMessage = nil
        do {
            let client = ProcessUnifiedLogClient()
            let result = try await client.fetch(
                process: name, lastSeconds: lastSeconds, maxLines: maxLines
            )
            lines = result
            phase = .loaded
        } catch {
            errorMessage = String(describing: error)
            phase = .failed
        }
    }
}
