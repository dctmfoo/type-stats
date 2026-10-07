import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import TypeStatsCore

@MainActor
final class TypingSpeedTests: XCTestCase {
    /// `n` presses evenly spread over `seconds`, starting at `start`.
    private func type(_ counter: KeyCounter, _ app: AppIdentity, _ n: Int, over seconds: Double, from start: Double) {
        for i in 0..<n { counter.record(app, kind: .typingCharacter, at: start + Double(i) * seconds / Double(n)) }
    }

    func test300KeysEvenlyOver60SecondsIs60WPM() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        type(counter, terminal, 300, over: 60, from: 1000)
        XCTAssertEqual(counter.wpm ?? 0, 12.0 * 300 / 59.8, accuracy: 0.001)
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.wpm ?? 0, 12.0 * 300 / 59.8, accuracy: 0.001)
        XCTAssertEqual(counter.total, 300, "typing speed never changes the key count")
    }

    func testLongPausesAreNotCounted() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        type(counter, terminal, 300, over: 60, from: 1000)      // 60 WPM
        type(counter, terminal, 300, over: 60, from: 1000 + 60 + 600)  // 10 minutes idle, then 60 WPM again
        // Single presses 5 s apart: each one is idle time, none is a burst.
        for i in 0..<10 { counter.record(terminal, kind: .typingCharacter, at: 2000 + Double(i) * 5) }
        XCTAssertEqual(counter.wpm ?? 0, 12.0 * 300 / 59.8, accuracy: 0.001, "idle time must not lower the speed")
        XCTAssertEqual(counter.total, 610)
    }

    func testTooLittleTypingHasNoSpeedAndUntimedPressesAreIgnored() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        type(counter, chatgpt, 20, over: 4, from: 50)  // 3.8 s of typing: below the 10 s stretch minimum
        for _ in 0..<50 { counter.record(chatgpt) }    // no time: counted, not timed
        XCTAssertNil(counter.wpm)
        XCTAssertEqual(counter.total, 70)
        XCTAssertEqual(TypingSpeed.wpm(burstCount: 0, activeSeconds: 100), 0)
        XCTAssertEqual(TypingSpeed.wpm(burstCount: 50, activeSeconds: 10) ?? 0, 60, accuracy: 1e-9)
    }

    func testSpeedIsPerAppAndPersists() throws {
        let dir = try makeTestDirectory()
        let clock = TestClock("2026-10-04 14:00")
        do {
            let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
            type(counter, terminal, 300, over: 60, from: 100)   // 60 WPM
            type(counter, claude, 400, over: 60, from: 200)     // 80 WPM
            try counter.flush()
        }
        let reopened = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(reopened.todayCounts[terminal.bundleID]?.wpm ?? 0, 12.0 * 300 / 59.8, accuracy: 0.001)
        XCTAssertEqual(reopened.todayCounts[claude.bundleID]?.wpm ?? 0, 12.0 * 400 / 59.85, accuracy: 0.001)
        // Overall: all burst presses over all active time.
        XCTAssertEqual(reopened.wpm ?? 0, 12.0 * 700 / (59.8 + 59.85), accuracy: 0.001)
    }

    func testPipelineTimesKeysFromEventTimestamps() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { terminal })
        let base = EventClock.nowNanos() - 120_000_000_000
        for i in 0..<300 {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
            e.timestamp = base + UInt64(i) * 200_000_000  // every 0.2 s
            pipeline.handle(type: .keyDown, event: e)
        }
        // Events without a timestamp (0) count but never add typing time.
        pipeline.handle(type: .keyDown, event: CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!)
        XCTAssertEqual(counter.total, 301)
        XCTAssertEqual(counter.wpm ?? 0, 12.0 * 300 / 59.8, accuracy: 0.001)
    }

    func testEventClockReadsNanosecondsOrMachTicks() {
        let timebase = EventClock.Timebase(numer: 125, denom: 3)  // Apple silicon: 1 tick = 41.67 ns
        let nowNanos: UInt64 = 36_000_000_000_000                 // 10 h after boot
        let nowTicks = nowNanos * 3 / 125
        XCTAssertNil(EventClock.seconds(fromEventTimestamp: 0, nowNanos: nowNanos, nowTicks: nowTicks, timebase: timebase))
        let fromNanos = EventClock.seconds(fromEventTimestamp: nowNanos - 1_000_000_000, nowNanos: nowNanos,
                                           nowTicks: nowTicks, timebase: timebase)
        XCTAssertEqual(fromNanos ?? 0, 35_999, accuracy: 1e-6)
        let fromTicks = EventClock.seconds(fromEventTimestamp: nowTicks - 24_000_000, nowNanos: nowNanos,
                                           nowTicks: nowTicks, timebase: timebase)
        XCTAssertEqual(fromTicks ?? 0, 35_999, accuracy: 1e-6)
    }
}

