import Foundation

/// plist の atomic write と書き込み前バックアップを1つの API に閉じ込める。
///
/// 呼び出し元（Phase 5 plist editor 等）は必ずこのクラス経由で書く。直接 `Data.write(to:)`
/// で既存ファイルを上書きするのは禁止。データ破壊が唯一許せない事故なので、この境界は
/// 絶対に死守する。
///
/// - Important: バックアップは destination が既に存在するときのみ作成する。
/// - Note: バックアップ先は `backupsRootURL`/`<label>`/`<yyyyMMdd-HHmmss>.plist` 形式。
/// - Note: 書き込みは destination と同一ディレクトリに tmp ファイルを作り、
///   `FileManager.replaceItemAt` で atomic 置換する。
public struct PlistAtomicWriter: Sendable {
    /// 書き込み前に取ったバックアップのメタデータ。
    ///
    /// 実ファイルは `plistPath` に保存済み。SwiftData (`BackupEntry`) への登録は
    /// 呼び出し元の責任。
    public struct BackupRecord: Sendable, Equatable {
        public let label: String
        public let timestamp: Date
        /// バックアップ先の絶対パス。
        public let plistPath: URL
        /// 呼び出し元が付ける理由文字列（例: "raw editor save"）。
        public let reason: String

        public init(label: String, timestamp: Date, plistPath: URL, reason: String) {
            self.label = label
            self.timestamp = timestamp
            self.plistPath = plistPath
            self.reason = reason
        }
    }

    /// 書き込み失敗の分類。失敗原因の絶対パスと下層のエラーメッセージを保持する。
    public enum WriteError: Error, Equatable {
        /// destination の親ディレクトリが存在しない。呼び出し側がパスを間違えている。
        case sourceDirectoryMissing(URL)
        /// バックアップ用サブディレクトリの作成に失敗。
        case backupDirectoryCreationFailed(URL, String)
        /// 既存ファイルのコピー（バックアップ）に失敗。
        case backupCopyFailed(URL, String)
        /// tmp ファイルへの書き込みに失敗。
        case tempWriteFailed(URL, String)
        /// tmp → destination の atomic 置換に失敗。
        case atomicReplaceFailed(URL, String)
    }

    private let backupsRootURL: URL
    private let clock: @Sendable () -> Date

    /// - Parameters:
    ///   - backupsRootURL: バックアップ保存先のルート。通常は
    ///     `~/Library/Application Support/Tender/backups`。
    ///   - clock: テスト用にタイムスタンプを注入可能にするためのクロック。
    public init(
        backupsRootURL: URL,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.backupsRootURL = backupsRootURL
        self.clock = clock
    }

    /// 呼び出しごとに参照する FileManager。`.default` は内部でスレッドセーフと文書化されている。
    private var fileManager: FileManager { .default }

    /// plist を書き込む。destination が既に存在するときは事前にバックアップを取る。
    ///
    /// アルゴリズム（順序が重要）:
    /// 1. destination の親ディレクトリが存在することを確認
    /// 2. destination が既存ならバックアップ（コピー）を先に取る
    /// 3. tmp ファイルに `data` を書き込む
    /// 4. `FileManager.replaceItemAt` で atomic 置換
    ///
    /// - Parameters:
    ///   - data: 書き込む plist の raw バイト列（XML / binary いずれも可）。
    ///   - destinationURL: 書き込み先の絶対パス。
    ///   - label: バックアップ先サブディレクトリ名（通常は LaunchAgent の `Label`）。
    ///   - reason: バックアップの理由文字列。`BackupRecord.reason` に入る。
    /// - Returns: 新規作成の場合 `nil`。既存を上書きした場合は `BackupRecord`。
    /// - Throws: `WriteError`
    @discardableResult
    public func write(
        _ data: Data,
        to destinationURL: URL,
        label: String,
        reason: String
    ) throws -> BackupRecord? {
        // 1. destination の親ディレクトリが存在するか
        let parentDir = destinationURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: parentDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw WriteError.sourceDirectoryMissing(parentDir)
        }

        // 2. バックアップ（destination が既存の場合のみ）
        let backupRecord: BackupRecord? = try makeBackupIfNeeded(
            destinationURL: destinationURL,
            label: label,
            reason: reason
        )

        // 3. tmp ファイル書き込み
        let tmpURL = parentDir.appendingPathComponent(".tender-write-\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmpURL, options: [.atomic])
        } catch {
            // tmp 書き込み失敗時は destination には手を付けていないので安全
            try? fileManager.removeItem(at: tmpURL)
            throw WriteError.tempWriteFailed(tmpURL, error.localizedDescription)
        }

        // 4. atomic 置換
        do {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: tmpURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            // 置換失敗時は tmp を掃除する。destination は元のまま（バックアップ済み）。
            try? fileManager.removeItem(at: tmpURL)
            throw WriteError.atomicReplaceFailed(destinationURL, error.localizedDescription)
        }

        return backupRecord
    }

    /// デフォルトの backupsRootURL を返すヘルパ。
    ///
    /// `~/Library/Application Support/Tender/backups` を返す。テストでは使わず、
    /// 呼び出し元（アプリ本体）の利便性のためのもの。
    public static func defaultBackupsRootURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return appSupport
            .appendingPathComponent("Tender", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
    }

    // MARK: - Private

    private func makeBackupIfNeeded(
        destinationURL: URL,
        label: String,
        reason: String
    ) throws -> BackupRecord? {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDir)
        guard exists, !isDir.boolValue else {
            return nil
        }

        let labelDir = backupsRootURL.appendingPathComponent(label, isDirectory: true)
        do {
            try fileManager.createDirectory(at: labelDir, withIntermediateDirectories: true)
        } catch {
            throw WriteError.backupDirectoryCreationFailed(labelDir, error.localizedDescription)
        }

        let now = clock()
        let filename = Self.timestampFormatter.string(from: now) + ".plist"
        let backupURL = labelDir.appendingPathComponent(filename)

        do {
            try fileManager.copyItem(at: destinationURL, to: backupURL)
        } catch {
            throw WriteError.backupCopyFailed(backupURL, error.localizedDescription)
        }

        return BackupRecord(
            label: label,
            timestamp: now,
            plistPath: backupURL,
            reason: reason
        )
    }

    /// `yyyyMMdd-HHmmss` フォーマッタ。`en_US_POSIX` / `TimeZone.current` / `Calendar.current`。
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.calendar = Calendar.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
