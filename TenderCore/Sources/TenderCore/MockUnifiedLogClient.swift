import Foundation

/// テスト用の `UnifiedLogClient`。enqueue した結果を FIFO で返す。
public actor MockUnifiedLogClient: UnifiedLogClient {
    private var queue: [Result<[LogLine], Error>] = []
    public private(set) var fetchCalls: [FetchCall] = []

    public struct FetchCall: Sendable, Equatable {
        public let process: String
        public let lastSeconds: Int
        public let maxLines: Int
    }

    public init() {}

    public func enqueueSuccess(_ lines: [LogLine]) {
        queue.append(.success(lines))
    }

    public func enqueueError(_ error: Error) {
        queue.append(.failure(error))
    }

    public func fetch(process: String, lastSeconds: Int, maxLines: Int) async throws -> [LogLine] {
        fetchCalls.append(.init(process: process, lastSeconds: lastSeconds, maxLines: maxLines))
        guard !queue.isEmpty else {
            fatalError("MockUnifiedLogClient: fetch called but queue is empty")
        }
        return try queue.removeFirst().get()
    }
}
