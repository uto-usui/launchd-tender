import Foundation

/// 平文 env を Keychain に移すために必要な一連の変更をまとめた immutable な計画。
///
/// - `make(...)` で生成、`KeychainMigrationService` が `execute(plan:)` する
/// - UI は plist 差分 / wrapper script をプレビュー表示するのに使う
/// - 実行副作用はゼロ（pure）。Keychain も file system も触らない
public struct KeychainMigrationPlan: Sendable {
    public enum MakeError: Error, Equatable, Sendable {
        case emptySelection
        case unknownEnvKey(String)
        case missingSourcePath
        case emptyProgramArguments
    }

    /// Keychain へ書き込むひとつ分。
    public struct KeychainWrite: Sendable, Hashable {
        public let service: String
        public let account: String
        public let password: String

        public init(service: String, account: String, password: String) {
            self.service = service
            self.account = account
            self.password = password
        }
    }

    /// plist に書き加える Tender 管理用メタキー。launchd は未知キーを無視する。
    public struct MetaKeys: Sendable, Hashable {
        public let tenderManaged: Bool
        public let tenderWrappedEnvs: [String]
        public let tenderOriginalProgramArguments: [String]

        public init(tenderWrappedEnvs: [String], tenderOriginalProgramArguments: [String]) {
            self.tenderManaged = true
            self.tenderWrappedEnvs = tenderWrappedEnvs
            self.tenderOriginalProgramArguments = tenderOriginalProgramArguments
        }

        /// plist 書き換え時にマージする辞書。
        public var asDictionary: [String: Any] {
            [
                "TenderManaged": tenderManaged,
                "TenderWrappedEnvs": tenderWrappedEnvs,
                "TenderOriginalProgramArguments": tenderOriginalProgramArguments
            ]
        }
    }

    public let agent: LaunchAgent
    public let selectedEnvs: [String]
    public let wrapperURL: URL
    public let wrapperScript: String
    public let keychainWrites: [KeychainWrite]
    public let newProgramArguments: [String]
    public let newEnvironmentVariables: [String: String]
    public let metaKeys: MetaKeys

    private init(
        agent: LaunchAgent, selectedEnvs: [String], wrapperURL: URL, wrapperScript: String,
        keychainWrites: [KeychainWrite], newProgramArguments: [String],
        newEnvironmentVariables: [String: String], metaKeys: MetaKeys
    ) {
        self.agent = agent
        self.selectedEnvs = selectedEnvs
        self.wrapperURL = wrapperURL
        self.wrapperScript = wrapperScript
        self.keychainWrites = keychainWrites
        self.newProgramArguments = newProgramArguments
        self.newEnvironmentVariables = newEnvironmentVariables
        self.metaKeys = metaKeys
    }

    /// 計画を生成する。失敗すれば `MakeError` を投げる。
    public static func make(
        agent: LaunchAgent,
        selectedEnvs: [String],
        wrapperDirectory: URL,
        keychainService: String,
        now: Date
    ) throws -> KeychainMigrationPlan {
        guard !selectedEnvs.isEmpty else { throw MakeError.emptySelection }
        guard let sourcePath = agent.sourcePath else { throw MakeError.missingSourcePath }
        guard !agent.programArguments.isEmpty else { throw MakeError.emptyProgramArguments }

        for key in selectedEnvs {
            if agent.environmentVariables[key] == nil {
                throw MakeError.unknownEnvKey(key)
            }
        }

        let wrapperURL = wrapperDirectory.appendingPathComponent("\(agent.label).sh")

        let wrapperScript = try WrapperScriptBuilder.buildOrThrow(
            label: agent.label,
            envKeys: selectedEnvs,
            programArguments: agent.programArguments,
            keychainService: keychainService,
            generatedAt: now,
            sourcePlistPath: sourcePath.path
        )

        let keychainWrites = selectedEnvs.map { key in
            KeychainWrite(
                service: keychainService,
                account: "\(agent.label).\(key)",
                password: agent.environmentVariables[key]!
            )
        }

        let newProgramArguments = ["/bin/bash", wrapperURL.path]

        // 選択された env を EnvironmentVariables から除去。他のキーは保持。
        var newEnv = agent.environmentVariables
        for key in selectedEnvs {
            newEnv.removeValue(forKey: key)
        }

        let metaKeys = MetaKeys(
            tenderWrappedEnvs: selectedEnvs,
            tenderOriginalProgramArguments: agent.programArguments
        )

        return KeychainMigrationPlan(
            agent: agent,
            selectedEnvs: selectedEnvs,
            wrapperURL: wrapperURL,
            wrapperScript: wrapperScript,
            keychainWrites: keychainWrites,
            newProgramArguments: newProgramArguments,
            newEnvironmentVariables: newEnv,
            metaKeys: metaKeys
        )
    }
}
