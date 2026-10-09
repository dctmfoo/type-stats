import Foundation
import Observation

/// Counts key presses and mouse clicks per app and per hour for today, and typing time
/// for the speed estimate. Events are kept in memory and written to the store in
/// batches by `flush()`.
@MainActor
@Observable
public final class KeyCounter {
    /// Today's counts (stored plus not yet flushed), keyed by bundle id.
    public private(set) var todayCounts: [String: AppCount] = [:]
    /// Today's keys and clicks per local hour (stored plus not yet flushed).
    public private(set) var todayHours: [Int: HourCount] = [:]
    public private(set) var day: String
    /// Apps excluded from counting, by name. Their presses and clicks are dropped; their
    /// earlier counts stay.
    public private(set) var excludedApps: [AppIdentity] = []

    private struct Bucket: Hashable { let day: String; let hour: Int; let bundleID: String }
    private struct Tally { var keys = 0; var clicks = 0; var burstCount = 0; var activeSeconds = 0.0 }

    @ObservationIgnored private var pending: [Bucket: Tally] = [:]
    @ObservationIgnored private var pendingNames: [Bucket: String] = [:]
    @ObservationIgnored private var stretch = TypingStretch()
    @ObservationIgnored private var typingApp: String?
    /// Saved rows of past days, by the list of days asked for. The popup asks for its period's
    /// history on every redraw, which is every key press while it shows 7 or 30 days, and past
    /// days only change when a flush writes to one, so they are read from the store once.
    @ObservationIgnored private var pastRows: [[String]: [(day: String, app: AppCount)]] = [:]
    @ObservationIgnored private var pastHours: [String: [Int: HourCount]] = [:]
    /// Store reads made for past days (tests check the cache with it).
    @ObservationIgnored private(set) var pastRowFetches = 0
    @ObservationIgnored private let store: CountStore
    @ObservationIgnored public let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    public init(store: CountStore, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) throws {
        self.store = store
        self.calendar = calendar
        self.now = now
        day = DayKey.string(for: now(), calendar: calendar)
        excludedApps = try store.excludedApps()
        try reloadToday()
    }

    public func isExcluded(_ bundleID: String) -> Bool { excludedApps.contains { $0.bundleID == bundleID } }

    /// Stops counting `app` (saved at once, so it survives a restart). Counts already
    /// recorded for it are kept.
    public func exclude(_ app: AppIdentity) throws {
        endTypingStretch()
        try store.exclude(app)
        excludedApps = try store.excludedApps()
    }

    /// Counts `bundleID` again.
    public func include(bundleID: String) throws {
        try store.include(bundleID: bundleID)
        excludedApps = try store.excludedApps()
    }

    /// `rows` with `excluded` set for apps on the exclusion list.
    public func markExcluded(_ rows: [AppCount]) -> [AppCount] {
        rows.map { row in
            var row = row
            row.excluded = isExcluded(row.bundleID)
            return row
        }
    }

    /// The counter's current time (a fixed time under the `--at` test seam).
    public var currentDate: Date { now() }

    /// One key press in `app`. Adds exactly 1 to that app's key count for the current
    /// day and hour. `time` (seconds, monotonic) is the press time from the event, used
    /// only for typing speed; nil when the event has none. Returns false, counting nothing
    /// (not even typing time), when the app is excluded.
    @discardableResult
    public func record(_ app: AppIdentity, kind: TypingKeyKind = .other, at time: TimeInterval? = nil) -> Bool {
        rolloverIfNeeded()
        guard !isExcluded(app.bundleID) else { endTypingStretch(); return false }
        if typingApp != app.bundleID { endTypingStretch() }
        typingApp = app.bundleID
        let delta = stretch.press(kind, at: time)
        let tally = Tally(keys: 1, burstCount: delta.characters, activeSeconds: delta.seconds)
        add(app, tally)
        return true
    }

    /// Breaks continuity without changing already-qualified totals.
    public func endTypingStretch() {
        stretch = TypingStretch()
        typingApp = nil
    }

    /// One mouse click in `app`. Adds exactly 1 to that app's click count for the current day and hour.
    /// Returns false, counting nothing, when the app is excluded.
    @discardableResult
    public func recordClick(_ app: AppIdentity) -> Bool {
        guard !isExcluded(app.bundleID) else { return false }
        add(app, Tally(clicks: 1))
        return true
    }

    private func add(_ app: AppIdentity, _ tally: Tally) {
        rolloverIfNeeded()
        let hour = calendar.component(.hour, from: now())
        let bucket = Bucket(day: day, hour: hour, bundleID: app.bundleID)
        pending[bucket, default: Tally()].keys += tally.keys
        pending[bucket, default: Tally()].clicks += tally.clicks
        pending[bucket, default: Tally()].burstCount += tally.burstCount
        pending[bucket, default: Tally()].activeSeconds += tally.activeSeconds
        pendingNames[bucket] = app.name
        var row = todayCounts[app.bundleID] ?? AppCount(bundleID: app.bundleID, name: app.name, count: 0)
        row.add(Self.appCount(tally, app: app))
        row.name = app.name
        todayCounts[app.bundleID] = row
        todayHours[hour, default: HourCount(hour: hour)].keys += tally.keys
        todayHours[hour, default: HourCount(hour: hour)].clicks += tally.clicks
    }

