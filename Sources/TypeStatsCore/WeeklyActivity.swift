import Foundation

/// Seven local days by 24 local-hour buckets. The store merges repeated daylight-saving
/// hours into one bucket; this view preserves those counts rather than inventing timestamps.
public struct WeeklyActivity: Equatable, Sendable {
    public enum Cell: Equatable, Sendable {
        case count(Int)
        case future

        public var keys: Int {
            if case .count(let keys) = self { return keys }
            return 0
        }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let day: String
        public let label: String
        public let cells: [Cell]
        public var id: String { day }
    }

    public struct Peak: Equatable, Sendable {
        public let day: String
        public let hour: Int
    }

    public let rows: [Row]
    public let totalKeys: Int
    public let placedKeys: Int
    public let peakKeys: Int
    public let peaks: [Peak]

    public init(dayKeys: [String], hours: [String: [Int: HourCount]], totalKeys: Int,
                now: Date, calendar: Calendar) {
        let today = DayKey.string(for: now, calendar: calendar)
        let currentHour = calendar.component(.hour, from: now)
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        let label = DateFormatter()
        label.calendar = calendar
        label.timeZone = calendar.timeZone
        label.locale = Locale(identifier: "en_US")
        label.dateFormat = "EEE d"
        rows = dayKeys.map { day in
            Row(day: day, label: parser.date(from: day).map { label.string(from: $0) } ?? day,
                cells: (0..<24).map { hour in
                    day == today && hour > currentHour ? .future : .count(hours[day]?[hour]?.keys ?? 0)
                })
        }
        self.totalKeys = totalKeys
        placedKeys = rows.reduce(0) { $0 + $1.cells.reduce(0) { $0 + $1.keys } }
        let maximum = rows.flatMap(\.cells).map(\.keys).max() ?? 0
        peakKeys = maximum
        peaks = maximum == 0 ? [] : rows.flatMap { row in
            row.cells.enumerated().compactMap { hour, cell in
                cell.keys == maximum ? Peak(day: row.day, hour: hour) : nil
            }
        }
    }

    public var coverageText: String? {
        placedKeys < totalKeys ? "Based on \(ShareSummary.number(placedKeys)) of \(ShareSummary.number(totalKeys)) keys" : nil
    }

    public var peakText: String {
        guard let peak = peaks.first else { return "No hourly typing yet · local time" }
        let day = rows.first { $0.day == peak.day }?.label ?? peak.day
        let tie = peaks.count > 1 ? " · \(peaks.count) tied" : ""
        return "Peak \(day), \(Self.hourRange(peak.hour))\(tie) · local time"
    }

    /// Equal-width quartiles of the busiest observed cell, with zero outside the scale.
    /// Even one real key has a visible shade. No multiplication of integer counts.
    public static func shadeStep(keys: Int, peak: Int) -> Int {
        guard keys > 0, peak > 0 else { return 0 }
        return min(4, max(1, Int(ceil(min(1, Double(keys) / Double(peak)) * 4))))
    }

    public static func hourRange(_ hour: Int) -> String {
        let end = (hour + 1) % 24
        func number(_ h: Int) -> Int { h % 12 == 0 ? 12 : h % 12 }
        func suffix(_ h: Int) -> String { h < 12 ? "am" : "pm" }
        if suffix(hour) == suffix(end) { return "\(number(hour))-\(number(end)) \(suffix(hour))" }
        return "\(number(hour)) \(suffix(hour))-\(number(end)) \(suffix(end))"
    }
}
