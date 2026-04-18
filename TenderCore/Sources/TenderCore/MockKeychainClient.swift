import Foundation

/// テスト用の `KeychainClient` 実装。呼び出しを記録し、事前に enqueue したレスポンスを FIFO で返す。
///
/// - キューが空の状態で呼ばれたら `fatalError`。セットアップ漏れを早く検知するため意図的に厳しくしている。
/// - 種別不一致（例: `add` 用のキューから `find` を取ろうとする）も `fatalError`。
public actor MockKeychainClient: KeychainClient {
    /// mock に記録される呼び出し種別。
    public enum Call: Equatable, Sendable {
        case add(KeychainCall, password: String, overwrite: Bool)
        case find(KeychainCall)
        case delete(KeychainCall)
    }

    private enum Response: Sendable {
        case addSuccess
        case findSuccess(password: String)
        case deleteSuccess
        case error(KeychainError)
    }

    private var queue: [Response] = []
    private var calls: [Call] = []

    public init() {}

    // MARK: - enqueue

    public func enqueueAddSuccess() {
        queue.append(.addSuccess)
    }

    public func enqueueFindSuccess(password: String) {
        queue.append(.findSuccess(password: password))
    }

    public func enqueueDeleteSuccess() {
        queue.append(.deleteSuccess)
    }

    public func enqueueError(_ error: KeychainError) {
        queue.append(.error(error))
    }

    // MARK: - 検証用

    public func recordedCalls() -> [Call] {
        calls
    }

    // MARK: - KeychainClient

    public func add(service: String, account: String, password: String, overwrite: Bool) async throws {
        calls.append(.add(.init(service: service, account: account), password: password, overwrite: overwrite))
        guard !queue.isEmpty else {
            fatalError("MockKeychainClient: add called but queue is empty")
        }
        let response = queue.removeFirst()
        switch response {
        case .addSuccess:
            return
        case .error(let error):
            throw error
        case .findSuccess, .deleteSuccess:
            fatalError("MockKeychainClient: add expected .addSuccess response, got \(response)")
        }
    }

    public func find(service: String, account: String) async throws -> String {
        calls.append(.find(.init(service: service, account: account)))
        guard !queue.isEmpty else {
            fatalError("MockKeychainClient: find called but queue is empty")
        }
        let response = queue.removeFirst()
        switch response {
        case .findSuccess(let password):
            return password
        case .error(let error):
            throw error
        case .addSuccess, .deleteSuccess:
            fatalError("MockKeychainClient: find expected .findSuccess response, got \(response)")
        }
    }

    public func delete(service: String, account: String) async throws {
        calls.append(.delete(.init(service: service, account: account)))
        guard !queue.isEmpty else {
            fatalError("MockKeychainClient: delete called but queue is empty")
        }
        let response = queue.removeFirst()
        switch response {
        case .deleteSuccess:
            return
        case .error(let error):
            throw error
        case .addSuccess, .findSuccess:
            fatalError("MockKeychainClient: delete expected .deleteSuccess response, got \(response)")
        }
    }
}
