import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import TypeStatsCore

@MainActor
final class KeyCounterTests: XCTestCase {
    func testEachPressAddsExactlyOneToThatAppsCount() throws {
        let store = try CountStore(directory: makeTestDirectory())
        let counter = try KeyCounter(store: store)
        for _ in 0..<3 { counter.record(terminal) }
        counter.record(chatgpt)

        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.count, 3)
        XCTAssertEqual(counter.todayCounts[chatgpt.bundleID]?.count, 1)
        XCTAssertEqual(counter.total, 4)

        try counter.flush()
        XCTAssertEqual(counter.pendingCount, 0)
        let stored = try store.counts(day: counter.day)
        XCTAssertEqual(stored.map(\.bundleID), [terminal.bundleID, chatgpt.bundleID])
        XCTAssertEqual(stored.map(\.count), [3, 1])

        // A second batch adds to the stored row instead of replacing it.
        counter.record(terminal)
        try counter.flush()
        XCTAssertEqual(try store.counts(day: counter.day).first?.count, 4)
    }

    func testPressesAreBucketedByLocalDay() throws {
        let clock = TestClock("2026-10-04 23:59")
        let store = try CountStore(directory: makeTestDirectory())
        let counter = try KeyCounter(store: store, calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(counter.day, "2026-10-04")
        counter.record(terminal)
        counter.record(terminal)

        clock.set("2026-10-05 00:01")
        counter.record(terminal)
        XCTAssertEqual(counter.day, "2026-10-05")
        XCTAssertEqual(counter.total, 1, "today starts fresh after midnight")
        try counter.flush()

        XCTAssertEqual(try store.counts(day: "2026-10-04").first?.count, 2)
        XCTAssertEqual(try store.counts(day: "2026-10-05").first?.count, 1)
    }

    func testTopAppsOrderedByCountThenName() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        for _ in 0..<2 { counter.record(terminal) }
        for _ in 0..<5 { counter.record(claude) }
        for _ in 0..<2 { counter.record(chatgpt) }

        XCTAssertEqual(counter.topApps(limit: 10).map(\.name), ["Claude", "ChatGPT", "Terminal"])
        XCTAssertEqual(counter.topApps(limit: 2).map(\.count), [5, 2])
    }

    func testCountsPersistAcrossStoreReopen() throws {
        let dir = try makeTestDirectory()
        let clock = TestClock("2026-10-04 10:00")
        do {
            let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
            for _ in 0..<7 { counter.record(claude) }
            counter.record(terminal)
            try counter.flush()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(CountStore.fileName).path))

        // Reopen as a new launch would: today's counts load from disk and keep growing.
        let reopened = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(reopened.todayCounts[claude.bundleID]?.count, 7)
        XCTAssertEqual(reopened.todayCounts[terminal.bundleID]?.count, 1)
        XCTAssertEqual(reopened.total, 8)
        reopened.record(claude)
        try reopened.flush()

        let third = try CountStore(directory: dir)
        XCTAssertEqual(try third.counts(day: "2026-10-04").map(\.count), [8, 1])
    }

    func testStoredModelHasNoKeyTextOrClickPositionFields() throws {
        // Allowed: counts, day/hour buckets, app identity and typing-time totals.
        let schema = Schema([AppDayCount.self, AppHourCount.self])
        let attributes = Dictionary(uniqueKeysWithValues: schema.entities.map { ($0.name, Set($0.attributes.map(\.name))) })
        XCTAssertEqual(attributes, [
            "AppDayCount": ["day", "bundleID", "appName", "count", "clicks", "burstCount", "activeSeconds"],
            "AppHourCount": ["day", "hour", "bundleID", "count", "clicks"],
        ])
        XCTAssertEqual(schema.entities.flatMap(\.relationships).count, 0)

        let rows: [Any] = [AppDayCount(day: "2026-10-04", bundleID: "x", appName: "X", count: 1),
                           AppHourCount(day: "2026-10-04", hour: 9, bundleID: "x", count: 1, clicks: 0)]
        for row in rows {
            let labels = Set(Mirror(reflecting: row).children.compactMap(\.label))
            for forbidden in ["key", "keyCode", "text", "character", "characters", "chars",
                              "location", "position", "point", "window", "title"] {
                XCTAssertFalse(labels.contains { $0.lowercased().contains(forbidden.lowercased()) && $0 != "_$backingData" },
                               "stored model must not have a \(forbidden) field: \(labels)")
            }
        }
    }
}

