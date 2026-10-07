import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import TypeStatsCore

@MainActor
final class ClickCounterTests: XCTestCase {
    func testEachClickAddsExactlyOneClickAndNoKeys() throws {
        let store = try CountStore(directory: makeTestDirectory())
        let counter = try KeyCounter(store: store)
        for _ in 0..<2 { counter.record(terminal) }
        for _ in 0..<3 { counter.recordClick(terminal) }
        counter.recordClick(chatgpt)

        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.count, 2, "clicks must not add keys")
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.clicks, 3)
        XCTAssertEqual(counter.todayCounts[chatgpt.bundleID]?.count, 0)
        XCTAssertEqual(counter.todayCounts[chatgpt.bundleID]?.clicks, 1)
        XCTAssertEqual(counter.total, 2)
        XCTAssertEqual(counter.totalClicks, 4)

        try counter.flush()
        XCTAssertEqual(counter.pendingCount, 0)
        let stored = try store.counts(day: counter.day)
        XCTAssertEqual(stored.map(\.bundleID), [terminal.bundleID, chatgpt.bundleID])
        XCTAssertEqual(stored.map(\.count), [2, 0])
        XCTAssertEqual(stored.map(\.clicks), [3, 1])

        // A second batch adds to the stored row instead of replacing it.
        counter.recordClick(chatgpt)
        try counter.flush()
        XCTAssertEqual(try store.counts(day: counter.day).first { $0.bundleID == chatgpt.bundleID }?.clicks, 2)
    }

    func testClicksPersistAcrossStoreReopenAndAreBucketedByDay() throws {
        let dir = try makeTestDirectory()
        let clock = TestClock("2026-10-04 23:59")
        do {
            let counter = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
            for _ in 0..<5 { counter.recordClick(claude) }
            counter.record(claude)
            try counter.flush()
        }
        let reopened = try KeyCounter(store: CountStore(directory: dir), calendar: clock.calendar, now: { clock.date })
        XCTAssertEqual(reopened.todayCounts[claude.bundleID]?.clicks, 5)
        XCTAssertEqual(reopened.todayCounts[claude.bundleID]?.count, 1)
        clock.set("2026-10-05 00:01")
        reopened.recordClick(claude)
        XCTAssertEqual(reopened.totalClicks, 1, "today starts fresh after midnight")
        try reopened.flush()

        let store = try CountStore(directory: dir)
        XCTAssertEqual(try store.counts(day: "2026-10-04").first?.clicks, 5)
        XCTAssertEqual(try store.counts(day: "2026-10-05").first?.clicks, 1)
        XCTAssertEqual(try store.counts(day: "2026-10-05").first?.count, 0)
    }
}

@MainActor
final class ClickPipelineTests: XCTestCase {
    private func mouse(_ type: CGEventType, at point: CGPoint = .zero, button: CGMouseButton = .left) -> CGEvent {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)!
    }

    func testCountsEveryMouseDownOnceAndNothingElse() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { terminal })

        XCTAssertTrue(pipeline.handle(type: .leftMouseDown, event: mouse(.leftMouseDown)))
        XCTAssertTrue(pipeline.handle(type: .rightMouseDown, event: mouse(.rightMouseDown, button: .right)))
        XCTAssertTrue(pipeline.handle(type: .otherMouseDown, event: mouse(.otherMouseDown, button: .center)))
        for type: CGEventType in [.leftMouseUp, .rightMouseUp, .otherMouseUp, .leftMouseDragged,
                                  .rightMouseDragged, .otherMouseDragged, .mouseMoved, .scrollWheel] {
            let e = CGEvent(source: nil)!
            e.type = type
            XCTAssertFalse(pipeline.handle(type: type, event: e), "\(type.rawValue) must not count")
        }

        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.clicks, 3)
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.count, 0, "clicks must not count as keys")
        XCTAssertEqual(counter.totalClicks, 3)
        XCTAssertEqual(counter.total, 0)
    }

    func testClickGoesToAppUnderPointerElseFrontmost() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        var front: AppIdentity? = terminal
        var looked: [CGPoint] = []
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { front }) { point in
            looked.append(point)
            return point.x < 100 ? claude : nil  // claude's window covers x < 100
        }

        pipeline.handle(type: .leftMouseDown, event: mouse(.leftMouseDown, at: CGPoint(x: 40, y: 300)))
        pipeline.handle(type: .rightMouseDown, event: mouse(.rightMouseDown, at: CGPoint(x: 60, y: 10), button: .right))
        pipeline.handle(type: .leftMouseDown, event: mouse(.leftMouseDown, at: CGPoint(x: 500, y: 300)))
        front = nil
        pipeline.handle(type: .leftMouseDown, event: mouse(.leftMouseDown, at: CGPoint(x: 900, y: 300)))
        // Key presses still go to the frontmost app, never the app under the pointer.
        front = chatgpt
        pipeline.handle(type: .keyDown, event: CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!)

        XCTAssertEqual(looked, [CGPoint(x: 40, y: 300), CGPoint(x: 60, y: 10), CGPoint(x: 500, y: 300), CGPoint(x: 900, y: 300)])
        XCTAssertEqual(counter.todayCounts[claude.bundleID]?.clicks, 2, "app under the pointer gets the click")
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.clicks, 1, "no window found: frontmost app")
        XCTAssertEqual(counter.todayCounts[AppIdentity.unknown.bundleID]?.clicks, 1)
        XCTAssertEqual(counter.todayCounts[chatgpt.bundleID]?.count, 1)
        XCTAssertEqual(counter.todayCounts[claude.bundleID]?.count, 0)
    }
}