@MainActor
final class HourlyTests: XCTestCase {
    func testKeysAndClicksLandInTheirLocalHour() throws {
        let dir = try makeTestDirectory()
        let clock = TestClock("2026-10-04 09:15")
        let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        for _ in 0..<3 { counter.record(terminal) }
        clock.set("2026-10-04 09:59")
        counter.recordClick(claude)
        clock.set("2026-10-04 10:00")
        for _ in 0..<2 { counter.record(claude) }
        clock.set("2026-10-04 23:30")
        counter.recordClick(terminal)

        let expected = [9: HourCount(hour: 9, keys: 3, clicks: 1), 10: HourCount(hour: 10, keys: 2, clicks: 0),
                        23: HourCount(hour: 23, keys: 0, clicks: 1)]
        XCTAssertEqual(counter.todayHours, expected, "live, before saving")
        try counter.flush()
        XCTAssertEqual(try CountStore(directory: dir).hours(day: "2026-10-04"), expected, "stored")
        let reopened = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(reopened.todayHours, expected, "after relaunch")
        XCTAssertEqual(reopened.keysWithoutHour, 0)

        clock.set("2026-10-05 00:10")
        reopened.record(terminal)
        XCTAssertEqual(reopened.todayHours, [0: HourCount(hour: 0, keys: 1)], "a new day starts with empty hours")
    }

    func testCountsWithoutHourAreReportedNotLost() throws {
        let dir = try makeTestDirectory()
        let clock = TestClock("2026-10-04 15:00")
        let store = try CountStore(directory: dir)
        try store.add(day: "2026-10-04", app: terminal, keys: 40, clicks: 4)  // as before hourly counts existed
        try store.save()
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        counter.record(terminal)
        XCTAssertEqual(counter.total, 41)
        XCTAssertEqual(counter.todayHours, [15: HourCount(hour: 15, keys: 1)])
        XCTAssertEqual(counter.keysWithoutHour, 40)
        XCTAssertEqual(counter.clicksWithoutHour, 4)
    }
}

@MainActor
final class HistoryTests: XCTestCase {
    private func seed(_ dir: URL, _ entries: [(String, AppIdentity, Int, Int)]) throws {
        let store = try CountStore(directory: dir)
        for (day, app, keys, clicks) in entries { try store.add(day: day, hour: 12, app: app, keys: keys, clicks: clicks) }
        try store.save()
    }

