import Foundation

/// ジョブの可視状態。`print-disabled` の結果 + ファイル存在・実行属性から合成する。
///
/// CLAUDE.md ガードレール 1 に沿い、`launchctl print` のパースには依存しない。
/// 正のデータ源は `print-disabled` の集合 / 実行ファイルの属性 / plist のキー。
public enum AgentStatus: Sendable, Equatable {
    /// ジョブが有効で、実行ファイルも解決できている状態。
    case enabled
    /// `print-disabled` 集合に含まれる。
    case disabled
    /// ProgramArguments / Program から決まる実行ファイルが存在しない。
    case missingExecutable(path: String)
    /// 実行ファイルは存在するが、実行可能属性が立っていない。
    case notExecutable(path: String)
    /// `ProgramArguments` も `Program` も未設定。launchd.plist(5) 的には違反だが、検出だけする。
    case noProgramArguments
}

/// `AgentStatus` を算出する純粋関数。ファイルアクセスは closure で注入可能。
public enum AgentStatusEvaluator {
    /// テスタブルなエントリ。`fileExists` / `isExecutable` は呼び出し元が注入する。
    public static func evaluate(
        agent: LaunchAgent,
        disabledLabels: Set<String>,
        fileExists: (String) -> Bool,
        isExecutable: (String) -> Bool
    ) -> AgentStatus {
        if disabledLabels.contains(agent.label) {
            return .disabled
        }

        guard let executablePath = resolveExecutablePath(agent: agent) else {
            return .noProgramArguments
        }

        guard fileExists(executablePath) else {
            return .missingExecutable(path: executablePath)
        }

        guard isExecutable(executablePath) else {
            return .notExecutable(path: executablePath)
        }

        return .enabled
    }

    /// `FileManager` 経由のデフォルト実装。アプリ本体はこちらを使う。
    public static func evaluate(
        agent: LaunchAgent,
        disabledLabels: Set<String>,
        fileManager: FileManager = .default
    ) -> AgentStatus {
        evaluate(
            agent: agent,
            disabledLabels: disabledLabels,
            fileExists: { fileManager.fileExists(atPath: $0) },
            isExecutable: { fileManager.isExecutableFile(atPath: $0) }
        )
    }

    // MARK: - Internal

    /// `ProgramArguments` 優先、次に `Program`。どちらもない場合は nil。
    static func resolveExecutablePath(agent: LaunchAgent) -> String? {
        if let first = agent.programArguments.first, !first.isEmpty {
            return first
        }
        if let program = agent.program, !program.isEmpty {
            return program
        }
        return nil
    }
}
