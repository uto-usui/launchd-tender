import XCTest
@testable import TenderCore

final class NextRunCalculatorTests: XCTestCase {
    // MARK: - StartInterval only

    func testStartIntervalOnly() {
        let agent = makeAgent(interval: 3600)
        let after = jst("2026-04-18T12:00:00+09:00")
        let expected = jst("2026-04-18T13:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Single StartCalendarEntry

    func testSingleCalendarEntryFromNoonReturnsNextDay() {
        let agent = makeAgent(calendar: [StartCalendarEntry(minute: 0, hour: 8)])
        let after = jst("2026-04-18T12:00:00+09:00")
        let expected = jst("2026-04-19T08:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    func testSingleCalendarEntryFromBeforeMatchReturnsSameDay() {
        let agent = makeAgent(calendar: [StartCalendarEntry(minute: 0, hour: 8)])
        let after = jst("2026-04-18T07:30:00+09:00")
        let expected = jst("2026-04-18T08:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Multiple StartCalendarEntry (OR semantics)

    func testMultipleCalendarEntriesFromNoonPicksEarliest() {
        let agent = makeAgent(calendar: [
            StartCalendarEntry(minute: 0, hour: 8),
            StartCalendarEntry(minute: 0, hour: 17)
        ])
        let after = jst("2026-04-18T12:00:00+09:00")
        // 同日 17:00 と翌日 08:00 のうち早い方
        let expected = jst("2026-04-18T17:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    func testMultipleCalendarEntriesFromEveningPicksNextDayMorning() {
        let agent = makeAgent(calendar: [
            StartCalendarEntry(minute: 0, hour: 8),
            StartCalendarEntry(minute: 0, hour: 17)
        ])
        let after = jst("2026-04-18T18:00:00+09:00")
        // 翌日 08:00 と翌日 17:00 のうち早い方
        let expected = jst("2026-04-19T08:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - StartInterval + StartCalendarInterval combined (.min across candidates)

    func testIntervalAndCalendarCalendarWins() {
        // interval=300 (5min) + hour:9
        // after 08:58:00 → interval 候補 09:03:00 / calendar 候補 09:00:00
        // 期待: 09:00:00（calendar が早い）
        let agent = makeAgent(
            interval: 300,
            calendar: [StartCalendarEntry(hour: 9)]
        )
        let after = jst("2026-04-18T08:58:00+09:00")
        let expected = jst("2026-04-18T09:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    func testIntervalAndCalendarIntervalWins() {
        // interval=60 + hour:10
        // after 08:00:00 → interval 候補 08:01:00 / calendar 候補 10:00:00
        // 期待: 08:01:00（interval が早い）
        let agent = makeAgent(
            interval: 60,
            calendar: [StartCalendarEntry(hour: 10)]
        )
        let after = jst("2026-04-18T08:00:00+09:00")
        let expected = jst("2026-04-18T08:01:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Neither key specified

    func testReturnsNilWhenNoScheduleKeysSet() {
        let agent = makeAgent()
        let after = jst("2026-04-18T12:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertNil(actual)
    }

    // MARK: - Weekday

    func testWeekdayOnlyFromSaturdayJumpsToMonday() {
        // 2026-04-18 (Sat) 12:00 JST 起点で weekday=2 (Mon)
        // Calendar.nextDate(matchingPolicy: .nextTime) は直近の月曜 00:00 を返す
        let agent = makeAgent(calendar: [StartCalendarEntry(weekday: 2)])
        let after = jst("2026-04-18T12:00:00+09:00")
        let expected = jst("2026-04-20T00:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - End-of-month safety (2月に31日は存在しない)

    func testDayThirtyOneFromFebruaryHandledByCalendar() {
        // 2026-02-15 起点で day=31。
        // .nextTime では「存在しない日付の場合、次の最も近い時刻」に丸められるため
        // 2026-03-01 00:00:00 JST が返る（Calendar 任せ、このテストは挙動固定の確認）。
        let agent = makeAgent(calendar: [StartCalendarEntry(day: 31)])
        let after = jst("2026-02-15T12:00:00+09:00")
        let expected = jst("2026-03-01T00:00:00+09:00")

        let actual = NextRunCalculator.nextRun(for: agent, after: after, calendar: jstCalendar)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Helpers

    /// TimeZone を Asia/Tokyo に固定し、POSIX ロケールを用いた決定的な `Calendar`。
    private var jstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// ISO8601 文字列（タイムゾーンオフセット付き）から `Date` を生成する。
    private func jst(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso8601) else {
            fatalError("invalid ISO8601 literal in test: \(iso8601)")
        }
        return date
    }

    /// `LaunchAgent` のスケジュール関連フィールドだけを差し替えた雛形を作る。
    private func makeAgent(
        interval: Int? = nil,
        calendar: [StartCalendarEntry] = []
    ) -> LaunchAgent {
        LaunchAgent(
            label: "com.example.test",
            startInterval: interval,
            startCalendarInterval: calendar
        )
    }
}
