import Foundation

/// wrapper script ファイルの書き出し / 削除を抽象化する。
///
/// 本番は `FileSystemWrapperFileWriter`（実際にディスクに書く）、
/// テストは `InMemoryWrapperFileWriter`（actor、記録のみ）を使う。
public protocol WrapperFileWriter: Sendable {
    /// 親ディレクトリが無ければ作り、chmod 700 で書き出す。
    func write(_ content: String, to url: URL) async throws

    /// 存在しなければエラー（rollback では呼び出し側で `try?` する）。
    func delete(at url: URL) async throws
}

/// 実ディスクに書き出す本番実装。
public struct FileSystemWrapperFileWriter: WrapperFileWriter {
    public init() {}

    public func write(_ content: String, to url: URL) async throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        // 所有者のみ実行 / 読み書き。group / world からは完全に隠す。
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    public func delete(at url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }
}

/// テスト用の in-memory 実装。書き込み / 削除を記録し、必要なら enqueue したエラーを投げる。
public actor InMemoryWrapperFileWriter: WrapperFileWriter {
    public private(set) var written: [URL: String] = [:]
    public private(set) var deletedURLs: [URL] = []
    private var nextWriteError: Error?
    private var nextDeleteError: Error?

    public init() {}

    public func enqueueWriteError(_ error: Error) {
        nextWriteError = error
    }

    public func enqueueDeleteError(_ error: Error) {
        nextDeleteError = error
    }

    public func write(_ content: String, to url: URL) async throws {
        if let error = nextWriteError {
            nextWriteError = nil
            throw error
        }
        written[url] = content
    }

    public func delete(at url: URL) async throws {
        if let error = nextDeleteError {
            nextDeleteError = nil
            throw error
        }
        deletedURLs.append(url)
        written.removeValue(forKey: url)
    }
}