final class WindowHitTestTests: XCTestCase {
    private let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
    private let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))

    func testTopmostVisibleNormalWindowUnderPointWins() {
        // Front-to-back, shaped like this Mac's real list: an overlay, the menu bar,
        // the Dock's invisible full-screen window, then app windows.
        let windows = [
            WindowHitTest.Window(pid: 9, layer: 1000, bounds: CGRect(x: 1900, y: 100, width: 500, height: 1100)),
            WindowHitTest.Window(pid: 1, layer: menuBarLayer, bounds: CGRect(x: 0, y: 0, width: 2560, height: 30)),
            WindowHitTest.Window(pid: 2, layer: dockLayer, bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440)),
            WindowHitTest.Window(pid: 3, layer: 3, bounds: CGRect(x: 100, y: 100, width: 200, height: 200)),  // floating panel
            WindowHitTest.Window(pid: 4, layer: 0, bounds: CGRect(x: 0, y: 30, width: 1200, height: 900), alpha: 0),
            WindowHitTest.Window(pid: 5, layer: 0, bounds: CGRect(x: 0, y: 30, width: 1200, height: 900)),
            WindowHitTest.Window(pid: 6, layer: 0, bounds: CGRect(x: 0, y: 30, width: 2560, height: 1410)),
        ]
        XCTAssertEqual(WindowHitTest.ownerPID(at: CGPoint(x: 150, y: 150), windows: windows), 3)
        XCTAssertEqual(WindowHitTest.ownerPID(at: CGPoint(x: 600, y: 500), windows: windows), 5)
        XCTAssertEqual(WindowHitTest.ownerPID(at: CGPoint(x: 2000, y: 500), windows: windows), 6)
        XCTAssertNil(WindowHitTest.ownerPID(at: CGPoint(x: 600, y: 10), windows: windows), "menu bar: frontmost fallback")
        XCTAssertNil(WindowHitTest.ownerPID(at: CGPoint(x: 600, y: 500), windows: []))
    }

    func testParsesWindowListEntry() {
        let info: [String: Any] = [
            kCGWindowOwnerPID as String: Int32(42), kCGWindowLayer as String: 0, kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: CGRect(x: 10, y: 20, width: 30, height: 40).dictionaryRepresentation,
        ]
        let w = WindowHitTest.Window(info: info)
        XCTAssertEqual(w?.pid, 42)
        XCTAssertEqual(w?.bounds, CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertNil(WindowHitTest.Window(info: [:]))
    }
}

/// The schema task 01 shipped (keys only), as the owner's store was written.
enum TaskOneSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [AppDayCount.self] }

    @Model
    final class AppDayCount {
        var day: String
        var bundleID: String
        var appName: String
        var count: Int

        init(day: String, bundleID: String, appName: String, count: Int) {
            self.day = day
            self.bundleID = bundleID
            self.appName = appName
            self.count = count
        }
    }
}

@MainActor
final class StoreUpgradeTests: XCTestCase {
    func testTaskOneStoreKeepsKeyCountsAndStartsClicksAtZero() throws {
        let dir = try makeTestDirectory()
        do {
            let config = ModelConfiguration(url: dir.appendingPathComponent(CountStore.fileName))
            let old = try ModelContainer(for: Schema(versionedSchema: TaskOneSchema.self), configurations: config)
            let context = ModelContext(old)
            context.insert(TaskOneSchema.AppDayCount(day: "2026-10-04", bundleID: terminal.bundleID, appName: "Terminal", count: 1240))
            context.insert(TaskOneSchema.AppDayCount(day: "2026-10-04", bundleID: claude.bundleID, appName: "Claude", count: 860))
            context.insert(TaskOneSchema.AppDayCount(day: "2026-10-03", bundleID: terminal.bundleID, appName: "Terminal", count: 77))
            try context.save()
        }

        let store = try CountStore(directory: dir)
        let today = try store.counts(day: "2026-10-04")
        XCTAssertEqual(today.map(\.bundleID), [terminal.bundleID, claude.bundleID])
        XCTAssertEqual(today.map(\.count), [1240, 860], "key counts survive the upgrade unchanged")
        XCTAssertEqual(today.map(\.clicks), [0, 0], "clicks start at 0")
        XCTAssertEqual(try store.counts(day: "2026-10-03").map(\.count), [77])

        // The upgraded store takes clicks and keeps them across a reopen.
        try store.add(day: "2026-10-04", app: claude, keys: 0, clicks: 3)
        try store.save()
        let reopened = try CountStore(directory: dir)
        let after = try reopened.counts(day: "2026-10-04")
        XCTAssertEqual(after.map(\.count), [1240, 860])
        XCTAssertEqual(after.map(\.clicks), [0, 3])
    }
}
