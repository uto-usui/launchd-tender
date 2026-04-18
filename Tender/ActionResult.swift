import Foundation

/// LaunchAgent に対して行った launchctl 操作の種別。
enum AgentActionKind: Equatable {
    case enable
    case disable
    case kickstart
    case kickstartKill  // -k で既存プロセス kill + 再起動

    var verb: String {
        switch self {
        case .enable: "有効化"
        case .disable: "無効化"
        case .kickstart: "手動実行"
        case .kickstartKill: "再起動"
        }
    }
}

/// アクションの結果。UI は成功トーストまたは失敗バナーに写す。
enum AgentActionResult: Equatable {
    case success(label: String, kind: AgentActionKind)
    case failure(label: String, kind: AgentActionKind, exitCode: Int32, stderr: String)

    var label: String {
        switch self {
        case .success(let label, _), .failure(let label, _, _, _): label
        }
    }

    var kind: AgentActionKind {
        switch self {
        case .success(_, let kind), .failure(_, let kind, _, _): kind
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