    /// Writes pending presses and clicks to the store. They are kept if saving fails.
    public func flush() throws {
        rolloverIfNeeded()
        guard !pending.isEmpty else { return }
        for (bucket, tally) in pending {
            let app = AppIdentity(bundleID: bucket.bundleID, name: pendingNames[bucket] ?? bucket.bundleID)
            try store.add(day: bucket.day, hour: bucket.hour, app: app, keys: tally.keys, clicks: tally.clicks,
                          burstCount: tally.burstCount, activeSeconds: tally.activeSeconds)
        }
        try store.save()
        // Unsaved counts from a day that already ended are now saved rows of a past day.
        if pending.keys.contains(where: { $0.day != day }) {
            pastRows = [:]
            pastHours = [:]
        }
        pending.removeAll()
        pendingNames.removeAll()
    }

    /// Key presses plus clicks not yet saved.
    public var pendingCount: Int { pending.values.reduce(0) { $0 + $1.keys + $1.clicks } }

    /// Today's key presses across all apps.
    public var total: Int { todayCounts.values.reduce(0) { $0 + $1.count } }

    /// Today's clicks across all apps.
    public var totalClicks: Int { todayCounts.values.reduce(0) { $0 + $1.clicks } }

    /// Today's estimated typing speed across all apps, or nil when there is too little typing.
    public var wpm: Double? {
        TypingSpeed.wpm(burstCount: todayCounts.values.reduce(0) { $0 + $1.burstCount },
                        activeSeconds: todayCounts.values.reduce(0) { $0 + $1.activeSeconds })
    }

    /// Today's keys and clicks that have no hour: counted before hourly counts existed
    /// (task 03), so they appear in the day total but in no hour.
    public var keysWithoutHour: Int { max(0, total - todayHours.values.reduce(0) { $0 + $1.keys }) }
    public var clicksWithoutHour: Int { max(0, totalClicks - todayHours.values.reduce(0) { $0 + $1.clicks }) }

    public func topApps(limit: Int) -> [AppCount] {
        markExcluded(Array(Array(todayCounts.values).rankedByCount().prefix(limit)))
    }

    /// The `days` days ending today (today live, including unsaved counts).
    public func history(days: Int) throws -> History {
        let keys = History.dayKeys(endingAt: now(), count: days, calendar: calendar)
        let past = keys.filter { $0 != day }
        var rows: [(day: String, app: AppCount)]
        if let cached = pastRows[past] {
            rows = cached
        } else {
            rows = try store.counts(days: past)
            pastRowFetches += 1
            pastRows[past] = rows
        }
        // Unsaved counts from a day that already ended (rare: right after midnight).
        for (bucket, tally) in pending where bucket.day != day && past.contains(bucket.day) {
            let app = AppIdentity(bundleID: bucket.bundleID, name: pendingNames[bucket] ?? bucket.bundleID)
            rows.append((bucket.day, Self.appCount(tally, app: app)))
        }
        if keys.contains(day) { rows += todayCounts.values.map { (day, $0) } }
        return History(dayKeys: keys, rows: rows)
    }

    /// Past days come from the store plus pending counts for days that ended. Today's
    /// in-memory hours already include saved and pending counts, so use them only once.
    public func weeklyActivity() throws -> WeeklyActivity {
        rolloverIfNeeded()
        let date = now()
        let history = try history(days: 7)
        let keys = history.days.map(\.day)
        var hours: [String: [Int: HourCount]] = [:]
        for past in keys where past != day {
            if pastHours[past] == nil { pastHours[past] = try store.hours(day: past) }
            hours[past] = pastHours[past]
        }
        for (bucket, tally) in pending where bucket.day != day && keys.contains(bucket.day) {
            hours[bucket.day, default: [:]][bucket.hour, default: HourCount(hour: bucket.hour)].keys += tally.keys
        }
        hours[day] = todayHours
        return WeeklyActivity(dayKeys: keys, hours: hours, totalKeys: history.totalKeys, now: date, calendar: calendar)
    }

    /// Starts a fresh "today" when the local date changes.
    public func rolloverIfNeeded() {
        let current = DayKey.string(for: now(), calendar: calendar)
        guard current != day else { return }
        endTypingStretch()
        day = current
        pastRows = [:]
        pastHours = [:]
        todayCounts = [:]
        todayHours = [:]
        try? reloadToday()
    }

    private func reloadToday() throws {
        var rows: [String: AppCount] = [:]
        for row in try store.counts(day: day) { rows[row.bundleID] = row }
        var hours = try store.hours(day: day)
        // Presses and clicks for today that were not flushed yet still count.
        for (bucket, tally) in pending where bucket.day == day {
            let app = AppIdentity(bundleID: bucket.bundleID, name: pendingNames[bucket] ?? bucket.bundleID)
            rows[bucket.bundleID, default: AppCount(bundleID: app.bundleID, name: app.name, count: 0)]
                .add(Self.appCount(tally, app: app))
            hours[bucket.hour, default: HourCount(hour: bucket.hour)].keys += tally.keys
            hours[bucket.hour, default: HourCount(hour: bucket.hour)].clicks += tally.clicks
        }
        todayCounts = rows
        todayHours = hours
    }

    private static func appCount(_ tally: Tally, app: AppIdentity) -> AppCount {
        AppCount(bundleID: app.bundleID, name: app.name, count: tally.keys, clicks: tally.clicks,
                 burstCount: tally.burstCount, activeSeconds: tally.activeSeconds)
    }
}
