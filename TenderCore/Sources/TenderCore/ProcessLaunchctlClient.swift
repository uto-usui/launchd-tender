import Darwin
import Foundation

/// `/bin/launchctl` を `Process` で呼び出す `LaunchctlClient` 実装。
///
/// - domain は常に `gui/$(getuid())`（user agent 前提）
/// - stdout / stderr は `Pipe` で捕捉
/// - デフォルト 30 秒でタイムアウト。超えたら `process.terminate()` → `LaunchctlError.timeout`
/// - 実 launchctl を叩くため、ユニットテストからは呼び出さないこと。argv 生成のみ `buildArguments(...)` で検証可能。
public struct ProcessLaunchctlClient: LaunchctlClient {
    /// `/bin/launchctl` の絶対パス。
    public static let launchctlPath = "/bin/launchctl"

    private let executablePath: String
    private let timeout: TimeInterval
    private let uidProvider: @Sendable () -> UInt32

    /// デフォルト設定で生成する。`timeout` は 30 秒、uid は `getuid()`。
    public init(timeout: TimeInterval = 30) {
        self.init(
            executablePath: Self.launchctlPath,
            timeout: timeout,
            uidProvider: { UInt32(getuid()) }
        )
    }

    /// 依存注入向けイニシャライザ。テスト用途で uid を固定したり、実行ファイルパスを差し替える。
    package init(
        executablePath: String,
        timeout: TimeInterval,
        uidProvider: @escaping @Sendable () -> UInt32
    ) {
        self.executablePath = executablePath
        self.timeout = timeout
        self.uidProvider = uidProvider
    }

    // MARK: - LaunchctlClient

    public func enable(label: String) async throws -> LaunchctlResult {
        try await run(arguments: Self.buildArguments(for: .enable(label: label), uid: uidProvider()))
    }

    public func disable(label: String) async throws -> LaunchctlResult {
        try await run(arguments: Self.buildArguments(for: .disable(label: label), uid: uidProvider()))
    }

    public func kickstart(label: String, options: KickstartOptions) async throws -> LaunchctlResult {
        try await run(
            arguments: Self.buildArguments(for: .kickstart(label: label, options: options), uid: uidProvider())
        )
    }

    public func bootstrap(plistPath: URL) async throws -> LaunchctlResult {
        try await run(arguments: Self.buildArguments(for: .bootstrap(plistPath: plistPath), uid: uidProvider()))
    }

    public func bootout(label: String) async throws -> LaunchctlResult {
        try await run(arguments: Self.buildArguments(for: .bootout(label: label), uid: uidProvider()))
    }

    public func printDisabled() async throws -> PrintDisabledResult {
        let raw = try await run(arguments: Self.buildArguments(for: .printDisabled, uid: uidProvider()))
        let labels = Self.parsePrintDisabled(raw.stdout)
        return PrintDisabledResult(disabledLabels: labels, raw: raw)
    }

    // MARK: - argv 生成（ユニットテストから検証）

    /// サブコマンド種別。`buildArguments` の入力として使う。
    package enum Subcommand: Equatable {
        case enable(label: String)
        case disable(label: String)
        case kickstart(label: String, options: KickstartOptions)
        case bootstrap(plistPath: URL)
        case bootout(label: String)
        case printDisabled
    }

    /// サブコマンドと uid から `launchctl` に渡す argv を組み立てる。
    ///
    /// domain は常に `gui/<uid>`。label 付きサブコマンドは `gui/<uid>/<label>` を生成する。
    package static func buildArguments(for subcommand: Subcommand, uid: UInt32) -> [String] {
        let domain = "gui/\(uid)"
        switch subcommand {
        case .enable(let label):
            return ["enable", "\(domain)/\(label)"]
        case .disable(let label):
            return ["disable", "\(domain)/\(label)"]
        case .kickstart(let label, let options):
            var args = ["kickstart"]
            if options.kill {
                args.append("-k")
            }
            args.append("\(domain)/\(label)")
            return args
        case .bootstrap(let plistPath):
            return ["bootstrap", domain, plistPath.path]
        case .bootout(let label):
            return ["bootout", "\(domain)/\(label)"]
        case .printDisabled:
            return ["print-disabled", domain]
        }
    }

    // MARK: - Private: Process 実行

    private func run(arguments: [String]) async throws -> LaunchctlResult {
        let executable = executablePath
        let timeout = timeout

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LaunchctlResult, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // 継続を一度だけ resume するためのガード。タイムアウトと termination が競合する。
            let state = ContinuationState()

            process.terminationHandler = { proc in
                // stdout / stderr を読み出す。Process が終了済みなので available data で十分。
                let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let result = LaunchctlResult(
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
                    // Process が起動できない典型例: 実行ファイルが無い
                    continuation.resume(throwing: LaunchctlError.executableNotFound)
                }
                return
            }

            // タイムアウト監視タスク。超過したら terminate して LaunchctlError.timeout を返す。
            let timeoutNs = UInt64(max(timeout, 0) * 1_000_000_000)
            Task.detached {
                try? await Task.sleep(nanoseconds: timeoutNs)
                if process.isRunning {
                    process.terminate()
                    state.finish {
                        continuation.resume(throwing: LaunchctlError.timeout)
                    }
                }
            }
        }
    }

    // MARK: - Private: print-disabled パーサ

    /// `launchctl print-disabled gui/<uid>` 出力から `"<label>" => disabled` を抽出する。
    ///
    /// macOS の典型的な出力:
    /// ```
    /// disabled services = {
    /// 	"com.example.foo" => disabled
    /// 	"com.example.bar" => enabled
    /// }
    /// ```
    /// `=> enabled` は無視。前後空白・タブ・改行に寛容。失敗時は空 Set。
    static func parsePrintDisabled(_ text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: #""([^"]+)"\s*=>\s*disabled"#,
            options: []
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var labels: Set<String> = []
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            if let labelRange = Range(match.range(at: 1), in: text) {
                labels.insert(String(text[labelRange]))
            }
        }
        return labels
    }
}

// MARK: - 継続の排他制御

/// `withCheckedThrowingContinuation` を 1 回だけ resume するためのロック付きフラグ。
///
/// `terminationHandler` とタイムアウトタスクが同じ継続へ競合してアクセスするため、
/// 最初の `finish(_:)` だけがクロージャを実行する。
private final class ContinuationState: @unchecked Sendable {
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
