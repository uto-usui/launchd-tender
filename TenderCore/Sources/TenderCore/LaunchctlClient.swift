import Foundation

/// `launchctl` 操作の抽象。Process 実装とテスト用 Mock の両方を差し替え可能にする。
///
/// 全メソッドは async throws で、失敗時は `LaunchctlError` を送る。
/// 実装は domain ターゲットを `gui/$(id -u)` に統一する（user agent のみ扱う）。
public protocol LaunchctlClient: Sendable {
    /// `launchctl enable gui/<uid>/<label>`
    func enable(label: String) async throws -> LaunchctlResult

    /// `launchctl disable gui/<uid>/<label>`
    func disable(label: String) async throws -> LaunchctlResult

    /// `launchctl kickstart [-k] gui/<uid>/<label>`
    ///
    /// - Parameter options: `-k` などのフラグ。`.default` で素のキックスタート。
    func kickstart(label: String, options: KickstartOptions) async throws -> LaunchctlResult

    /// `launchctl bootstrap gui/<uid> <plistPath>`
    func bootstrap(plistPath: URL) async throws -> LaunchctlResult

    /// `launchctl bootout gui/<uid>/<label>`
    func bootout(label: String) async throws -> LaunchctlResult

    /// `launchctl print-disabled gui/<uid>` の出力をパースして disabled ラベル集合を返す。
    func printDisabled() async throws -> PrintDisabledResult
}

/// `launchctl` の実行結果。exit code と標準出力・標準エラーをそのまま保持する。
public struct LaunchctlResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    /// exit code が 0 のときのみ true。
    public var isSuccess: Bool { exitCode == 0 }
}

/// `launchctl kickstart` のフラグ。
public struct KickstartOptions: Sendable, Equatable {
    /// `-k` フラグ。true のとき既存プロセスを kill して再起動する。
    public var kill: Bool

    public init(kill: Bool) {
        self.kill = kill
    }

    /// `-k` なしのデフォルト。
    public static let `default` = KickstartOptions(kill: false)
}

/// `launchctl print-disabled` 出力のパース結果。
public struct PrintDisabledResult: Sendable, Equatable {
    /// `=> disabled` と記録されていたラベル集合。
    public let disabledLabels: Set<String>

    /// パース前の生コマンド結果。stderr やデバッグ用途に参照する。
    public let raw: LaunchctlResult

    public init(disabledLabels: Set<String>, raw: LaunchctlResult) {
        self.disabledLabels = disabledLabels
        self.raw = raw
    }
}

/// `LaunchctlClient` の失敗理由。
public enum LaunchctlError: Error, Equatable {
    /// タイムアウト。`ProcessLaunchctlClient(timeout:)` で指定した秒数を超えた。
    case timeout

    /// `launchctl` が非 0 exit した。結果を同梱する。
    case commandFailed(LaunchctlResult)

    /// `/bin/launchctl` が見つからない、または起動できない。
    case executableNotFound
}
