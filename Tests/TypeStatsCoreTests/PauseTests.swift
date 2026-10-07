import CoreGraphics
import Foundation
import XCTest
@testable import TypeStatsCore

@MainActor
final class PauseTests: XCTestCase {
    private func makePause(_ clock: TestClock, directory: URL? = nil) throws -> (PauseControl, URL) {
        let dir = try directory ?? makeTestDirectory()
        return (PauseControl(directory: dir, now: { clock.date }), dir)
    }

    private func keyDown() -> CGEvent { CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)! }
    private func click() -> CGEvent {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
    }

    func testTimedPauseEndsExactlyAtItsEndTime() throws {
        let clock = TestClock("2026-10-05 10:00")
        let (pause, _) = try makePause(clock)
        XCTAssertFalse(pause.isPaused)

        pause.pause(.fifteenMinutes)
        XCTAssertTrue(pause.isPaused)
        clock.set("2026-10-05 10:14")
        XCTAssertTrue(pause.isPaused)
        clock.set("2026-10-05 10:15")
        XCTAssertFalse(pause.isPaused, "the pause ends at its end time")

        clock.set("2026-10-05 11:00")
        pause.pause(.oneHour)
        clock.set("2026-10-05 11:59")
        XCTAssertTrue(pause.isPaused)
        clock.set("2026-10-05 12:00")
        XCTAssertFalse(pause.isPaused)
    }

    func testUntilResumedNeverEndsOnItsOwnAndResumeIsOneCall() throws {
        let clock = TestClock("2026-10-05 10:00")
        let (pause, _) = try makePause(clock)
        pause.pause(.untilResumed)
        clock.set("2027-10-05 10:00")
        XCTAssertTrue(pause.isPaused)
        pause.resume()
        XCTAssertFalse(pause.isPaused)
        XCTAssertNil(pause.state)
    }

    func testNothingIsCountedWhilePausedAndCountingResumesAfter() throws {
        let clock = TestClock("2026-10-05 10:00")
        let (pause, _) = try makePause(clock)
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()),
                                     calendar: clock.calendar, now: { clock.date })
        var lookups = 0
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { terminal },
                                        appAtPoint: { _ in lookups += 1; return claude }, isPaused: { pause.isPaused })

        XCTAssertTrue(pipeline.handle(type: .keyDown, event: keyDown()))
        pause.pause(.fifteenMinutes)
        // Keys and every kind of click, in any app, are ignored.
        XCTAssertFalse(pipeline.handle(type: .keyDown, event: keyDown()))
        XCTAssertFalse(pipeline.handle(type: .keyDown, event: keyDown(), app: chatgpt))
        XCTAssertFalse(pipeline.handle(type: .leftMouseDown, event: click()))
        XCTAssertFalse(pipeline.handle(type: .rightMouseDown, event: click(), app: claude))
        XCTAssertEqual(counter.total, 1)
        XCTAssertEqual(counter.totalClicks, 0)
        XCTAssertEqual(lookups, 0, "a paused click must not even look up the window under the pointer")

        clock.set("2026-10-05 10:15")
        XCTAssertTrue(pipeline.handle(type: .keyDown, event: keyDown()))
        XCTAssertTrue(pipeline.handle(type: .leftMouseDown, event: click(), app: claude))
        XCTAssertEqual(counter.total, 2)
        XCTAssertEqual(counter.totalClicks, 1)

        pause.pause(.untilResumed)
        XCTAssertFalse(pipeline.handle(type: .keyDown, event: keyDown()))
        pause.resume()
        XCTAssertTrue(pipeline.handle(type: .keyDown, event: keyDown()))
        XCTAssertEqual(counter.total, 3)
    }

    func testPausedStateSurvivesRestartUntilItsEndTime() throws {
        let clock = TestClock("2026-10-05 10:00")
        let (first, dir) = try makePause(clock)
        first.pause(.oneHour)

        clock.set("2026-10-05 10:30")
        let (restarted, _) = try makePause(clock, directory: dir)
        XCTAssertTrue(restarted.isPaused, "a restart inside the pause stays paused")
        XCTAssertEqual(restarted.state, first.state)

        clock.set("2026-10-05 11:00")
        let (late, _) = try makePause(clock, directory: dir)
        XCTAssertFalse(late.isPaused, "a restart after the end time is not paused")
        XCTAssertNil(late.state)

        let (until, dir2) = try makePause(clock)
        until.pause(.untilResumed)
        clock.set("2026-12-31 10:00")
        let (stillPaused, _) = try makePause(clock, directory: dir2)
        XCTAssertTrue(stillPaused.isPaused, "until resumed survives any number of restarts")
        stillPaused.resume()
        let (resumed, _) = try makePause(clock, directory: dir2)
        XCTAssertFalse(resumed.isPaused, "resuming is remembered across a restart")
    }

    func testRefreshClearsAnExpiredPauseSoTheUICanUpdate() throws {
        let clock = TestClock("2026-10-05 10:00")
        let (pause, _) = try makePause(clock)
        pause.pause(.fifteenMinutes)
        clock.set("2026-10-05 10:20")
        XCTAssertNotNil(pause.state)
        pause.refresh()
        XCTAssertNil(pause.state)
        XCTAssertEqual(pause.menuBarSymbol, PauseControl.runningSymbol)
    }

    func testStoredFileHoldsOnlyTheEndTime() throws {
        let clock = TestClock("2026-10-05 10:00")
        let (pause, dir) = try makePause(clock)
        pause.pause(.fifteenMinutes)
        let text = try String(contentsOf: dir.appendingPathComponent(PauseControl.fileName), encoding: .utf8)
        XCTAssertTrue(text.contains("until"))
        XCTAssertFalse(text.contains("bundle"), "no app, key or text information in the pause file")
        pause.resume()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(PauseControl.fileName).path))
    }

    func testAnUnreadableFileMeansNotPaused() throws {
        let clock = TestClock("2026-10-05 10:00")
        let dir = try makeTestDirectory()
        try Data("{not json".utf8).write(to: dir.appendingPathComponent(PauseControl.fileName))
        let (pause, _) = try makePause(clock, directory: dir)
        XCTAssertFalse(pause.isPaused)
    }

    func testMenuBarSymbolAndStatusTextShowPausedStateAndResumeTime() throws {
        let clock = TestClock("2026-10-05 10:00")
        let (pause, _) = try makePause(clock)
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(pause.menuBarSymbol, "keyboard")
        XCTAssertNil(pause.statusText(calendar: clock.calendar, locale: us))

        pause.pause(.fifteenMinutes)
        XCTAssertEqual(pause.menuBarSymbol, "pause.circle.fill")
        let same = try XCTUnwrap(pause.statusText(calendar: clock.calendar, locale: us))
        XCTAssertTrue(same.hasPrefix("Paused until 10:15"), same)
        XCTAssertTrue(same.contains("AM"), same)

        // A pause that crosses midnight names the day.
        clock.set("2026-10-05 23:50")
        pause.pause(.oneHour)
        let next = try XCTUnwrap(pause.statusText(calendar: clock.calendar, locale: us))
        XCTAssertTrue(next.contains("Tue") && next.contains("12:50"), next)

        pause.pause(.untilResumed)
        XCTAssertEqual(pause.statusText(calendar: clock.calendar, locale: us), "Paused until you resume")
    }

    func testChoicesAndLaunchOptions() throws {
        XCTAssertEqual(PauseChoice.allCases.map(\.title), ["15 minutes", "1 hour", "Until I resume"])
        XCTAssertEqual(try LaunchOptions.parse(["--pause", "15m"]).pause, .fifteenMinutes)
        XCTAssertEqual(try LaunchOptions.parse(["--pause", "1h"]).pause, .oneHour)
        XCTAssertEqual(try LaunchOptions.parse(["--pause", "until-resumed"]).pause, .untilResumed)
        XCTAssertTrue(try LaunchOptions.parse(["--resume"]).resume)
        XCTAssertTrue(try LaunchOptions.parse(["--dump-pause"]).dumpPause)
        XCTAssertThrowsError(try LaunchOptions.parse(["--pause", "5m"]))
    }
}
