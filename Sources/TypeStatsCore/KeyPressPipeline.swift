import CoreGraphics
import Foundation

/// The single path from an event tap or a test seam to the counter. Key identity is
/// read only to classify into a coarse kind, then discarded. Text is never read.
/// Click locations are used once to find the app and never stored.
@MainActor
public final class KeyPressPipeline {
    public let counter: KeyCounter
    private let frontmostApp: () -> AppIdentity?
    private let appAtPoint: (CGPoint) -> AppIdentity?
    private let isPaused: () -> Bool

    /// Mouse-down events that count as one click each. Mouse up, drag, move and
    /// scroll are never counted.
    public nonisolated static let clickTypes: Set<CGEventType> = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    public init(counter: KeyCounter, frontmostApp: @escaping () -> AppIdentity?,
                appAtPoint: @escaping (CGPoint) -> AppIdentity? = { _ in nil },
                isPaused: @escaping () -> Bool = { false }) {
        self.counter = counter
        self.frontmostApp = frontmostApp
        self.appAtPoint = appAtPoint
        self.isPaused = isPaused
    }

    /// Returns true when the event was counted (not for autorepeat, other events, an excluded app or while counting is paused).
    /// Autorepeat (holding a key down) is ignored: one physical press counts once.
    @discardableResult
    public func handle(type: CGEventType, event: CGEvent, app override: AppIdentity? = nil) -> Bool {
        handle(type: type, isAutorepeat: type == .keyDown && Self.isAutorepeat(event),
               location: Self.clickTypes.contains(type) ? event.location : nil,
               time: type == .keyDown ? Self.time(of: event) : nil,
               kind: type == .keyDown ? Self.kind(of: event) : .other, app: override)
    }

    /// Key presses go to the frontmost app. Clicks go to the app under `location`,
    /// falling back to the frontmost app. `time` is a key press's event time in seconds
    /// (nil when unknown); it only feeds the typing speed estimate.
    @discardableResult
    public func handle(type: CGEventType, isAutorepeat: Bool = false, location: CGPoint? = nil,
                       time: TimeInterval? = nil, kind: TypingKeyKind = .other, app override: AppIdentity? = nil) -> Bool {
        // Paused: nothing is counted for any app, and no window lookup happens for a click.
        guard !isPaused() else { counter.endTypingStretch(); return false }
        if type == .keyDown {
            guard !isAutorepeat else { return false }
            return counter.record(override ?? frontmostApp() ?? .unknown, kind: kind, at: time)
        }
        guard Self.clickTypes.contains(type) else { return false }
        return counter.recordClick(override ?? location.flatMap(appAtPoint) ?? frontmostApp() ?? .unknown)
    }

    /// Classify physical typing keys without reading Unicode or retaining key codes.
    /// Key positions come from the macOS SDK HIToolbox Events.h virtual-key constants.
    public nonisolated static func kind(of event: CGEvent) -> TypingKeyKind {
        guard event.flags.intersection([.maskCommand, .maskControl]).isEmpty else { return .other }
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 51, 117: return .backspace // Delete and Forward Delete
        // Letters, digits, punctuation, ISO Section, Return, Space and Grave.
        case 0...47, 49, 50: return .typingCharacter
        // Keypad punctuation, operators, Enter and digits, plus JIS punctuation.
        case 65, 67, 69, 75, 76, 78, 81...89, 91...95: return .typingCharacter
        default: return .other
        }
    }

    /// The event's time in seconds since boot, or nil when it has none.
    public nonisolated static func time(of event: CGEvent) -> TimeInterval? {
        EventClock.seconds(fromEventTimestamp: event.timestamp)
    }

    public nonisolated static func isAutorepeat(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    }
}
