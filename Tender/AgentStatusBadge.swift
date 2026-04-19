import SwiftUI
import TenderCore

/// `AgentStatus` の視覚表現。SF Symbol + 色で状態を一瞥で伝える。
struct AgentStatusBadge: View {
    let status: AgentStatus
    var compact: Bool = false

    var body: some View {
        Label {
            if !compact {
                Text(title)
            }
        } icon: {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .labelStyle(.titleAndIcon)
        .font(compact ? .caption2 : .caption)
        .foregroundStyle(tint)
        .help(detailedDescription)
    }

    private var symbol: String {
        switch status {
        case .enabled: "leaf.fill"
        case .disabled: "pause.circle.fill"
        case .missingExecutable: "questionmark.circle"
        case .notExecutable: "lock.circle.fill"
        case .noProgramArguments: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .enabled: .green
        case .disabled: .secondary
        case .missingExecutable, .notExecutable, .noProgramArguments: .yellow
        }
    }

    private var title: String {
        switch status {
        case .enabled: "有効"
        case .disabled: "無効"
        case .missingExecutable: "実行ファイルなし"
        case .notExecutable: "実行不可"
        case .noProgramArguments: "引数未設定"
        }
    }

    private var detailedDescription: String {
        switch status {
        case .enabled: "launchctl print-disabled に含まれていません。実行ファイルは解決できます。"
        case .disabled: "launchctl print-disabled で disabled と表示されています。"
        case .missingExecutable(let path): "実行ファイルが見つかりません: \(path)"
        case .notExecutable(let path): "実行ファイルは存在しますが、実行可能属性が立っていません: \(path)"
        case .noProgramArguments: "ProgramArguments も Program も未設定です。launchd.plist(5) 的には構成不備。"
        }
    }
}

#Preview("states") {
    VStack(alignment: .leading, spacing: 8) {
        AgentStatusBadge(status: .enabled)
        AgentStatusBadge(status: .disabled)
        AgentStatusBadge(status: .missingExecutable(path: "/opt/ghost"))
        AgentStatusBadge(status: .notExecutable(path: "/opt/script.sh"))
        AgentStatusBadge(status: .noProgramArguments)
    }
    .padding()
}