@MainActor
final class KeyPressPipelineTests: XCTestCase {
    private func keyDown(_ text: String? = nil, autorepeat: Bool = false) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        if let text {
            let units = Array(text.utf16)
            e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        }
        if autorepeat { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return e
    }

    func testCountsKeyDownForFrontmostAppAndIgnoresAutorepeatAndKeyUp() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        var front: AppIdentity? = terminal
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { front })

        XCTAssertTrue(pipeline.handle(type: .keyDown, event: keyDown()))
        XCTAssertFalse(pipeline.handle(type: .keyDown, event: keyDown(autorepeat: true)))
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        XCTAssertFalse(pipeline.handle(type: .keyUp, event: up))
        XCTAssertFalse(pipeline.handle(type: .flagsChanged, event: up))
        front = chatgpt
        pipeline.handle(type: .keyDown, event: keyDown())
        front = nil
        pipeline.handle(type: .keyDown, event: keyDown())

        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.count, 1)
        XCTAssertEqual(counter.todayCounts[chatgpt.bundleID]?.count, 1)
        XCTAssertEqual(counter.todayCounts[AppIdentity.unknown.bundleID]?.count, 1)
        XCTAssertEqual(counter.total, 3)
    }

    func testTypedTextIsCountedButNeverStored() throws {
        let dir = try makeTestDirectory()
        let counter = try KeyCounter(store: CountStore(directory: dir))
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { claude })
        let marker = "ZQXMARKERJV"
        for ch in marker { pipeline.handle(type: .keyDown, event: keyDown(String(ch))) }
        pipeline.handle(type: .keyDown, event: keyDown(marker))  // one event carrying the whole string
        try counter.flush()

        XCTAssertEqual(counter.todayCounts[claude.bundleID]?.count, marker.count + 1)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: Data(marker.utf8)), "typed text found in \(file.lastPathComponent)")
            XCTAssertNil(bytes.range(of: Data(marker.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })),
                         "typed text (UTF-16) found in \(file.lastPathComponent)")
        }
    }
}

final class LaunchOptionsTests: XCTestCase {
    func testParsesTestSeams() throws {
        let o = try LaunchOptions.parse([
            "-NSDocumentRevisionsDebugMode", "YES",
            "--data-dir", "/tmp/x", "--show-window", "--no-tap", "--hold-flush", "--snapshot", "/tmp/s.png",
            "--simulate-keys", "com.apple.TextEdit:5, com.openai.chat:3",
            "--simulate-text", "com.apple.TextEdit:a:b,c",
            "--simulate-clicks", "com.apple.finder:4,com.openai.chat:0", "--simulate-self-clicks", "6",
        ])
        XCTAssertEqual(o.dataDir?.path, "/tmp/x")
        XCTAssertTrue(o.showWindow)
        XCTAssertTrue(o.noTap)
        XCTAssertTrue(o.holdFlush)
        XCTAssertEqual(o.snapshot?.path, "/tmp/s.png")
        XCTAssertFalse(o.dumpCounts)
        XCTAssertEqual(o.simulateKeys.map(\.bundleID), ["com.apple.TextEdit", "com.openai.chat"])
        XCTAssertEqual(o.simulateKeys.map(\.count), [5, 3])
        XCTAssertEqual(o.simulateText?.bundleID, "com.apple.TextEdit")
        XCTAssertEqual(o.simulateText?.text, "a:b,c")
        XCTAssertEqual(o.simulateClicks.map(\.bundleID), ["com.apple.finder", "com.openai.chat"])
        XCTAssertEqual(o.simulateClicks.map(\.count), [4, 0])
        XCTAssertEqual(o.simulateSelfClicks, 6)
        XCTAssertTrue(try LaunchOptions.parse(["--dump-counts"]).dumpCounts)
    }

    func testRejectsBadSpecs() {
        XCTAssertThrowsError(try LaunchOptions.parse(["--simulate-keys", "com.x:abc"]))
        XCTAssertThrowsError(try LaunchOptions.parse(["--simulate-keys", ":3"]))
        XCTAssertThrowsError(try LaunchOptions.parse(["--data-dir"]))
        XCTAssertThrowsError(try LaunchOptions.parse(["--simulate-clicks", "com.x:-1"]))
        XCTAssertThrowsError(try LaunchOptions.parse(["--simulate-self-clicks", "many"]))
    }
}

final class DayKeyTests: XCTestCase {
    func testFormatsLocalDay() {
        let clock = TestClock("2026-01-02 00:30")
        XCTAssertEqual(DayKey.string(for: clock.date, calendar: clock.calendar), "2026-01-02")
    }
}
