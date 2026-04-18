import Foundation

/// launchd の plist を `LaunchAgent` に変換する。
///
/// `PropertyListSerialization` に全面的に委譲するため、XML / binary の両形式を扱える。
/// 欠落キーはデフォルト値（空配列・nil・false）にフォールバックし、`Label` のみ必須。
public enum PlistParser {
    public enum Error: Swift.Error, Equatable {
        case invalidFormat
        case missingLabel
        case rootIsNotDictionary
    }

    /// Data をデコードして `LaunchAgent` を返す。
    ///
    /// - Parameters:
    ///   - data: plist の raw バイト列（XML または bplist）
    ///   - sourcePath: ファイル由来の場合の絶対パス。`LaunchAgent.sourcePath` に入る。
    public static func parse(_ data: Data, sourcePath: URL? = nil) throws -> LaunchAgent {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw Error.invalidFormat
        }

        guard let dict = plist as? [String: Any] else {
            throw Error.rootIsNotDictionary
        }

        guard let label = dict["Label"] as? String, !label.isEmpty else {
            throw Error.missingLabel
        }

        return LaunchAgent(
            label: label,
            programArguments: dict["ProgramArguments"] as? [String] ?? [],
            program: dict["Program"] as? String,
            environmentVariables: dict["EnvironmentVariables"] as? [String: String] ?? [:],
            workingDirectory: dict["WorkingDirectory"] as? String,
            startInterval: dict["StartInterval"] as? Int,
            startCalendarInterval: parseCalendarInterval(dict["StartCalendarInterval"]),
            watchPaths: dict["WatchPaths"] as? [String] ?? [],
            queueDirectories: dict["QueueDirectories"] as? [String] ?? [],
            standardOutPath: dict["StandardOutPath"] as? String,
            standardErrorPath: dict["StandardErrorPath"] as? String,
            runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepAlive: parseKeepAlive(dict["KeepAlive"]),
            launchOnlyOnce: dict["LaunchOnlyOnce"] as? Bool ?? false,
            sourcePath: sourcePath
        )
    }

    /// ファイルから読み込んでパース。
    public static func parse(contentsOf url: URL) throws -> LaunchAgent {
        let data = try Data(contentsOf: url)
        return try parse(data, sourcePath: url)
    }

    // MARK: - Private

    /// `StartCalendarInterval` は単一 dict / dict 配列のどちらも取りうる。両方を配列に正規化する。
    private static func parseCalendarInterval(_ value: Any?) -> [StartCalendarEntry] {
        if let single = value as? [String: Any] {
            return [dictToCalendarEntry(single)]
        }
        if let array = value as? [[String: Any]] {
            return array.map(dictToCalendarEntry)
        }
        return []
    }

    private static func dictToCalendarEntry(_ dict: [String: Any]) -> StartCalendarEntry {
        StartCalendarEntry(
            minute: dict["Minute"] as? Int,
            hour: dict["Hour"] as? Int,
            day: dict["Day"] as? Int,
            weekday: dict["Weekday"] as? Int,
            month: dict["Month"] as? Int
        )
    }

    private static func parseKeepAlive(_ value: Any?) -> KeepAlive {
        if let bool = value as? Bool {
            return bool ? .always : .disabled
        }
        if let dict = value as? [String: Any] {
            return .conditions(KeepAlive.Conditions(
                successfulExit: dict["SuccessfulExit"] as? Bool,
                networkState: dict["NetworkState"] as? Bool,
                pathState: dict["PathState"] as? [String: Bool] ?? [:],
                otherJobEnabled: dict["OtherJobEnabled"] as? [String: Bool] ?? [:],
                crashed: dict["Crashed"] as? Bool,
                afterInitialDemand: dict["AfterInitialDemand"] as? Bool
            ))
        }
        return .disabled
    }
}