    func testSevenAndThirtyDayWindowsWithPerAppTotals() throws {
        let dir = try makeTestDirectory()
        try seed(dir, [
            ("2026-09-04", terminal, 1000, 100),  // 30 days back: outside both
            ("2026-09-05", terminal, 50, 5),      // 29 days back: inside 30 only
            ("2026-09-27", claude, 70, 7),        // 7 days back: inside 30 only
            ("2026-09-28", claude, 20, 2),        // 6 days back: inside both
            ("2026-10-02", terminal, 30, 0),
            ("2026-10-02", chatgpt, 0, 9),
            ("2026-10-04", terminal, 5, 1),       // today, saved
        ])
        let clock = TestClock("2026-10-04 18:00")
        let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        counter.record(claude)  // today, not saved yet
        counter.recordClick(chatgpt)

        let week = try counter.history(days: 7)
        XCTAssertEqual(week.days.map(\.day), ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01",
                                              "2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertEqual(week.days.map(\.keys), [20, 0, 0, 0, 30, 0, 6])
        XCTAssertEqual(week.days.map(\.clicks), [2, 0, 0, 0, 9, 0, 2])
        XCTAssertEqual(week.apps.map(\.bundleID), [terminal.bundleID, claude.bundleID, chatgpt.bundleID])
        XCTAssertEqual(week.apps.map(\.count), [35, 21, 0])
        XCTAssertEqual(week.apps.map(\.clicks), [1, 2, 10])
        XCTAssertEqual(week.totalKeys, 56)
        XCTAssertEqual(week.totalClicks, 13)

        let month = try counter.history(days: 30)
        XCTAssertEqual(month.days.count, 30)
        XCTAssertEqual(month.days.first?.day, "2026-09-05")
        XCTAssertEqual(month.totalKeys, 56 + 50 + 70)
        XCTAssertEqual(month.totalClicks, 13 + 5 + 7)
        XCTAssertEqual(month.apps.map(\.count), [91, 85, 0])
        XCTAssertEqual(month.apps.map(\.bundleID), [claude.bundleID, terminal.bundleID, chatgpt.bundleID])

        // Saving does not change what history shows.
        try counter.flush()
        XCTAssertEqual(try counter.history(days: 7), week)
    }

    func testPastDaysAreReadOnceWhileTodayStaysLive() throws {
        let dir = try makeTestDirectory()
        try seed(dir, [("2026-10-02", terminal, 30, 3)])
        let clock = TestClock("2026-10-04 18:00")
        let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })

        XCTAssertEqual(try counter.history(days: 7).totalKeys, 30)
        // Redraws while typing: today's live counts show at once, past days are not read again.
        for expected in 31...40 {
            counter.record(claude)
            XCTAssertEqual(try counter.history(days: 7).totalKeys, expected)
        }
        try counter.flush()
        XCTAssertEqual(try counter.history(days: 7).totalKeys, 40)
        XCTAssertEqual(counter.pastRowFetches, 1)
        _ = try counter.history(days: 30)
        XCTAssertEqual(counter.pastRowFetches, 2, "another period is its own read")
    }

    func testCountsFlushedAfterMidnightReachThePastDayOnce() throws {
        let dir = try makeTestDirectory()
        let clock = TestClock("2026-10-04 23:59")
        let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        for _ in 0..<3 { counter.record(terminal) }

        clock.set("2026-10-05 00:01")
        counter.record(claude)
        // Yesterday's 3 presses are still unsaved: history shows them from memory.
        XCTAssertEqual(try counter.history(days: 7).days.suffix(2).map(\.keys), [3, 1])
        try counter.flush()
        // Now they are saved rows of a past day: shown once, not twice and not lost.
        XCTAssertEqual(try counter.history(days: 7).days.suffix(2).map(\.keys), [3, 1])
        XCTAssertEqual(try counter.history(days: 7).totalKeys, 4)
    }

    func testHistorySpeedCombinesDays() throws {
        let dir = try makeTestDirectory()
        let store = try CountStore(directory: dir)
        try store.add(day: "2026-10-03", app: terminal, keys: 300, burstCount: 299, activeSeconds: 59.8)
        try store.save()
        let clock = TestClock("2026-10-04 10:00")
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        for i in 0..<400 { counter.record(terminal, kind: .typingCharacter, at: Double(i) * 0.15) }  // 400 keys over 60 s: 80 WPM
        let week = try counter.history(days: 7)
        XCTAssertEqual(week.wpm ?? 0, 12.0 * (299 + 400) / (59.8 + 399 * 0.15), accuracy: 0.001)
        XCTAssertEqual(week.apps.first?.count, 700)
    }
}

/// The schema task 02 shipped (keys and clicks per day), as the owner's store is written now.
enum TaskTwoSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [AppDayCount.self] }

    @Model
    final class AppDayCount {
        var day: String
        var bundleID: String
        var appName: String
        var count: Int
        var clicks: Int = 0

        init(day: String, bundleID: String, appName: String, count: Int, clicks: Int) {
            self.day = day
            self.bundleID = bundleID
            self.appName = appName
            self.count = count
            self.clicks = clicks
        }
    }
}

