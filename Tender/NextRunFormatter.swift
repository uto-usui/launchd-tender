import Foundation

/// 次回実行時刻を UI 向けに短く整形する。
///
/// 例:
/// - 今日: `14:30`
/// - 明日: `明日 08:00`
/// - それ以外: `4/21 08:00`
/// - 1年以上先: `2027/4/18`
///
/// いずれも UI 上で「(推定)」ラベルを伴って表示する（呼び出し側で付与）。
struct NextRunFormatter {
    static let shared = NextRunFormatter()

    private let timeFormatter: DateFormatter
    private let monthDayFormatter: DateFormatter
    private let yearFormatter: DateFormatter
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar

        self.timeFormatter = DateFormatter()
        self.timeFormatter.calendar = calendar
        self.timeFormatter.timeZone = calendar.timeZone
        self.timeFormatter.locale = Locale.current
        self.timeFormatter.dateFormat = "HH:mm"

        self.monthDayFormatter = DateFormatter()
        self.monthDayFormatter.calendar = calendar
        self.monthDayFormatter.timeZone = calendar.timeZone
        self.monthDayFormatter.locale = Locale.current
        self.monthDayFormatter.dateFormat = "M/d HH:mm"

        self.yearFormatter = DateFormatter()
        self.yearFormatter.calendar = calendar
        self.yearFormatter.timeZone = calendar.timeZone
        self.yearFormatter.locale = Locale.current
        self.yearFormatter.dateFormat = "yyyy/M/d"
    }

    func format(_ date: Date, now: Date = Date()) -> String {
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInTomorrow(date) {
            return "明日 " + timeFormatter.string(from: date)
        }
        let daysFromNow = calendar.dateComponents([.day], from: now, to: date).day ?? 0
        if daysFromNow < 365 {
            return monthDayFormatter.string(from: date)
        }
        return yearFormatter.string(from: date)
    }
}
