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
            AgentDetailView(agent: agent, status: store.status(for: agent))
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
