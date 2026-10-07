import Foundation
import SwiftData
import XCTest
@testable import TypeStatsCore

/// The shape of the daily goal table that earlier versions wrote into the store.
@Model
final class DailyGoalChange {
    var day: String
    var goal: Int

    init(day: String, goal: Int) {
        self.day = day
        self.goal = goal
    }
}

@MainActor
final class LegacyStoreTests: XCTestCase {
    func testOldSpeedTotalsLoadUnchangedAndNewDayUsesSteadyNetSpeed() throws {
        let directory = try makeTestDirectory()
        let url = directory.appendingPathComponent(CountStore.fileName)
        // Exact pre-option-C schema and fields. It has a valid speed from only 6 seconds.
        do {
            let old = try ModelContainer(for: AppDayCount.self, AppHourCount.self, ExcludedApp.self,
                                         configurations: ModelConfiguration(url: url))
            old.mainContext.insert(AppDayCount(day: "2026-10-06", bundleID: terminal.bundleID,
                                               appName: terminal.name, count: 60, clicks: 4,
                                               burstCount: 25, activeSeconds: 6))
            try old.mainContext.save()
        }
        let clock = TestClock("2026-10-07 10:00")
        let store = try CountStore(directory: directory)
        let before = try XCTUnwrap(store.counts(day: "2026-10-06").first)
        XCTAssertEqual(before.wpm, 50)
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        for i in 0...10 { counter.record(terminal, kind: .typingCharacter, at: Double(i)) }
        counter.record(terminal, kind: .backspace, at: 11)
        try counter.flush()
        let reopened = try CountStore(directory: directory)
        XCTAssertEqual(try reopened.counts(day: "2026-10-06").first, before, "old speed and counts must not be rewritten")
        let today = try XCTUnwrap(reopened.counts(day: "2026-10-07").first)
        XCTAssertEqual(today.count, 12)
        XCTAssertEqual(today.burstCount, 10)
        XCTAssertEqual(today.activeSeconds, 11)
        XCTAssertEqual(today.wpm ?? -1, 120.0 / 11, accuracy: 0.001)
        XCTAssertEqual(try counter.history(days: 7).wpm ?? -1, 12.0 * 35 / 17, accuracy: 0.001)
    }

    func testStoreWithAStoredGoalStillOpensAndKeepsItsCounts() throws {
        let directory = try makeTestDirectory()
        let url = directory.appendingPathComponent(CountStore.fileName)
        do {
            let old = try ModelContainer(
                for: AppDayCount.self, AppHourCount.self, ExcludedApp.self, DailyGoalChange.self,
                configurations: ModelConfiguration(url: url))
            old.mainContext.insert(AppDayCount(day: "2026-10-04", bundleID: terminal.bundleID,
                                               appName: terminal.name, count: 7, clicks: 2))
            old.mainContext.insert(DailyGoalChange(day: "2026-10-01", goal: 5_000))
            try old.mainContext.save()
        }

        let store = try CountStore(directory: directory)
        let rows = try store.counts(day: "2026-10-04")
        XCTAssertEqual(rows.map(\.bundleID), [terminal.bundleID])
        XCTAssertEqual(rows.first?.count, 7)
        XCTAssertEqual(rows.first?.clicks, 2)

        let counter = try KeyCounter(store: store)
        counter.record(terminal)
        try counter.flush()
        XCTAssertEqual(counter.total, 1)
    }
}
