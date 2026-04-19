import Darwin
import Foundation

/// `/usr/bin/log show --predicate 'process == "<name>"' --style ndjson` を呼び、
/// 返ってきた ndjson を `LogLine` にパースする。
///
/// - ndjson の各行は独立 JSON。`eventType == "logEvent"` のみ採用（activityCreate 等は捨てる）
/// - timestamp は `yyyy-MM-dd HH:mm:ss.SSSSSSZ` 形式（例: "2026-04-19 09:39:17.629838+0900"）
/// - messageType: "Default" / "Info" / "Debug" / "Error" / "Fault"。小文字化して LogLineLevel に写す
/// - maxLines を超えたら末尾側（新しい側）を返す
public struct ProcessUnifiedLogClient: UnifiedLogClient {
    public static let logPath = "/usr/bin/log"

    private let executablePath: String
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 10) {
        self.init(executablePath: Self.logPath, timeout: timeout)
    }

    package init(executablePath: String, timeout: TimeInterval) {
        self.executablePath = executablePath
        self.timeout = timeout
    }

    // MARK: - UnifiedLogClient

    public func fetch(process: String, lastSeconds: Int, maxLines: Int) async throws -> [LogLine] {
        let args = Self.buildArguments(process: process, lastSeconds: lastSeconds)
        let result = try await run(arguments: args)
        if result.exitCode != 0 {
            throw UnifiedLogError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        let all = Self.parseNDJSON(result.stdout)
        if all.count <= maxLines {
            return all
        }
        return Array(all.suffix(maxLines))
    }

    // MARK: - argv 生成

    package static func buildArguments(process: String, lastSeconds: Int) -> [String] {
        let predicate = "process == \"\(process)\""
        return ["show", "--predicate", predicate, "--style", "ndjson", "--last", "\(lastSeconds)s"]
    }

    // MARK: - NDJSON パーサ

    package static func parseNDJSON(_ raw: String) -> [LogLine] {
        var lines: [LogLine] = []
        raw.enumerateLines { line, _ in
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return
            }
            // activity / boundary 系は eventMessage が空、もしくは eventType が logEvent でない
            guard (obj["eventType"] as? String) == "logEvent" else { return }
            guard let message = obj["eventMessage"] as? String, !message.isEmpty else { return }

            let timestamp = (obj["timestamp"] as? String).flatMap(parseTimestamp) ?? Date()
            let level = levelFromMessageType(obj["messageType"] as? String)
            let processPath = obj["processImagePath"] as? String
            let category = (obj["category"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let subsystem = (obj["subsystem"] as? String).flatMap { $0.isEmpty ? nil : $0 }

            lines.append(LogLine(
                timestamp: timestamp,
                processImagePath: processPath,
                message: message,
                category: category,
                subsystem: subsystem,
                level: level
            ))
        }
        return lines
    }

    package static func levelFromMessageType(_ raw: String?) -> LogLineLevel {
        switch raw?.lowercased() {
        case "default": return .default
        case "info": return .info
        case "debug": return .debug
        case "error": return .error
        case "fault": return .fault
        default: return .unknown
        }
    }

    /// `log show` ndjson timestamp: `yyyy-MM-dd HH:mm:ss.SSSSSSZ` を Date に変換。
    /// microseconds は millisecond 精度に落とす（Date 精度の現実的な限界）。
    package static func parseTimestamp(_ s: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        if let date = formatter.date(from: s) { return date }
        // 6 桁が合わない場合のフォールバック（3 桁 ms 版）
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        return formatter.date(from: s)
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

            let state = LogContinuationState()

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
                    continuation.resume(throwing: UnifiedLogError.executableNotFound)
                }
                return
            }

            let timeoutNs = UInt64(max(timeout, 0) * 1_000_000_000)
            Task.detached {
                try? await Task.sleep(nanoseconds: timeoutNs)
                if process.isRunning {
                    process.terminate()
                    state.finish {
                        continuation.resume(throwing: UnifiedLogError.timeout)
                    }
                }
            }
        }
    }
}

private final class LogContinuationState: @unchecked Sendable {
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
