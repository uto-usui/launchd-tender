import Foundation

/// `launchd.plist(5)` が定めるキーのうち Tender で扱うものを型として表現する。
///
/// plist が唯一の truth であり、この型はそれを写し取る純粋なスナップショット。
/// SwiftData の永続化対象ではない（永続化されるのは `Intent`・`BackupEntry`・`ExecutionRecord`）。
public struct LaunchAgent: Sendable, Hashable, Identifiable {
    public var id: String { label }

    /// 必須。`com.uto-usui.tender` のような逆 DNS 記法の一意識別子。
    public let label: String

    /// 実行する argv。先頭が実行ファイル。
    public let programArguments: [String]

    /// 単一コマンド指定（`ProgramArguments` より優先度低だが互換のため保持）。
    public let program: String?

    public let environmentVariables: [String: String]

    public let workingDirectory: String?

    /// 秒単位の周期起動。`StartCalendarInterval` と同時指定は独立評価される。
    public let startInterval: Int?

    /// cron 風の時刻指定（複数 dict の OR）。
    public let startCalendarInterval: [StartCalendarEntry]

    /// 監視対象ファイル・ディレクトリ。いずれかに変更が入ると起動。
    public let watchPaths: [String]

    /// キューとして振る舞うディレクトリ。
    public let queueDirectories: [String]

    public let standardOutPath: String?
    public let standardErrorPath: String?

    public let runAtLoad: Bool
    public let keepAlive: KeepAlive
    public let launchOnlyOnce: Bool

    /// plist ファイルの絶対パス（スキャナが埋める。パース単体では nil）。
    public let sourcePath: URL?

    /// Tender が Keychain ラッパ移行済みとしてマークしたか（`TenderManaged` meta key）。
    public let tenderManaged: Bool

    /// Keychain へ移された env 名一覧（`TenderWrappedEnvs` meta key）。
    public let tenderWrappedEnvs: [String]

    /// 移行前の ProgramArguments（`TenderOriginalProgramArguments` meta key、復元用）。
    public let tenderOriginalProgramArguments: [String]

    public init(
        label: String,
        programArguments: [String] = [],
        program: String? = nil,
        environmentVariables: [String: String] = [:],
        workingDirectory: String? = nil,
        startInterval: Int? = nil,
        startCalendarInterval: [StartCalendarEntry] = [],
        watchPaths: [String] = [],
        queueDirectories: [String] = [],
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        runAtLoad: Bool = false,
        keepAlive: KeepAlive = .disabled,
        launchOnlyOnce: Bool = false,
        sourcePath: URL? = nil,
        tenderManaged: Bool = false,
        tenderWrappedEnvs: [String] = [],
        tenderOriginalProgramArguments: [String] = []
    ) {
        self.label = label
        self.programArguments = programArguments
        self.program = program
        self.environmentVariables = environmentVariables
        self.workingDirectory = workingDirectory
        self.startInterval = startInterval
        self.startCalendarInterval = startCalendarInterval
        self.watchPaths = watchPaths
        self.queueDirectories = queueDirectories
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.launchOnlyOnce = launchOnlyOnce
        self.sourcePath = sourcePath
        self.tenderManaged = tenderManaged
        self.tenderWrappedEnvs = tenderWrappedEnvs
        self.tenderOriginalProgramArguments = tenderOriginalProgramArguments
    }
}

/// `StartCalendarInterval` の1エントリ。いずれも未指定 (nil) の場合「任意値」に一致する。
public struct StartCalendarEntry: Sendable, Hashable, Codable {
    public let minute: Int?
    public let hour: Int?
    public let day: Int?
    public let weekday: Int?
    public let month: Int?

    public init(
        minute: Int? = nil,
        hour: Int? = nil,
        day: Int? = nil,
        weekday: Int? = nil,
        month: Int? = nil
    ) {
        self.minute = minute
        self.hour = hour
        self.day = day
        self.weekday = weekday
        self.month = month
    }
}

/// `KeepAlive` は bool か dict。表現力を担保するため列挙型で保持する。
public enum KeepAlive: Sendable, Hashable {
    case disabled
    case always
    case conditions(Conditions)

    public struct Conditions: Sendable, Hashable {
        public let successfulExit: Bool?
        public let networkState: Bool?
        public let pathState: [String: Bool]
        public let otherJobEnabled: [String: Bool]
        public let crashed: Bool?
        public let afterInitialDemand: Bool?

        public init(
            successfulExit: Bool? = nil,
            networkState: Bool? = nil,
            pathState: [String: Bool] = [:],
            otherJobEnabled: [String: Bool] = [:],
            crashed: Bool? = nil,
            afterInitialDemand: Bool? = nil
        ) {
            self.successfulExit = successfulExit
            self.networkState = networkState
            self.pathState = pathState
            self.otherJobEnabled = otherJobEnabled
            self.crashed = crashed
            self.afterInitialDemand = afterInitialDemand
        }
    }
}
