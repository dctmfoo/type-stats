import Foundation

/// Local calendar day as "yyyy-MM-dd". Counts are bucketed by this key.
public enum DayKey {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
