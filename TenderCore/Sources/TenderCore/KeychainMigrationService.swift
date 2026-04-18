import Foundation

/// `KeychainMigrationPlan` を実際に適用する orchestrator。
///
/// 実行順序:
/// 1. 既存 plist を読み込む（rollback 後に戻す必要はない — `PlistAtomicWriter` が書き換え前バックアップを取る）
/// 2. Keychain に全 write を追加（`overwrite: true`）
/// 3. wrapper script をディスクに書き出す
/// 4. plist を atomic 書き換え（`PlistAtomicWriter` 経由でバックアップ自動取得）
///
/// いずれかで失敗した場合は逆順に rollback:
/// - wrapper を削除（書いていれば）
/// - Keychain エントリを削除（追加した分だけ）
///
/// plist 書き込みは最後なので、失敗しても `PlistAtomicWriter` が destination を触らず、
/// 中間状態は発生しない。
public actor KeychainMigrationService {
    public struct Receipt: Sendable, Equatable {
        public let backup: PlistAtomicWriter.BackupRecord?
        public let wrapperURL: URL
        public let writtenAccounts: [KeychainCall]

        public init(backup: PlistAtomicWriter.BackupRecord?, wrapperURL: URL, writtenAccounts: [KeychainCall]) {
            self.backup = backup
            self.wrapperURL = wrapperURL
            self.writtenAccounts = writtenAccounts
        }
    }

    public enum ServiceError: Error, Equatable, Sendable {
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

    /// 本番アプリが使う wrapper script 保存ディレクトリ。
    ///
    /// `~/Library/Application Support/Tender/wrappers/` を返す。存在しなければ作成する。
    public static func defaultWrapperDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = appSupport
            .appendingPathComponent("Tender", isDirectory: true)
            .appendingPathComponent("wrappers", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func execute(plan: KeychainMigrationPlan) async throws -> Receipt {
        guard let sourceURL = plan.agent.sourcePath else {
            // Plan.make で弾いているので通常到達しない
            throw KeychainMigrationPlan.MakeError.missingSourcePath
        }

        let originalData: Data
        do {
            originalData = try Data(contentsOf: sourceURL)
        } catch {
            throw ServiceError.plistReadFailed(error.localizedDescription)
        }

        var addedAccounts: [KeychainCall] = []
        var wrapperWritten = false

        do {
            // Step 1: Keychain 追加
            for write in plan.keychainWrites {
                try await keychain.add(
                    service: write.service,
                    account: write.account,
                    password: write.password,
                    overwrite: true
                )
                addedAccounts.append(.init(service: write.service, account: write.account))
            }

            // Step 2: wrapper 書き出し
            try await fileWriter.write(plan.wrapperScript, to: plan.wrapperURL)
            wrapperWritten = true

            // Step 3: plist 書き換え
            let newData = try MigrationPlistComposer.compose(
                originalData: originalData, plan: plan
            )
            let backup = try plistWriter.write(
                newData, to: sourceURL,
                label: plan.agent.label, reason: "keychain-migration"
            )

            return Receipt(
                backup: backup,
                wrapperURL: plan.wrapperURL,
                writtenAccounts: addedAccounts
            )
        } catch {
            if wrapperWritten {
                try? await fileWriter.delete(at: plan.wrapperURL)
            }
            for call in addedAccounts.reversed() {
                try? await keychain.delete(service: call.service, account: call.account)
            }
            throw error
        }
    }
}
