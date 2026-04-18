import Foundation

/// `KeychainDetachPlan` を実際に適用する orchestrator。
///
/// 実行順序:
/// 1. 既存 plist を読む
/// 2. plist を atomic 書き換え（meta key 除去 + ProgramArguments 復元）
/// 3. wrapper script を削除（存在しなくても最適エフォート）
/// 4. `deleteKeychainEntries == true` なら Keychain エントリ削除
///
/// 順序は detach の性質上 rollback は考えない:
/// - plist 書き戻し（これが成功すれば最悪 wrapper が残っても launchctl は元の argv で動く）
/// - wrapper / Keychain 削除は「掃除」なので失敗しても致命ではない
public actor KeychainDetachService {
    public struct Receipt: Sendable {
        public let backup: PlistAtomicWriter.BackupRecord?
        public let wrapperDeleted: Bool
        public let keychainAccountsDeleted: [KeychainCall]
    }

    public enum ServiceError: Error, Sendable {
        case plistReadFailed(String)
    }

    private let keychain: any KeychainClient
    private let plistWriter: PlistAtomicWriter
    private let fileWriter: any WrapperFileWriter

    public init(
        keychain: any KeychainClient,
        plistWriter: PlistAtomicWriter,
        fileWriter: any WrapperFileWriter = FileSystemWrapperFileWriter()
    ) {
        self.keychain = keychain
        self.plistWriter = plistWriter
        self.fileWriter = fileWriter
    }

    public func execute(plan: KeychainDetachPlan) async throws -> Receipt {
        guard let sourceURL = plan.agent.sourcePath else {
            throw KeychainDetachPlan.MakeError.missingSourcePath
        }

        let originalData: Data
        do {
            originalData = try Data(contentsOf: sourceURL)
        } catch {
            throw ServiceError.plistReadFailed(error.localizedDescription)
        }

        // Step 1: plist 書き戻し（失敗したらここで止まる、掃除フェーズに進まない）
        let newData = try DetachPlistComposer.compose(originalData: originalData, plan: plan)
        let backup = try plistWriter.write(
            newData, to: sourceURL,
            label: plan.agent.label, reason: "keychain-detach"
        )

        // Step 2: wrapper 削除（掃除、失敗しても throw しない）
        var wrapperDeleted = false
        do {
            try await fileWriter.delete(at: plan.wrapperURL)
            wrapperDeleted = true
        } catch {
            // 存在しない / 権限エラーでも plist は既に戻っているので続行
        }

        // Step 3: Keychain エントリ削除（オプション）
        var deletedAccounts: [KeychainCall] = []
        if plan.deleteKeychainEntries {
            for account in plan.keychainAccountsToDelete {
                do {
                    try await keychain.delete(
                        service: account.service, account: account.account
                    )
                    deletedAccounts.append(account)
                } catch {
                    // 見つからない等は黙って skip — 残っていたらユーザーが Keychain Access で消せる
                }
            }
        }

        return Receipt(
            backup: backup,
            wrapperDeleted: wrapperDeleted,
            keychainAccountsDeleted: deletedAccounts
        )
    }
}
