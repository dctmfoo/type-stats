import XCTest
@testable import TypeStatsCore

@MainActor
final class WeeklyActivityTests: XCTestCase {
    func testSevenDatedRowsAnd24HoursIncludeLiveCountsExactlyOnce() throws {
        let clock = TestClock("2026-10-05 10:30")
        let store = try CountStore(directory: makeTestDirectory())
        try store.add(day: "2026-09-28", hour: 10, app: terminal, keys: 999)
        try store.add(day: "2026-09-29", hour: 10, app: terminal, keys: 2)
        try store.add(day: "2026-09-29", hour: 10, app: claude, keys: 3)
        try store.add(day: "2026-10-05", hour: 10, app: terminal, keys: 4)
        try store.save()
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        counter.record(claude)
        counter.recordClick(claude)
        let activity = try counter.weeklyActivity()
        XCTAssertEqual(activity.rows.map(\.day), History.dayKeys(endingAt: clock.date, count: 7, calendar: clock.calendar))
        XCTAssertTrue(activity.rows.allSatisfy { $0.cells.count == 24 })
        XCTAssertEqual(activity.rows[0].cells[10], .count(5))
        XCTAssertEqual(activity.rows[6].cells[10], .count(5))
        XCTAssertEqual(activity.rows[6].cells[9], .count(0))
        XCTAssertEqual(activity.rows[6].cells[11], .future)
        XCTAssertEqual(activity.placedKeys, 10)
        XCTAssertEqual(activity.totalKeys, 10)
        XCTAssertNil(activity.coverageText)
        XCTAssertEqual(activity.peaks.count, 2)
        XCTAssertEqual(activity.peakText, "Peak Tue 29, 10-11 am · 2 tied · local time")
        try counter.flush()
        XCTAssertEqual(try counter.weeklyActivity(), activity)
        XCTAssertEqual(ShareSummary.make(period: .week, counter: counter).activity, activity)
        XCTAssertNil(ShareSummary.make(period: .today, counter: counter).activity)
        XCTAssertNil(ShareSummary.make(period: .month, counter: counter).activity)
    }

    func testRolloverWithoutAnEventAndFlushKeepYesterdayOnce() throws {
        let clock = TestClock("2026-10-04 23:59")
        let store = try CountStore(directory: makeTestDirectory())
        try store.add(day: "2026-10-04", hour: 23, app: terminal, keys: 2)
        try store.save()
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        counter.record(terminal)
        _ = try counter.weeklyActivity() // populate the past-hours cache
        clock.set("2026-10-05 00:01")
        let rolled = try counter.weeklyActivity()
        XCTAssertEqual(rolled.rows[5].cells[23], .count(3))
        XCTAssertEqual(rolled.rows[6].cells[0], .count(0))
        XCTAssertEqual(rolled.rows[6].cells[1], .future)
        XCTAssertEqual(rolled.totalKeys, 3)
        counter.record(claude)
        let live = try counter.weeklyActivity()
        XCTAssertEqual(live.totalKeys, 4)
        try counter.flush()
        XCTAssertEqual(try counter.weeklyActivity(), live)
        let reopened = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(try reopened.weeklyActivity(), live)
    }

    func testLegacyCoverageEmptyWeekAndSinglePeak() throws {
        let clock = TestClock("2026-10-05 10:30")
        let store = try CountStore(directory: makeTestDirectory())
        let empty = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date }).weeklyActivity()
        XCTAssertEqual(empty.peakText, "No hourly typing yet · local time")
        XCTAssertEqual(empty.peakKeys, 0)
        XCTAssertTrue(empty.peaks.isEmpty)
        try store.add(day: "2026-09-29", app: terminal, keys: 90)
        try store.add(day: "2026-10-05", app: terminal, keys: 10)
        try store.add(day: "2026-10-05", hour: 10, app: claude, keys: 100)
        try store.save()
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        let activity = try counter.weeklyActivity()
        XCTAssertEqual(activity.coverageText, "Based on 100 of 200 keys")
        XCTAssertEqual(activity.peakText, "Peak Mon 5, 10-11 am · local time")
        XCTAssertEqual(activity.rows[0].cells[10], .count(0), "legacy keys never get invented hours")
    }

    func testFourShadeStepsHaveDistinctZeroAndExactBoundaries() throws {
        XCTAssertTrue(try LaunchOptions.parse(["--no-tap", "--dark-snapshot"]).darkSnapshot)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 0, peak: 100), 0)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 1, peak: 100), 1)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 25, peak: 100), 1)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 26, peak: 100), 2)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 50, peak: 100), 2)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 51, peak: 100), 3)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 75, peak: 100), 3)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 76, peak: 100), 4)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 100, peak: 100), 4)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 1, peak: 1), 4)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 0, peak: 0), 0)
        XCTAssertEqual(WeeklyActivity.hourRange(0), "12-1 am")
        XCTAssertEqual(WeeklyActivity.hourRange(11), "11 am-12 pm")
        XCTAssertEqual(WeeklyActivity.hourRange(12), "12-1 pm")
        XCTAssertEqual(WeeklyActivity.hourRange(23), "11 pm-12 am")
    }

    func testScreenHeightSeamParsesPositiveValuesOnly() throws {
        XCTAssertEqual(try LaunchOptions.parse(["--screen-height", "700"]).screenHeight, 700)
        XCTAssertNil(try LaunchOptions.parse([]).screenHeight)
        XCTAssertThrowsError(try LaunchOptions.parse(["--screen-height", "0"]))
        XCTAssertThrowsError(try LaunchOptions.parse(["--screen-height", "tall"]))
        XCTAssertThrowsError(try LaunchOptions.parse(["--screen-height"]))
    }
}