@MainActor
final class TaskTwoUpgradeTests: XCTestCase {
    func testTaskTwoStoreKeepsKeysAndClicksAndHasNoHoursOrSpeed() throws {
        let dir = try makeTestDirectory()
        do {
            let config = ModelConfiguration(url: dir.appendingPathComponent(CountStore.fileName))
            let old = try ModelContainer(for: Schema(versionedSchema: TaskTwoSchema.self), configurations: config)
            let context = ModelContext(old)
            context.insert(TaskTwoSchema.AppDayCount(day: "2026-10-04", bundleID: terminal.bundleID, appName: "Terminal", count: 1240, clicks: 85))
            context.insert(TaskTwoSchema.AppDayCount(day: "2026-10-04", bundleID: claude.bundleID, appName: "Claude", count: 860, clicks: 312))
            context.insert(TaskTwoSchema.AppDayCount(day: "2026-10-01", bundleID: terminal.bundleID, appName: "Terminal", count: 77, clicks: 3))
            try context.save()
        }

        let clock = TestClock("2026-10-04 20:00")
        let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        let today = counter.topApps(limit: 10)
        XCTAssertEqual(today.map(\.bundleID), [terminal.bundleID, claude.bundleID])
        XCTAssertEqual(today.map(\.count), [1240, 860], "keys survive the upgrade unchanged")
        XCTAssertEqual(today.map(\.clicks), [85, 312], "clicks survive the upgrade unchanged")
        XCTAssertEqual(today.map(\.burstCount), [0, 0])
        XCTAssertNil(counter.wpm, "no typing time before the upgrade")
        XCTAssertEqual(counter.todayHours, [:], "no hours before the upgrade")
        XCTAssertEqual(counter.keysWithoutHour, 2100)
        XCTAssertEqual(counter.clicksWithoutHour, 397)
        let week = try counter.history(days: 7)
        XCTAssertEqual(week.days.first { $0.day == "2026-10-01" }?.keys, 77, "earlier days still appear")
        XCTAssertEqual(week.totalKeys, 2177)

        // The upgraded store takes hourly counts and typing time and keeps them.
        for i in 0..<300 { counter.record(claude, kind: .typingCharacter, at: Double(i) * 0.2) }
        try counter.flush()
        let reopened = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(reopened.topApps(limit: 10).map(\.count), [1240, 1160])
        XCTAssertEqual(reopened.topApps(limit: 10).map(\.clicks), [85, 312])
        XCTAssertEqual(reopened.todayHours, [20: HourCount(hour: 20, keys: 300)])
        XCTAssertEqual(reopened.todayCounts[claude.bundleID]?.wpm ?? 0, 12.0 * 300 / 59.8, accuracy: 0.001)
    }
}

@MainActor
final class LoginItemTests: XCTestCase {
    private final class FakeService: LoginItemService {
        var status: LoginItemStatus = .disabled
        var calls: [String] = []
        var failNext: Error?
        var approvalNeeded = false

        func register() throws {
            calls.append("register")
            if let e = failNext { failNext = nil; throw e }
            status = approvalNeeded ? .requiresApproval : .enabled
        }

        func unregister() throws {
            calls.append("unregister")
            if let e = failNext { failNext = nil; throw e }
            status = .disabled
        }
    }

    private struct Denied: Error {}

    func testToggleRegistersAndUnregistersAndShowsSystemStatus() {
        let service = FakeService()
        let item = LoginItem(service: service)
        XCTAssertFalse(item.isOn)

        item.set(true)
        XCTAssertEqual(service.calls, ["register"])
        XCTAssertTrue(item.isOn)
        XCTAssertEqual(item.status, .enabled)

        item.set(false)
        XCTAssertEqual(service.calls, ["register", "unregister"])
        XCTAssertFalse(item.isOn)

        // Changed outside the app (System Settings): the toggle follows on refresh.
        service.status = .enabled
        XCTAssertFalse(item.isOn)
        item.refresh()
        XCTAssertTrue(item.isOn)
    }

