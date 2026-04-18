import XCTest
@testable import TenderCore

final class StartCalendarFormatterTests: XCTestCase {
    func testHourAndMinute() {
        let entry = StartCalendarEntry(minute: 0, hour: 8)
        XCTAssertEqual(StartCalendarFormatter.format(entry), "毎日 08:00")
    }

    func testHourOnly() {
        let entry = StartCalendarEntry(hour: 17)
        XCTAssertEqual(StartCalendarFormatter.format(entry), "毎日 17時")
    }

    func testMinuteOnly() {
        let entry = StartCalendarEntry(minute: 30)
        XCTAssertEqual(StartCalendarFormatter.format(entry), "毎時 30 分")
    }

    func testWeekdayHourMinute() {
        // 月曜 = 2 (launchd.plist(5) / Calendar.current 共通: 1=Sunday)
        let entry = StartCalendarEntry(minute: 30, hour: 8, weekday: 2)
        XCTAssertEqual(StartCalendarFormatter.format(entry), "月曜 08:30")
    }

    func testAllWeekdaysMap() {
        let expected = [
            1: "日曜", 2: "月曜", 3: "火曜",
            4: "水曜", 5: "木曜", 6: "金曜", 7: "土曜"
        ]
        for (weekday, label) in expected {
            let entry = StartCalendarEntry(weekday: weekday)
            XCTAssertEqual(StartCalendarFormatter.format(entry), label)
        }
    }

    func testMonthDayHour() {
        let entry = StartCalendarEntry(hour: 9, day: 1, month: 1)
        XCTAssertEqual(StartCalendarFormatter.format(entry), "1月 1日 09時")
    }

    func testDayOnly() {
        let entry = StartCalendarEntry(day: 15)
        XCTAssertEqual(StartCalendarFormatter.format(entry), "15日")
    }

    func testEmptyEntry() {
        let entry = StartCalendarEntry()
        XCTAssertEqual(StartCalendarFormatter.format(entry), "(任意時刻)")
    }

    func testFormatArrayReturnsOnePerEntry() {
        let entries = [
            StartCalendarEntry(minute: 0, hour: 8),
            StartCalendarEntry(minute: 0, hour: 17)
        ]
        XCTAssertEqual(StartCalendarFormatter.format(entries), ["毎日 08:00", "毎日 17:00"])
    }

    func testSummarySingleEntry() {
        let entries = [StartCalendarEntry(minute: 0, hour: 8)]
        XCTAssertEqual(StartCalendarFormatter.summary(entries), "毎日 08:00")
    }

    func testSummaryMultipleEntriesShowsRemainder() {
        let entries = [
            StartCalendarEntry(minute: 0, hour: 8),
            StartCalendarEntry(minute: 0, hour: 12),
            StartCalendarEntry(minute: 0, hour: 17)
        ]
        XCTAssertEqual(StartCalendarFormatter.summary(entries), "毎日 08:00 他 2 件")
    }

    func testSummaryEmpty() {
        XCTAssertNil(StartCalendarFormatter.summary([]))
    }

    func testMinuteOnlyWithScope() {
        let entry = StartCalendarEntry(minute: 15, weekday: 2)
        XCTAssertEqual(StartCalendarFormatter.format(entry), "月曜 毎時 15 分")
    }
}
