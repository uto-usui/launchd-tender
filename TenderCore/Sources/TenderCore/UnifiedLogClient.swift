import Foundation

/// Unified Log (`log show`) を取得するクライアント。
///
/// Tender では user agent の stdout / stderr ファイルに書かれない情報（例: dyld エラー、
/// `FunctionEvaluator` からの sanitizer 出力）を補完するために使う。
public protocol UnifiedLogClient: Sendable {
    /// 指定 process の直近ログを取得する。
    /// - Parameters:
    ///   - process: executable basename（例: `python3`、`node`）
    ///   - lastSeconds: 遡る秒数（例: 3600 で 1h）
    ///   - maxLines: 返却上限（超過分は UI 側でスクロールさせない、実行時間を抑える）
    func fetch(process: String, lastSeconds: Int, maxLines: Int) async throws -> [LogLine]
}

public struct LogLine: Sendable, Hashable, Identifiable {
    /// ndjson の `traceID` と timestamp の組で実質ユニーク。UI の List id 用。
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(message.hashValue)" }
    public let timestamp: Date
    public let processImagePath: String?
    public let message: String
    public let category: String?
    public let subsystem: String?
    public let level: LogLineLevel

    public init(
        timestamp: Date,
        processImagePath: String? = nil,
        message: String,
        category: String? = nil,
        subsystem: String? = nil,
        level: LogLineLevel = .default
    ) {
        self.timestamp = timestamp
        self.processImagePath = processImagePath
        self.message = message
        self.category = category
        self.subsystem = subsystem
        self.level = level
    }
}

public enum LogLineLevel: String, Sendable, Equatable {
    case `default`
    case info
    case debug
    case error
    case fault
    case unknown

    public var isError: Bool { self == .error || self == .fault }
}

public enum UnifiedLogError: Error, Equatable, Sendable {
    case executableNotFound
    case commandFailed(exitCode: Int32, stderr: String)
    case timeout
    case parseFailed(String)
}
