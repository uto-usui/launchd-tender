import Foundation

/// `LaunchAgent` の次回実行時刻を推定する純粋関数群。
///
/// 実際の launchd はスリープ挙動や最終実行時刻の影響を受けるため、
/// ここで返される `Date` は UI 上で「推定」ラベル付きで提示される前提。
/// この型は現在時刻を起点に、スケジュールキー（`StartInterval` / `StartCalendarInterval`）
/// から算出した最良推定のみを返す責務を持つ。
public enum NextRunCalculator {
    /// 推定の次回実行時刻を返す。
    ///
    /// アルゴリズム:
    /// - `startInterval` のみ指定: `after` に `interval` 秒を足した時刻を候補とする（最悪ケース想定）
    /// - `startCalendarInterval` のみ指定: 各エントリの次マッチ時刻のうち最早を候補とする
    /// - 両方指定: 上記2種の候補を合わせて最早を返す
    /// - どちらも未指定: `nil`
    ///
    /// - Parameters:
    ///   - agent: 対象の `LaunchAgent`
    ///   - after: 起点となる時刻（デフォルト: `Date()`）
    ///   - calendar: 時刻計算に使う `Calendar`（デフォルト: `.current`。テストでは
    ///     TimeZone を固定した `Calendar` を明示注入すること）
    /// - Returns: 推定次回実行時刻。候補が一つもなければ `nil`。
    public static func nextRun(
        for agent: LaunchAgent,
        after: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        var candidates: [Date] = []

        if let interval = agent.startInterval {
            candidates.append(after.addingTimeInterval(TimeInterval(interval)))
        }

        for entry in agent.startCalendarInterval {
            let components = dateComponents(from: entry)
            if let next = calendar.nextDate(
                after: after,
                matching: components,
                matchingPolicy: .nextTime
            ) {
                candidates.append(next)
            }
        }

        return candidates.min()
    }

    // MARK: - Private

    /// `StartCalendarEntry` を `DateComponents` にマッピングする。
    ///
    /// `nil` のフィールドは設定せず、`Calendar.nextDate(after:matching:matchingPolicy:)`
    /// 内部でワイルドカード扱いにさせる。`weekday` は launchd.plist(5) と
    /// `Calendar` の両方で 1 = Sunday の規約なので変換は不要。
    private static func dateComponents(from entry: StartCalendarEntry) -> DateComponents {
        var components = DateComponents()
        if let minute = entry.minute { components.minute = minute }
        if let hour = entry.hour { components.hour = hour }
        if let day = entry.day { components.day = day }
        if let weekday = entry.weekday { components.weekday = weekday }
        if let month = entry.month { components.month = month }
        return components
    }
}
