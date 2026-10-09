import Foundation

/// What the share card and share text show for one period (Today, 7 days or 30 days):
/// totals, the chart buckets and the top apps. Built from the same counts the popup
/// shows. Holds counts only, never key codes, text or click positions.
public struct ShareSummary: Equatable, Sendable {
    public struct AppRow: Identifiable, Equatable, Sendable {
        public let name: String
        public let keys: Int
        public var id: String { name }

        public init(name: String, keys: Int) {
            self.name = name
            self.keys = keys
        }
    }

    /// One bar of the chart: an hour of today or a day of the period.
    public struct Bucket: Identifiable, Equatable, Sendable {
        public let label: String
        public let keys: Int
        public let clicks: Int
        public let index: Int
        public var id: Int { index }

        public init(label: String, keys: Int, clicks: Int, index: Int) {
            self.label = label
            self.keys = keys
            self.clicks = clicks
            self.index = index
        }
    }

    public let title: String
    public let dateText: String
    public let keys: Int
    public let clicks: Int
    /// Estimated typing speed, nil when there is too little typing to estimate.
    public let wpm: Int?
    public let buckets: [Bucket]
    public let apps: [AppRow]
    /// True for 7 and 30 days (a bar per day), false for today (a bar per hour).
    public let isDaily: Bool
    /// Present only for the 7-day image, never synthesized from daily totals.
    public let activity: WeeklyActivity?

    public init(title: String, dateText: String, keys: Int, clicks: Int, wpm: Int?,
                buckets: [Bucket], apps: [AppRow], isDaily: Bool, activity: WeeklyActivity? = nil) {
        self.title = title
        self.dateText = dateText
        self.keys = keys
        self.clicks = clicks
        self.wpm = wpm
        self.buckets = buckets
        self.apps = apps
        self.isDaily = isDaily
        self.activity = activity
    }

    public var topThree: [AppRow] { Array(apps.prefix(3)) }

    /// The one-line summary to paste into a post:
    /// "Today: 7,120 keys · 665 clicks · 58 wpm. Top: Xcode 3,840 · Mail 1,215 · Chrome 960. via TypeStats".
    /// Without a speed estimate the wpm part is left out, and with no apps so is "Top:".
    public var text: String {
        var line = "\(title): \(Self.number(keys)) keys · \(Self.number(clicks)) clicks"
        if let wpm { line += " · \(wpm) wpm" }
        line += "."
        if !topThree.isEmpty {
            line += " Top: " + topThree.map { "\(Self.shortName($0.name)) \(Self.number($0.keys))" }.joined(separator: " · ") + "."
        }
        return line + " via TypeStats"
    }

    /// Thousands commas whatever the Mac's region, so a shared line reads the same everywhere.
    public static func number(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    static func shortName(_ name: String) -> String { name == "Google Chrome" ? "Chrome" : name }

    /// `TypeStats-Today-2026-10-05.png`, `TypeStats-7-days-...`, `TypeStats-30-days-...`.
    public static func fileName(period: StatsPeriod, date: Date, calendar: Calendar = .current) -> String {
        let part: String
        switch period {
        case .today: part = "Today"
        case .week: part = "7-days"
        case .month: part = "30-days"
        }
        return "TypeStats-\(part)-\(DayKey.string(for: date, calendar: calendar)).png"
    }

    /// The summary of `period` from the counter's own counts (today's hours, or the last
    /// 7 or 30 days), as the popup shows them.
    @MainActor public static func make(period: StatsPeriod, counter: KeyCounter) -> ShareSummary {
        let activity = period == .week ? try? counter.weeklyActivity() : nil
        let calendar = counter.calendar
        func format(_ pattern: String, _ date: Date) -> String {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = Locale(identifier: "en_US")
            f.dateFormat = pattern
            return f.string(from: date)
        }
        func rows(_ apps: [AppCount]) -> [AppRow] { apps.prefix(8).map { AppRow(name: $0.name, keys: $0.count) } }

        if period == .today {
            let hours = (0..<24).map { counter.todayHours[$0] ?? HourCount(hour: $0) }
            return ShareSummary(
                title: "Today", dateText: format("EEEE d MMMM", counter.currentDate),
                keys: counter.total, clicks: counter.totalClicks, wpm: counter.wpm.map { Int($0.rounded()) },
                buckets: hours.map { Bucket(label: "\($0.hour)", keys: $0.keys, clicks: $0.clicks, index: $0.hour) },
                apps: rows(counter.topApps(limit: 8)), isDaily: false)
        }
        let history = (try? counter.history(days: period.days)) ?? History(dayKeys: [], rows: [])
        let dayLabel = period == .week ? "EEE" : "d MMM"
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        let dates = history.days.map { parser.date(from: $0.day) }
        let buckets = history.days.enumerated().map { i, d in
            Bucket(label: dates[i].map { format(dayLabel, $0) } ?? d.day, keys: d.keys, clicks: d.clicks, index: i)
        }
        let range = [dates.first ?? nil, counter.currentDate].compactMap { $0 }.map { format("d MMM", $0) }.joined(separator: " – ")
        return ShareSummary(
            title: "Last \(period.days) days", dateText: range,
            keys: history.totalKeys, clicks: history.totalClicks, wpm: history.wpm.map { Int($0.rounded()) },
            buckets: buckets, apps: rows(history.apps), isDaily: true, activity: activity)
    }
}
