import Foundation

/// 既存 plist Data の `StartInterval` / `StartCalendarInterval` だけを差し替えて返す。
///
/// - 単一 entry の StartCalendarInterval は dict、2 件以上は array of dicts で書き出す
///   （launchd.plist(5) が両形式を受ける前提、単一ケースは dict のほうが典型）
/// - `startInterval == nil` / `startCalendarInterval.isEmpty` の場合は対応キーを削除
/// - 他のキー（ProgramArguments, EnvironmentVariables 等）は保持
/// - 出力は XML 固定（人間可読・diff しやすさ優先）
public enum SchedulePlistComposer {
    public enum ComposeError: Error, Equatable, Sendable {
        case rootIsNotDictionary
        case invalidFormat
    }

    public static func compose(
        originalData: Data,
        startInterval: Int?,
        startCalendarInterval: [StartCalendarEntry]
    ) throws -> Data {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(
                from: originalData, options: .mutableContainersAndLeaves, format: nil
            )
        } catch {
            throw ComposeError.invalidFormat
        }
        guard var dict = plist as? [String: Any] else {
            throw ComposeError.rootIsNotDictionary
        }

        // StartInterval
        if let startInterval {
            dict["StartInterval"] = startInterval
        } else {
            dict.removeValue(forKey: "StartInterval")
        }

        // StartCalendarInterval
        switch startCalendarInterval.count {
        case 0:
            dict.removeValue(forKey: "StartCalendarInterval")
        case 1:
            dict["StartCalendarInterval"] = dictionary(from: startCalendarInterval[0])
        default:
            dict["StartCalendarInterval"] = startCalendarInterval.map(dictionary(from:))
        }

        return try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        )
    }

    /// `StartCalendarEntry` → plist dict 表現。nil フィールドはキーを載せない。
    private static func dictionary(from entry: StartCalendarEntry) -> [String: Int] {
        var out: [String: Int] = [:]
        if let m = entry.minute { out["Minute"] = m }
        if let h = entry.hour { out["Hour"] = h }
        if let d = entry.day { out["Day"] = d }
        if let w = entry.weekday { out["Weekday"] = w }
        if let mo = entry.month { out["Month"] = mo }
        return out
    }
}
