import Foundation

/// Keychain 操作の抽象。`/usr/bin/security` を Process 実行する本番実装とテスト用 Mock を差し替え可能にする。
///
/// Tender は generic password アイテムのみを扱う（internet password は使わない）。
/// service / account / password の 3 つ組を CRUD する最小インタフェース。
public protocol KeychainClient: Sendable {
    /// 新規追加、または `overwrite == true` のとき `-U` で上書き。
    /// - Throws: `KeychainError.duplicateItem`（`overwrite == false` で既存があった場合）
    func add(service: String, account: String, password: String, overwrite: Bool) async throws

    /// 既存アイテムのパスワードを取り出す。
    /// - Throws: `KeychainError.notFound` が該当なし時。
    func find(service: String, account: String) async throws -> String

    /// 既存アイテムを削除する。
    /// - Throws: `KeychainError.notFound` が該当なし時。
    func delete(service: String, account: String) async throws
}

/// `KeychainClient` 呼び出しの service / account ペア。Mock の履歴検証用。
public struct KeychainCall: Sendable, Hashable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

/// `KeychainClient` の失敗理由。
public enum KeychainError: Error, Equatable, Sendable {
    /// 該当する service / account のアイテムが存在しない（security exit 44）。
    case notFound

    /// `overwrite == false` で追加しようとしたが既存があった（security exit 45）。
    case duplicateItem

    /// `/usr/bin/security` が非 0 exit した。exit code と stderr を同梱。
    case commandFailed(exitCode: Int32, stderr: String)

    /// `/usr/bin/security` が見つからない、または起動できない。
    case executableNotFound

    /// タイムアウト。
    case timeout
}
