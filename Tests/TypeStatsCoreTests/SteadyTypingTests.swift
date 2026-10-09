import CoreGraphics
import XCTest
@testable import TypeStatsCore

@MainActor
final class SteadyTypingTests: XCTestCase {
    func testShortReplyDoesNotProduceSpeed() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { terminal })
        let base = EventClock.nowNanos()
        for i in 0..<20 {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
            event.flags = []
            event.timestamp = base + UInt64(i) * 500_000_000
            pipeline.handle(type: .keyDown, event: event)
        }
        XCTAssertNil(counter.wpm, "9.5-second reply must not produce WPM")
        XCTAssertEqual(counter.total, 20)
    }
}

extension SteadyTypingTests {
    private func event(_ code: CGKeyCode, flags: CGEventFlags = [], at nanoseconds: UInt64 = 0) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        event.flags = flags
        event.timestamp = nanoseconds
        return event
    }

    func testClassifierUsesOnlyCoarseKinds() {
        for code: CGKeyCode in [0, 8, 18, 24, 36, 49, 50, 65, 76, 82, 93, 94, 95] {
            XCTAssertEqual(KeyPressPipeline.kind(of: event(code)), .typingCharacter)
            XCTAssertEqual(KeyPressPipeline.kind(of: event(code, flags: [.maskShift, .maskAlternate])), .typingCharacter)
            for flags: CGEventFlags in [.maskCommand, .maskControl, [.maskCommand, .maskShift]] {
                XCTAssertEqual(KeyPressPipeline.kind(of: event(code, flags: flags)), .other)
            }
        }
        for code: CGKeyCode in [51, 117] {
            XCTAssertEqual(KeyPressPipeline.kind(of: event(code)), .backspace)
            XCTAssertEqual(KeyPressPipeline.kind(of: event(code, flags: .maskCommand)), .other)
        }
        for code: CGKeyCode in [48, 53, 71, 90, 96, 102, 104, 115, 116, 123, 124, 125, 126, 65535] {
            XCTAssertEqual(KeyPressPipeline.kind(of: event(code)), .other)
        }
    }

    func testThresholdIsPerStretchAndGapIsStrictlyUnderTwoSeconds() {
        var stretch = TypingStretch()
        for i in 0..<10 {
            XCTAssertEqual(stretch.press(.typingCharacter, at: Double(i)).characters, 0)
        }
        let qualified = stretch.press(.typingCharacter, at: 10)
        XCTAssertEqual(qualified.characters, 11)
        XCTAssertEqual(qualified.seconds, 10)
        XCTAssertEqual(stretch.press(.typingCharacter, at: 11.999).characters, 1)
        XCTAssertEqual(stretch.press(.typingCharacter, at: 13.999).characters, 0, "exactly 2 seconds starts fresh")
        XCTAssertEqual(stretch.press(.typingCharacter, at: 13.999).seconds, 0)
        XCTAssertEqual(stretch.press(.typingCharacter, at: 13).seconds, 0)
        XCTAssertEqual(stretch.press(.other, at: 14).characters, 0)
        // Many short stretches never combine to qualify.
        for base in stride(from: 20.0, to: 100, by: 20) {
            for i in 0..<10 { XCTAssertEqual(stretch.press(.typingCharacter, at: base + Double(i)).seconds, 0) }
        }
    }

    func testCorrectionsSubtractAfterFlushAndFloorWithinTheirStretch() throws {
        let directory = try makeTestDirectory()
        let counter = try KeyCounter(store: CountStore(directory: directory))
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { terminal })
        // Whole seconds keep the exact 10-second qualification boundary representable.
        let base = (EventClock.nowNanos() / 1_000_000_000 + 1) * 1_000_000_000
        for i in 0...10 { pipeline.handle(type: .keyDown, event: event(0, at: base + UInt64(i) * 1_000_000_000)) }
        try counter.flush()
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.burstCount, 11)
        for i in 1...15 { pipeline.handle(type: .keyDown, event: event(i % 2 == 0 ? 117 : 51, at: base + 10_000_000_000 + UInt64(i) * 100_000_000)) }
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.burstCount, 0)
        XCTAssertEqual(counter.wpm, 0)
        try counter.flush()
        let reopened = try KeyCounter(store: CountStore(directory: directory))
        XCTAssertEqual(reopened.total, 26)
        XCTAssertEqual(reopened.todayCounts[terminal.bundleID]?.burstCount, 0)
        XCTAssertEqual(reopened.todayCounts[terminal.bundleID]?.activeSeconds ?? 0, 11.5, accuracy: 0.0001)
        // Deletes in a fresh stretch cannot erase already-qualified earlier writing.
        let baseSeconds = Double(base) / 1e9
        for i in 0...10 { counter.record(terminal, kind: .typingCharacter, at: baseSeconds + 100 + Double(i)) }
        counter.record(terminal, kind: .backspace, at: baseSeconds + 200)
        XCTAssertEqual(counter.todayCounts[terminal.bundleID]?.burstCount, 11)
    }

    func testShortcutsAndNavigationKeepKeyCountButBreakSpeed() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { terminal })
        let base = EventClock.nowNanos()
        for i in 0..<30 {
            let code: CGKeyCode = i % 5 == 4 ? 123 : 0
            pipeline.handle(type: .keyDown, event: event(code, at: base + UInt64(i) * 1_000_000_000))
        }
        for i in 30..<50 { pipeline.handle(type: .keyDown, event: event(8, flags: .maskCommand, at: base + UInt64(i) * 1_000_000_000)) }
        XCTAssertEqual(counter.total, 50)
        XCTAssertNil(counter.wpm)
    }

    func testAppAndDayChangesBreakContinuity() throws {
        let clock = TestClock("2026-10-06 23:59")
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()), calendar: clock.calendar, now: { clock.date })
        for i in 0..<20 { counter.record(i % 2 == 0 ? terminal : claude, kind: .typingCharacter, at: Double(i)) }
        XCTAssertNil(counter.wpm)
        for i in 0..<10 { counter.record(terminal, kind: .typingCharacter, at: 100 + Double(i)) }
        clock.set("2026-10-07 00:01")
        counter.record(terminal, kind: .typingCharacter, at: 110)
        XCTAssertNil(counter.wpm)
        XCTAssertEqual(counter.total, 1)
    }

    func testPauseAndUnknownTimeBreakContinuity() throws {
        let counter = try KeyCounter(store: CountStore(directory: makeTestDirectory()))
        var paused = false
        let pipeline = KeyPressPipeline(counter: counter, frontmostApp: { terminal }, isPaused: { paused })
        for i in 0..<10 { pipeline.handle(type: .keyDown, time: Double(i), kind: .typingCharacter) }
        paused = true
        XCTAssertFalse(pipeline.handle(type: .keyDown, time: 9.1, kind: .typingCharacter))
        paused = false
        pipeline.handle(type: .keyDown, time: 10, kind: .typingCharacter)
        XCTAssertNil(counter.wpm)
        counter.record(terminal, kind: .typingCharacter)
        counter.record(terminal, kind: .typingCharacter, at: 11)
        XCTAssertNil(counter.wpm)
    }
}
