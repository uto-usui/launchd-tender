import SwiftUI
import TenderCore

struct ContentView: View {
    @State private var store = LaunchAgentsStore()
    @State private var selection: LaunchAgent.ID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Tender")
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detail
        }
        .task {
            await store.reload()
        }
        .overlay(alignment: .top) {
            if let result = store.lastActionResult {
                ActionToastView(result: result) { store.dismissActionResult() }
                    .task(id: result) {
                        // 成功バナーは 3 秒で自動 dismiss。失敗は残して明示的に閉じさせる。
                        guard result.isSuccess else { return }
                        try? await Task.sleep(for: .seconds(3))
                        if store.lastActionResult == result {
                            store.dismissActionResult()
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: store.lastActionResult)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if store.isLoading && store.agents.isEmpty {
            ProgressView("読み込み中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.agents.isEmpty {
            ContentUnavailableView(
                "LaunchAgent が見つかりません",
                systemImage: "tray",
                description: Text("~/Library/LaunchAgents に .plist が置かれていません。")
            )
        } else {
            List(store.agents, selection: $selection) { agent in
                AgentRow(agent: agent, status: store.status(for: agent))
                    .tag(agent.id)
            }
            .refreshable { await store.reload() }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selection, let agent = store.agents.first(where: { $0.id == selection }) {
            AgentDetailView(
                agent: agent,
                status: store.status(for: agent),
                runningAction: store.runningAction,
                onEnable: { Task { await store.enable(agent) } },
                onDisable: { Task { await store.disable(agent) } },
                onKickstart: { Task { await store.kickstart(agent, kill: false) } },
                onKickstartKill: { Task { await store.kickstart(agent, kill: true) } }
            )
        } else {
            ContentUnavailableView(
                "ジョブを選択",
                systemImage: "gearshape.2",
                description: Text("サイドバーから LaunchAgent を選んでください。")
            )
        }
    }
}

private struct AgentRow: View {
    let agent: LaunchAgent
    let status: AgentStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.label)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let summary = summaryLine {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            AgentStatusBadge(status: status, compact: true)
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String? {
        if let interval = agent.startInterval {
            return "StartInterval: \(interval)s"
        }
        if !agent.startCalendarInterval.isEmpty {
            return "StartCalendarInterval (\(agent.startCalendarInterval.count) entries)"
        }
        if !agent.watchPaths.isEmpty {
            return "WatchPaths: \(agent.watchPaths.count)"
        }
        if agent.runAtLoad {
            return "RunAtLoad"
        }
        return nil
    }
}

private struct AgentDetailView: View {
    let agent: LaunchAgent
    let status: AgentStatus
    let runningAction: AgentActionKind?
    let onEnable: () -> Void
    let onDisable: () -> Void
    let onKickstart: () -> Void
    let onKickstartKill: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.label)
                        .font(.title2).bold()
                        .textSelection(.enabled)
                    Spacer()
                    AgentStatusBadge(status: status)
                }

                if let sourcePath = agent.sourcePath {
                    Text(sourcePath.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                actionBar

                Divider()

                if !agent.programArguments.isEmpty {
                    DetailSection(title: "ProgramArguments") {
                        Text(agent.programArguments.joined(separator: " "))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let interval = agent.startInterval {
                    DetailSection(title: "StartInterval") {
                        Text("\(interval) 秒")
                    }
                }

                if !agent.startCalendarInterval.isEmpty {
                    DetailSection(title: "StartCalendarInterval") {
                        ForEach(Array(agent.startCalendarInterval.enumerated()), id: \.offset) { _, entry in
                            Text(describe(entry))
                                .font(.body.monospaced())
                        }
                    }
                }

                if !agent.environmentVariables.isEmpty {
                    DetailSection(title: "EnvironmentVariables") {
                        ForEach(agent.environmentVariables.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(alignment: .firstTextBaseline) {
                                Text(key).font(.body.monospaced().bold())
                                Text("=").foregroundStyle(.secondary)
                                Text(value).font(.body.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func describe(_ entry: StartCalendarEntry) -> String {
        var parts: [String] = []
        if let h = entry.hour { parts.append("H:\(h)") }
        if let m = entry.minute { parts.append("M:\(m)") }
        if let d = entry.day { parts.append("D:\(d)") }
        if let w = entry.weekday { parts.append("W:\(w)") }
        if let mo = entry.month { parts.append("Mo:\(mo)") }
        return parts.isEmpty ? "(任意時刻)" : parts.joined(separator: " ")
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 8) {
            switch status {
            case .disabled:
                Button("有効化") { onEnable() }
                    .disabled(runningAction != nil)
            default:
                Button("無効化") { onDisable() }
                    .disabled(runningAction != nil)
            }

            Button {
                onKickstart()
            } label: {
                Label("手動実行", systemImage: "play.fill")
            }
            .disabled(runningAction != nil)

            Button {
                onKickstartKill()
            } label: {
                Label("再起動", systemImage: "arrow.clockwise.circle")
            }
            .disabled(runningAction != nil)
            .help("launchctl kickstart -k で既存プロセスを kill してから起動する")

            if let running = runningAction {
                ProgressView()
                    .controlSize(.small)
                Text("\(running.verb) 実行中…")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer()
        }
        .buttonStyle(.bordered)
    }
}

private struct DetailSection<Content: View>: View {
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

#Preview {
    ContentView()
}
