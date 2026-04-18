import Darwin
import Foundation

/// `/usr/bin/security` を `Process` で呼び出す `KeychainClient` 実装。
///
/// - generic password アイテムのみを扱う（internet password 非対応）
/// - 失敗時は exit code で `KeychainError` に分類:
///   - 44 → `.notFound`
///   - 45 → `.duplicateItem`
///   - その他 → `.commandFailed`
/// - デフォルト 15 秒でタイムアウト（Keychain は高速、長引いたら異常）
/// - 実 security を叩くため、ユニットテストからは argv 生成 `buildXxxArguments` のみ検証する
public struct ProcessKeychainClient: KeychainClient {
    /// `/usr/bin/security` の絶対パス。
    public static let securityPath = "/usr/bin/security"

    private let executablePath: String
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.init(executablePath: Self.securityPath, timeout: timeout)
    }

    package init(executablePath: String, timeout: TimeInterval) {
        self.executablePath = executablePath
        self.timeout = timeout
    }

    // MARK: - KeychainClient

    public func add(service: String, account: String, password: String, overwrite: Bool) async throws {
        let args = Self.buildAddArguments(service: service, account: account, password: password, overwrite: overwrite)
        let result = try await run(arguments: args)
        if result.exitCode == 0 { return }
        if result.exitCode == 45 {
            throw KeychainError.duplicateItem
        }
        throw KeychainError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
    }

    public func find(service: String, account: String) async throws -> String {
        let args = Self.buildFindArguments(service: service, account: account)
        let result = try await run(arguments: args)
        if result.exitCode == 0 {
            // `-w` は password のみを stdout に出す。末尾の改行を落とす。
            return result.stdout.trimmingCharacters(in: .newlines)
        }
        if result.exitCode == 44 {
            throw KeychainError.notFound
        }
        throw KeychainError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
    }

    public func delete(service: String, account: String) async throws {
        let args = Self.buildDeleteArguments(service: service, account: account)
        let result = try await run(arguments: args)
        if result.exitCode == 0 { return }
        if result.exitCode == 44 {
            throw KeychainError.notFound
        }
        throw KeychainError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
    }

    // MARK: - argv 生成（ユニットテストから検証）

    package static func buildAddArguments(
        service: String, account: String, password: String, overwrite: Bool
    ) -> [String] {
        var args = ["add-generic-password", "-s", service, "-a", account, "-w", password]
        if overwrite {
            args.append("-U")
        }
        return args
    }

    package static func buildFindArguments(service: String, account: String) -> [String] {
        ["find-generic-password", "-s", service, "-a", account, "-w"]
    }

    package static func buildDeleteArguments(service: String, account: String) -> [String] {
        ["delete-generic-password", "-s", service, "-a", account]
    }

    // MARK: - Private: Process 実行

    private struct RawResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func run(arguments: [String]) async throws -> RawResult {
        let executable = executablePath
        let timeout = timeout

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RawResult, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let state = KeychainContinuationState()

            process.terminationHandler = { proc in
                let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let result = RawResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                )
                state.finish {
                    continuation.resume(returning: result)
                }
            }

            do {
                try process.run()
            } catch {
                state.finish {
                    continuation.resume(throwing: KeychainError.executableNotFound)
                }
                return
            }

            let timeoutNs = UInt64(max(timeout, 0) * 1_000_000_000)
            Task.detached {
                try? await Task.sleep(nanoseconds: timeoutNs)
                if process.isRunning {
                    process.terminate()
                    state.finish {
                        continuation.resume(throwing: KeychainError.timeout)
                    }
                }
            }
        }
    }
}

private final class KeychainContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func finish(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !resumed
        resumed = true
        lock.unlock()
        if shouldRun {
            body()
        }
    }
}