    func testFailureLeavesStatusAsTheSystemReportsIt() {
        let service = FakeService()
        let item = LoginItem(service: service)
        service.failNext = Denied()
        item.set(true)
        XCTAssertFalse(item.isOn, "a failed register must not show as on")
        XCTAssertNotNil(item.lastError)
        item.set(true)
        XCTAssertTrue(item.isOn)
        XCTAssertNil(item.lastError)
    }

    func testWaitingForApprovalShowsOn() {
        let service = FakeService()
        service.approvalNeeded = true
        let item = LoginItem(service: service)
        item.set(true)
        XCTAssertEqual(item.status, .requiresApproval)
        XCTAssertTrue(item.isOn)
    }

    func testTestModeServiceStaysInMemory() throws {
        let item = LoginItem(service: InMemoryLoginItemService())
        item.set(true)
        XCTAssertTrue(item.isOn)
    }
}

final class HistoryLaunchOptionsTests: XCTestCase {
    func testParsesNoTestBanner() throws {
        XCTAssertFalse(try LaunchOptions.parse(["--no-tap"]).noTestBanner)
        XCTAssertTrue(try LaunchOptions.parse(["--no-tap", "--no-test-banner"]).noTestBanner)
    }

    func testParsesHistorySeams() throws {
        let tz = TimeZone(identifier: "Asia/Kolkata")!
        let o = try LaunchOptions.parse([
            "--simulate-typing", "com.apple.TextEdit:300:60, com.openai.chat:200:30.5",
            "--at", "2026-10-01T14:00", "--dump-hours", "--dump-history", "30", "--dump-wpm",
            "--view", "week", "--login-status",
        ], timeZone: tz)
        XCTAssertEqual(o.simulateTyping, [
            .init(bundleID: "com.apple.TextEdit", keys: 300, seconds: 60),
            .init(bundleID: "com.openai.chat", keys: 200, seconds: 30.5),
        ])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        XCTAssertEqual(o.at, cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 14)))
        XCTAssertTrue(o.dumpHours)
        XCTAssertEqual(o.dumpHistory, 30)
        XCTAssertTrue(o.dumpWPM)
        XCTAssertTrue(o.loginStatus)
        XCTAssertEqual(o.view, .week)
        XCTAssertEqual(try LaunchOptions.parse([]).view, .today)
        XCTAssertNotNil(try LaunchOptions.parse(["--at", "2026-10-01T14:00:30"]).at)
    }

    func testParsesSteadyPopupSeams() throws {
        let o = try LaunchOptions.parse(["--seed-nohour", "com.x:40,com.y:3", "--measure-views"])
        XCTAssertEqual(o.seedNoHour.map { "\($0.bundleID):\($0.count)" }, ["com.x:40", "com.y:3"])
        XCTAssertTrue(o.measureViews)
        XCTAssertFalse(try LaunchOptions.parse([]).measureViews)
        XCTAssertThrowsError(try LaunchOptions.parse(["--seed-nohour", "com.x"]))
    }

    func testParsesReadyFile() throws {
        XCTAssertEqual(try LaunchOptions.parse(["--ready-file", "/tmp/r"]).readyFile, URL(fileURLWithPath: "/tmp/r"))
        XCTAssertNil(try LaunchOptions.parse([]).readyFile)
        XCTAssertThrowsError(try LaunchOptions.parse(["--ready-file"]))
    }

    func testRejectsBadHistorySpecs() {
        for args in [["--simulate-typing", "com.x:300"], ["--simulate-typing", "com.x:0:60"],
                     ["--simulate-typing", "com.x:10:0"], ["--simulate-typing", ":10:5"],
                     ["--at", "2026-10-01"], ["--at", "yesterday"], ["--dump-history", "0"],
                     ["--view", "year"]] {
            XCTAssertThrowsError(try LaunchOptions.parse(args), "\(args)")
        }
    }

    func testDayKeysEndingTodayAcrossMonthEnd() {
        let clock = TestClock("2026-10-02 08:00")
        XCTAssertEqual(History.dayKeys(endingAt: clock.date, count: 4, calendar: clock.calendar),
                       ["2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"])
    }
}
