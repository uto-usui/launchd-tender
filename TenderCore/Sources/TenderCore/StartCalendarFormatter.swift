import Foundation

/// `StartCalendarEntry` / `[StartCalendarEntry]` を人間可読な文字列に整形する。
///
/// 例:
/// - `Hour: 8, Minute: 0` → `毎日 08:00`
/// - `Weekday: 2, Hour: 8` → `月曜 08:00`
/// - `Day: 1, Hour: 0, Minute: 0` → `毎月1日 00:00`
/// - `Minute: 30` → `毎時 30 分`
/// - 空 → `(任意時刻)`
///
/// launchd.plist(5) 準拠で `Weekday` は 1=Sunday。
public enum StartCalendarFormatter {
    /// 単一エントリをフォーマットする。
    public static func format(_ entry: StartCalendarEntry) -> String {
        var scope: [String] = []

        if let month = entry.month {
            scope.append("\(month)月")
        }
        if let day = entry.day {
            scope.append("\(day)日")
        }
        if let weekday = entry.weekday {
            scope.append(weekdayName(weekday))
        }

        let scopeString: String
        if scope.isEmpty {
            scopeString = "毎日"
        } else {
            scopeString = scope.joined(separator: " ")
        }

        switch (entry.hour, entry.minute) {
        case (let h?, let m?):
            return "\(scopeString) \(pad(h)):\(pad(m))"
        case (let h?, nil):
            return "\(scopeString) \(pad(h))時"
        case (nil, let m?):
            return scope.isEmpty ? "毎時 \(m) 分" : "\(scopeString) 毎時 \(m) 分"
        case (nil, nil):
            if scope.isEmpty {
                return "(任意時刻)"
            }
            return scopeString
        }
    }

    /// 配列。各エントリ1行ずつ。
    public static func format(_ entries: [StartCalendarEntry]) -> [String] {
        entries.map { format($0) }
    }

    /// サイドバー向けの1行要約。複数エントリは最初の1件 + "他 N 件"。
    public static func summary(_ entries: [StartCalendarEntry]) -> String? {
        guard let first = entries.first else { return nil }
        let firstString = format(first)
        if entries.count == 1 {
            return firstString
        }
        return "\(firstString) 他 \(entries.count - 1) 件"
    }

    // MARK: - Private

    private static let weekdayNames = [
        1: "日曜", 2: "月曜", 3: "火曜",
        4: "水曜", 5: "木曜", 6: "金曜", 7: "土曜"
    ]

    private static func weekdayName(_ weekday: Int) -> String {
        weekdayNames[weekday] ?? "Weekday:\(weekday)"
    }

    private static func pad(_ n: Int) -> String {
        String(format: "%02d", n)
    }
}
