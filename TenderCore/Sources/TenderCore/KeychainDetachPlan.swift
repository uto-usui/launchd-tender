import Foundation

/// Keychain ラッパ管理を解除する（元の plist に戻す）ための計画。
///
/// - ProgramArguments を `TenderOriginalProgramArguments` で戻す
/// - meta key 3 つを plist から除去
/// - wrapper script を file system から削除
/// - Keychain エントリは既定で残す（再移行時に値を再入力不要）、削除する場合はオプション
///
/// 実行は `KeychainDetachService` が担当する。
public struct KeychainDetachPlan: Sendable {
    public enum MakeError: Error, Equatable, Sendable {
        case notManaged
        case missingSourcePath
        case missingOriginalProgramArguments
    }

    public let agent: LaunchAgent
    public let wrapperURL: URL
    public let restoredProgramArguments: [String]
    public let keychainAccountsToDelete: [KeychainCall]
    public let deleteKeychainEntries: Bool

    private init(
        agent: LaunchAgent, wrapperURL: URL,
        restoredProgramArguments: [String],
        keychainAccountsToDelete: [KeychainCall],
        deleteKeychainEntries: Bool
    ) {
        self.agent = agent
        self.wrapperURL = wrapperURL
        self.restoredProgramArguments = restoredProgramArguments
        self.keychainAccountsToDelete = keychainAccountsToDelete
        self.deleteKeychainEntries = deleteKeychainEntries
    }

    public static func make(
        agent: LaunchAgent,
        wrapperDirectory: URL,
        keychainService: String,
        deleteKeychainEntries: Bool
    ) throws -> KeychainDetachPlan {
        guard agent.tenderManaged else { throw MakeError.notManaged }
        guard agent.sourcePath != nil else { throw MakeError.missingSourcePath }
        guard !agent.tenderOriginalProgramArguments.isEmpty else {
            throw MakeError.missingOriginalProgramArguments
        }

        let wrapperURL = wrapperDirectory.appendingPathComponent("\(agent.label).sh")
        let accounts = agent.tenderWrappedEnvs.map { env in
            KeychainCall(service: keychainService, account: "\(agent.label).\(env)")
        }

        return KeychainDetachPlan(
            agent: agent,
            wrapperURL: wrapperURL,
            restoredProgramArguments: agent.tenderOriginalProgramArguments,
            keychainAccountsToDelete: accounts,
            deleteKeychainEntries: deleteKeychainEntries
        )
    }
}
