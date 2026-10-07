import Darwin
import Foundation

/// The only key information allowed past the event boundary. No key identity or text.
public enum TypingKeyKind: Sendable {
    case typingCharacter, backspace, other
}

/// A steady stretch contributes only after it reaches the minimum duration.
/// Returns differences from its already-contributed totals, including corrections.
public struct TypingStretch: Sendable {
    public static let maxGap: TimeInterval = 2
    public static let minimumSeconds: TimeInterval = 10

    private var start: TimeInterval?
    private var last: TimeInterval?
    private var netCharacters = 0
    private var contributedCharacters = 0
    private var contributedSeconds = 0.0

    public init() {}

    public mutating func press(_ kind: TypingKeyKind, at time: TimeInterval?) -> (characters: Int, seconds: Double) {
        guard kind != .other, let time, time.isFinite else {
            self = Self()
            return (0, 0)
        }
        if let last, time <= last || time - last >= Self.maxGap { self = Self() }
        // A correction can continue writing, but cannot start a typing stretch.
        if start == nil {
            guard kind == .typingCharacter else { return (0, 0) }
            start = time
        }
        last = time
        switch kind {
        case .typingCharacter: netCharacters += 1
        case .backspace: netCharacters = max(0, netCharacters - 1)
        case .other: break
        }
        let duration = time - start!
        guard duration >= Self.minimumSeconds else { return (0, 0) }
        let delta = (netCharacters - contributedCharacters, duration - contributedSeconds)
        contributedCharacters = netCharacters
        contributedSeconds = duration
        return delta
    }
}

public enum TypingSpeed {
    /// Retained for old stored estimates. New stretches qualify at 10 seconds.
    public static let minimumSeconds: TimeInterval = 5
    public static let charactersPerWord: Double = 5

    /// Stored numerator is net characters in qualifying stretches for new data.
    /// Historical rows retain their original burst-press numerator.
    public static func wpm(burstCount: Int, activeSeconds: TimeInterval) -> Double? {
        guard activeSeconds >= minimumSeconds, burstCount >= 0 else { return nil }
        return (Double(burstCount) / charactersPerWord) / (activeSeconds / 60)
    }
}

/// Converts a CGEvent timestamp to seconds since boot. Apple documents nanoseconds, but
/// some Macs deliver mach absolute time ticks, so the unit is chosen by which clock
/// the timestamp is closer to right now.
public enum EventClock {
    public struct Timebase: Sendable { public let numer: UInt64; public let denom: UInt64 }

    public static let machTimebase: Timebase = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Timebase(numer: UInt64(info.numer), denom: UInt64(max(info.denom, 1)))
    }()

    /// Nil when the event has no timestamp (0), as synthetic events do.
    public static func seconds(fromEventTimestamp ts: UInt64,
                               nowNanos: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW),
                               nowTicks: UInt64 = mach_absolute_time(),
                               timebase: Timebase = machTimebase) -> TimeInterval? {
        guard ts > 0 else { return nil }
        let nanos = distance(ts, nowNanos) <= distance(ts, nowTicks) ? ts : ts * timebase.numer / timebase.denom
        return TimeInterval(nanos) / 1_000_000_000
    }

    /// The current time in the nanosecond unit, for synthetic event timestamps.
    public static func nowNanos() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

    private static func distance(_ a: UInt64, _ b: UInt64) -> UInt64 { a > b ? a - b : b - a }
}
