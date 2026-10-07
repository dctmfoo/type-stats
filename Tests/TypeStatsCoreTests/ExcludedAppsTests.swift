import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import TypeStatsCore

private let passwords = AppIdentity(bundleID: "com.example.passwords", name: "Passwords")

@MainActor
final class ExcludedAppsTests: XCTestCase {
    func testExcludedAppPressesAndClicksAreNeverCounted() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        try counter.exclude(passwords)

        XCTAssertFalse(counter.record(passwords))
        XCTAssertFalse(counter.record(passwords, kind: .typingCharacter, at: 1.0))
        counter.recordClick(passwords)
        XCTAssertTrue(counter.record(terminal))

        XCTAssertNil(counter.todayCounts[passwords.bundleID], "an excluded app gets no row today")
        XCTAssertEqual(counter.total, 1)
        XCTAssertEqual(counter.totalClicks, 0)
        XCTAssertEqual(counter.pendingCount, 1)
        XCTAssertNil(counter.todayHours.values.first { $0.keys + $0.clicks > 1 })
    }

    func testExcludedPressesDoNotFeedTypingSpeed() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        try counter.exclude(passwords)
        // Excluded activity breaks the writing stretch even with short gaps.
        for i in 0..<20 {
            counter.record(terminal, kind: .typingCharacter, at: Double(i))
            counter.record(passwords, kind: .typingCharacter, at: Double(i) + 0.5)
        }
        let row = try XCTUnwrap(counter.todayCounts[terminal.bundleID])
        XCTAssertEqual(row.count, 20)
        XCTAssertEqual(row.burstCount, 0, "excluded input breaks typing continuity")
        XCTAssertEqual(row.activeSeconds, 0, accuracy: 0.001)
    }

    func testHistoryIsKeptAndTheAppIsMarkedExcluded() throws {
        let store = try CountStore(directory: makeTestDirectory())
        let counter = try KeyCounter(store: store)
        for _ in 0..<4 { counter.record(passwords) }
        counter.recordClick(passwords)
        counter.record(terminal)
        try counter.flush()

        try counter.exclude(passwords)
        for _ in 0..<10 { counter.record(passwords) }
        try counter.flush()

        XCTAssertEqual(counter.todayCounts[passwords.bundleID]?.count, 4, "counts from before exclusion stay")
        XCTAssertEqual(counter.todayCounts[passwords.bundleID]?.clicks, 1)
        XCTAssertEqual(try store.counts(day: counter.day).first { $0.bundleID == passwords.bundleID }?.count, 4)
        let top = counter.topApps(limit: 8)
        XCTAssertEqual(top.map(\.bundleID), [passwords.bundleID, terminal.bundleID])
        XCTAssertEqual(top.map(\.excluded), [true, false])
        XCTAssertEqual(counter.markExcluded(try counter.history(days: 7).apps).map(\.excluded), [true, false])

        try counter.include(bundleID: passwords.bundleID)
        counter.record(passwords)
        XCTAssertEqual(counter.todayCounts[passwords.bundleID]?.count, 5, "counting resumes after removing the exclusion")
        XCTAssertEqual(counter.topApps(limit: 8).map(\.excluded), [false, false])
    }

    func testExclusionListPersistsAcrossRestartsAndRemovalToo() throws {
        let dir = try makeTestDirectory()
        do {
            let counter = try KeyCounter(store: CountStore(directory: dir))
            try counter.exclude(passwords)
            try counter.exclude(terminal)
            try counter.exclude(passwords)  // twice: still one entry
            XCTAssertEqual(counter.excludedApps.map(\.bundleID), [passwords.bundleID, terminal.bundleID])
        }
        let reopened = try KeyCounter(store: CountStore(directory: dir))
        XCTAssertEqual(reopened.excludedApps.map(\.bundleID), [passwords.bundleID, terminal.bundleID])
        XCTAssertEqual(reopened.excludedApps.map(\.name), ["Passwords", "Terminal"])
        XCTAssertFalse(reopened.record(passwords), "still excluded after a restart")

        try reopened.include(bundleID: terminal.bundleID)
        let again = try KeyCounter(store: CountStore(directory: dir))
        XCTAssertEqual(again.excludedApps.map(\.bundleID), [passwords.bundleID])
        XCTAssertTrue(again.record(terminal))
    }

    func testStoreWithoutExclusionsUpgradesInPlace() throws {
        let dir = try makeTestDirectory()
        // A store written before this feature knew only the two count models.
        do {
            let url = dir.appendingPathComponent(CountStore.fileName)
            let old = try ModelContainer(for: AppDayCount.self, AppHourCount.self, configurations: ModelConfiguration(url: url))
            old.mainContext.insert(AppDayCount(day: "2026-10-04", bundleID: terminal.bundleID, appName: "Terminal", count: 7, clicks: 2))
            try old.mainContext.save()
        }
        let clock = TestClock("2026-10-04 12:00")
        let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.count, 7)
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.clicks, 2)
        XCTAssertTrue(counter.excludedApps.isEmpty)
        try counter.exclude(terminal)
        XCTAssertEqual(try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
            .todayCounts[terminal.bundleID]?.count, 7)
    }

    func testPipelineDropsKeysAndClicksForExcludedApps() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        try counter.exclude(passwords)
        var front = passwords
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { front }, appAtPoint: { _ in passwords })

        let key = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertFalse(pipeline.handle(type: .keyDown, event: key), "a key in the frontmost excluded app")
        let click = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left))
        XCTAssertFalse(pipeline.handle(type: .leftMouseDown, event: click), "a click on an excluded app's window")
        XCTAssertEqual(counter.total + counter.totalClicks, 0)

        // The click goes to the window under the pointer, not to the frontmost app, even
        // when that app is not excluded: excluding the window's app wins.
        front = terminal
        XCTAssertFalse(pipeline.handle(type: .leftMouseDown, event: click))
        XCTAssertEqual(counter.totalClicks, 0)
        XCTAssertTrue(pipeline.handle(type: .keyDown, event: key), "a key in a non-excluded frontmost app")
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.count, 1)
    }

    func testLaunchOptionsForExclusions() throws {
        let o = try LaunchOptions.parse(["--exclude", "com.a, com.b", "--include", "com.c", "--dump-excluded", "--excluded-page"])
        XCTAssertEqual(o.exclude, ["com.a", "com.b"])
        XCTAssertEqual(o.include, ["com.c"])
        XCTAssertTrue(o.dumpExcluded)
        XCTAssertTrue(o.excludedPage)
        let none = try LaunchOptions.parse([])
        XCTAssertEqual(none.exclude, [])
        XCTAssertFalse(none.dumpExcluded)
        XCTAssertFalse(none.excludedPage)
        XCTAssertThrowsError(try LaunchOptions.parse(["--exclude"]))
    }
}
