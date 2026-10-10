import XCTest
@testable import TypeStatsCore

@MainActor
final class HourlyAppActivityTests: XCTestCase {
    private let a = AppIdentity(bundleID: "com.anthropic.claudefordesktop", name: "Claude")
    private let b = AppIdentity(bundleID: "com.openai.codex", name: "Codex")
    private let c = AppIdentity(bundleID: "com.microsoft.teams2", name: "Teams")

    func testRepeatedDSTHourMergesEachAppOnce() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let parser = ISO8601DateFormatter()
        var date = try XCTUnwrap(parser.date(from: "2026-11-01T08:30:00Z"))
        let store = try CountStore(directory: makeTestDirectory())
        let counter = try KeyCounter(store: store, calendar: calendar, now: { date })
        counter.record(a)
        date = try XCTUnwrap(parser.date(from: "2026-11-01T09:30:00Z"))
        counter.record(a)
        for _ in 0..<3 { counter.record(b) }
        let activity = try counter.weeklyActivity()
        XCTAssertEqual(activity.rows[6].cells[1], .count(5))
        XCTAssertEqual(activity.rows[6].detail(at: 1).leaders.map(\.app), [b])
        XCTAssertEqual(activity.rows[6].detail(at: 1).leadingShare, 0.6)
        XCTAssertEqual(activity.totalKeys, 5)
        XCTAssertEqual(activity.placedKeys, 5)
        try counter.flush()
        XCTAssertEqual(try counter.weeklyActivity(), activity)
        XCTAssertEqual(try KeyCounter(store: store, calendar: calendar, now: { date }).weeklyActivity(), activity)
    }

    func testLeadersBelongToEachHourNotWeeklyRankAndIgnoreClicks() throws {
        let clock = TestClock("2026-10-05 14:30")
        let store = try CountStore(directory: makeTestDirectory())
        try store.add(day: "2026-10-05", hour: 9, app: a, keys: 600)
        try store.add(day: "2026-10-05", hour: 9, app: b, keys: 200)
        try store.add(day: "2026-10-05", hour: 13, app: a, keys: 257)
        try store.add(day: "2026-10-05", hour: 13, app: b, keys: 252)
        try store.add(day: "2026-10-05", hour: 13, app: c, keys: 16, clicks: 5000)
        try store.add(day: "2026-10-05", hour: 14, app: b, keys: 5)
        try store.save()
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        let before = try counter.weeklyActivity()
        XCTAssertEqual(before.rows[6].detail(at: 14).leaders.map(\.app), [b])
        XCTAssertEqual(before.rows[6].detail(at: 13).leadingShare!, 257.0 / 525, accuracy: 0.00001)
        XCTAssertTrue(before.rows[6].detail(at: 13).text.contains("Leading app: Claude · 49.0%"))
        XCTAssertFalse(before.rows[6].detail(at: 13).text.contains("majority"))
        clock.set("2026-10-05 13:30")
        for _ in 0..<6 { counter.record(b) }
        let after = try counter.weeklyActivity()
        XCTAssertEqual(after.rows[6].detail(at: 13).leaders.map(\.app), [b])
        XCTAssertEqual(after.rows[6].cells[13], .count(531))
        XCTAssertEqual(after.rows[6].detail(at: 9).leaders.map(\.app), [a])
        XCTAssertEqual(after.totalKeys, 1336)
        try counter.flush()
        XCTAssertEqual(try counter.weeklyActivity(), after)
        XCTAssertEqual(try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date }).weeklyActivity(), after)
        let share = ShareSummary.make(period: .week, counter: counter)
        XCTAssertEqual(share.activity, after)
        XCTAssertEqual(share.apps.first?.bundleID, a.bundleID)
    }

    func testPendingAcrossMidnightHourChangesAndCachesMergeExactlyOnce() throws {
        let clock = TestClock("2026-10-04 23:59")
        let store = try CountStore(directory: makeTestDirectory())
        try store.add(day: "2026-10-04", hour: 23, app: a, keys: 2)
        try store.save()
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        counter.record(b)
        _ = try counter.weeklyActivity()
        clock.set("2026-10-05 00:01")
        counter.record(a)
        clock.set("2026-10-05 01:01")
        counter.record(b)
        counter.record(b)
        let live = try counter.weeklyActivity()
        XCTAssertEqual(live.totalKeys, 6)
        XCTAssertEqual(live.placedKeys, 6)
        XCTAssertEqual(live.rows[5].appHours[23].reduce(0) { $0 + $1.keys }, 3)
        XCTAssertEqual(live.rows[5].detail(at: 23).leaders.map(\.app), [a])
        XCTAssertEqual(live.rows[6].detail(at: 0).leaders.map(\.app), [a])
        XCTAssertEqual(live.rows[6].detail(at: 1).leaders.map(\.app), [b])
        for _ in 0..<3 { XCTAssertEqual(try counter.weeklyActivity(), live) }
        try counter.flush()
        XCTAssertEqual(try counter.weeklyActivity(), live)
        XCTAssertEqual(try store.appHours(day: "2026-10-04")[23]?[b.bundleID]?.keys, 1)
        let restarted = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(try restarted.weeklyActivity(), live)
    }

    func testTiesZeroFuturePluralityAndUnavailableBreakdownLabels() throws {
        let clock = TestClock("2026-10-05 13:30")
        let day = "2026-10-05"
        let hours = [day: [9: HourCount(hour: 9, keys: 420), 10: HourCount(hour: 10, keys: 735),
                          11: HourCount(hour: 11, keys: 100), 12: HourCount(hour: 12, keys: 100),
                          14: HourCount(hour: 14, keys: 999)]]
        let appHours = [day: [9: [a.bundleID: HourlyAppCount(app: a, keys: 210), b.bundleID: HourlyAppCount(app: b, keys: 210)],
                            10: [a.bundleID: HourlyAppCount(app: a, keys: 245), b.bundleID: HourlyAppCount(app: b, keys: 226),
                                 c.bundleID: HourlyAppCount(app: c, keys: 264)],
                            11: [a.bundleID: HourlyAppCount(app: a, keys: 60)],
                            14: [a.bundleID: HourlyAppCount(app: a, keys: 999)]]]
        let activity = WeeklyActivity(dayKeys: [day], hours: hours, totalKeys: 2354, now: clock.date,
                                      calendar: clock.calendar, appHours: appHours)
        let row = activity.rows[0]
        XCTAssertEqual(row.detail(at: 9).leaders.map(\.app), [a, b])
        XCTAssertEqual(row.detail(at: 9).leadingShare, 0.5)
        XCTAssertTrue(row.detail(at: 9).text.contains("Tied leaders: Claude, Codex · 50.0% each"))
        XCTAssertEqual(row.detail(at: 10).leaders.map(\.app), [c])
        XCTAssertEqual(row.detail(at: 10).leadingShare!, 264.0 / 735, accuracy: 0.00001)
        XCTAssertTrue(row.detail(at: 10).text.contains("35.9%"))
        for h in [11, 12] {
            XCTAssertTrue(row.detail(at: h).leaders.isEmpty)
            XCTAssertNil(row.detail(at: h).leadingShare)
            XCTAssertTrue(row.detail(at: h).text.contains("App breakdown unavailable"))
        }
        XCTAssertTrue(row.detail(at: 0).text.contains("No leading app"))
        XCTAssertNil(row.detail(at: 0).leadingShare)
        XCTAssertEqual(row.cells[14], .future)
        XCTAssertTrue(row.appHours[14].isEmpty)
        XCTAssertEqual(row.detail(at: 14).text, "Mon 5, 2-3 pm\nNot yet counted")
        XCTAssertEqual(activity.coverageText, "Based on 1,355 of 2,354 keys")
    }

    func testOrphanHourIdentityFallsBackToBundleWithoutInventingNames() throws {
        let clock = TestClock("2026-10-05 13:30")
        let store = try CountStore(directory: makeTestDirectory())
        store.container.mainContext.insert(AppHourCount(day: "2026-10-05", hour: 10, bundleID: "host.unknown", count: 9, clicks: 2))
        try store.save()
        let row = try XCTUnwrap(store.appHours(day: "2026-10-05")[10]?["host.unknown"])
        XCTAssertEqual(row.app, AppIdentity(bundleID: "host.unknown", name: "host.unknown"))
        XCTAssertEqual(row.keys, 9)
        XCTAssertEqual(row.clicks, 2)
        XCTAssertEqual(AppPalette.family(bundleID: row.app.bundleID), .other)
    }

    func testLegacyAndClicksOnlyNeverInventAKeyLeader() throws {
        let clock = TestClock("2026-10-05 10:30")
        let store = try CountStore(directory: makeTestDirectory())
        try store.add(day: "2026-10-05", app: a, keys: 90)
        try store.add(day: "2026-10-05", hour: 10, app: b, keys: 0, clicks: 100)
        try store.save()
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        let activity = try counter.weeklyActivity()
        XCTAssertEqual(activity.totalKeys, 90)
        XCTAssertEqual(activity.placedKeys, 0)
        XCTAssertEqual(activity.coverageText, "Based on 0 of 90 keys")
        XCTAssertTrue(activity.leadingApps.isEmpty)
        XCTAssertTrue(activity.rows[6].detail(at: 10).leaders.isEmpty)
        XCTAssertEqual(activity.rows[6].appHours[10].first?.clicks, 100)
    }
}
