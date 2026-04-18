import Foundation

/// テスト用の `LaunchctlClient` 実装。呼び出しを記録し、事前に enqueue したレスポンスを FIFO で返す。
///
/// - キューが空の状態で呼ばれたら `fatalError`。セットアップ漏れを早く検知するため意図的に厳しくしている。
/// - `printDisabled` も同じキューから取り、種別不一致なら `fatalError`。
public actor MockLaunchctlClient: LaunchctlClient {
    /// mock に記録される呼び出し種別。
    public enum Call: Equatable, Sendable {
        case enable(String)
        case disable(String)
        case kickstart(String, KickstartOptions)
        case bootstrap(URL)
        case bootout(String)
        case printDisabled
    }

    /// キューに詰める応答の種別。
    private enum Response: Sendable {
        case result(LaunchctlResult)
        case printDisabled(labels: Set<String>, raw: LaunchctlResult)
        case error(LaunchctlError)
    }

    private var queue: [Response] = []
    private var calls: [Call] = []

    public init() {}

    // MARK: - enqueue

    /// 成功結果を enqueue する。デフォルトは exit code 0 / 空 stdout・stderr。
    public func enqueueSuccess(
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = ""
    ) {
        queue.append(.result(LaunchctlResult(exitCode: exitCode, stdout: stdout, stderr: stderr)))
    }

    /// 任意の `LaunchctlResult` を enqueue する。
    public func enqueue(result: LaunchctlResult) {
        queue.append(.result(result))
    }

    /// `printDisabled` 用の応答を enqueue する。
    public func enqueuePrintDisabled(
        labels: Set<String>,
        raw: LaunchctlResult = LaunchctlResult(exitCode: 0, stdout: "", stderr: "")
    ) {
        queue.append(.printDisabled(labels: labels, raw: raw))
    }

    /// 次の呼び出しで投げるエラーを enqueue する。
    public func enqueueError(_ error: LaunchctlError) {
        queue.append(.error(error))
    }

    // MARK: - 検証用

    /// 呼び出し履歴を古い順で返す。
    public func recordedCalls() -> [Call] {
        calls
    }

    // MARK: - LaunchctlClient

    public func enable(label: String) async throws -> LaunchctlResult {
        calls.append(.enable(label))
        return try dequeueResult(for: "enable")
    }

    public func disable(label: String) async throws -> LaunchctlResult {
        calls.append(.disable(label))
        return try dequeueResult(for: "disable")
    }

    public func kickstart(label: String, options: KickstartOptions) async throws -> LaunchctlResult {
        calls.append(.kickstart(label, options))
        return try dequeueResult(for: "kickstart")
    }

    public func bootstrap(plistPath: URL) async throws -> LaunchctlResult {
        calls.append(.bootstrap(plistPath))
        return try dequeueResult(for: "bootstrap")
    }

    public func bootout(label: String) async throws -> LaunchctlResult {
        calls.append(.bootout(label))
        return try dequeueResult(for: "bootout")
    }

    public func printDisabled() async throws -> PrintDisabledResult {
        calls.append(.printDisabled)
        guard !queue.isEmpty else {
            fatalError("MockLaunchctlClient: printDisabled called but queue is empty")
        }
        let response = queue.removeFirst()
        switch response {
        case .printDisabled(let labels, let raw):
            return PrintDisabledResult(disabledLabels: labels, raw: raw)
        case .error(let error):
            throw error
        case .result:
            fatalError("MockLaunchctlClient: printDisabled expected .printDisabled response, got .result")
        }
    }

    // MARK: - Private

    private func dequeueResult(for operation: String) throws -> LaunchctlResult {
        guard !queue.isEmpty else {
            fatalError("MockLaunchctlClient: \(operation) called but queue is empty")
        }
        let response = queue.removeFirst()
        switch response {
        case .result(let result):
            return result
        case .error(let error):
            throw error
        case .printDisabled:
            fatalError("MockLaunchctlClient: \(operation) expected .result response, got .printDisabled")
        }
    }
}
