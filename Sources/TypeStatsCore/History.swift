import Foundation

/// Key presses and clicks across all apps in one local hour (0...23) of a day.
public struct HourCount: Identifiable, Hashable, Sendable {
    public let hour: Int
    public var keys: Int
    public var clicks: Int

    public var id: Int { hour }

    public init(hour: Int, keys: Int = 0, clicks: Int = 0) {
        self.hour = hour
        self.keys = keys
        self.clicks = clicks
    }
}

/// Key presses and clicks across all apps on one day.
public struct DayTotal: Identifiable, Hashable, Sendable {
    public let day: String
    public var keys: Int
    public var clicks: Int

    public var id: String { day }

    public init(day: String, keys: Int = 0, clicks: Int = 0) {
        self.day = day
        self.keys = keys
        self.clicks = clicks
    }
}

/// Counts for a period of days ending today: one total per day (oldest first, days
/// with nothing counted included as 0) and per-app totals for the whole period.
public struct History: Sendable, Equatable {
    public let days: [DayTotal]
    public let apps: [AppCount]

    public init(dayKeys: [String], rows: [(day: String, app: AppCount)]) {
        var byDay = Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, DayTotal(day: $0)) })
        var byApp: [String: AppCount] = [:]
        for (day, row) in rows where byDay[day] != nil {
            byDay[day]!.keys += row.count
            byDay[day]!.clicks += row.clicks
            if byApp[row.bundleID] == nil {
                byApp[row.bundleID] = AppCount(bundleID: row.bundleID, name: row.name, count: 0)
            }
            byApp[row.bundleID]!.add(row)
        }
        days = dayKeys.map { byDay[$0]! }
        apps = Array(byApp.values).rankedByCount()
    }

    public var totalKeys: Int { days.reduce(0) { $0 + $1.keys } }
    public var totalClicks: Int { days.reduce(0) { $0 + $1.clicks } }
    public var wpm: Double? {
        TypingSpeed.wpm(burstCount: apps.reduce(0) { $0 + $1.burstCount },
                        activeSeconds: apps.reduce(0) { $0 + $1.activeSeconds })
    }

    /// The `count` local days ending with the day of `date`, oldest first.
    public static func dayKeys(endingAt date: Date, count: Int, calendar: Calendar = .current) -> [String] {
        let start = calendar.startOfDay(for: date)
        return (0..<max(count, 1)).reversed().map { back in
            DayKey.string(for: calendar.date(byAdding: .day, value: -back, to: start) ?? start, calendar: calendar)
        }
    }

    public static func == (a: History, b: History) -> Bool { a.days == b.days && a.apps == b.apps }
}
