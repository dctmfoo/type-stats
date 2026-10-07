import Foundation
import Observation

/// How long a pause lasts: the three choices in the popup's Pause menu.
public enum PauseChoice: String, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes, oneHour, untilResumed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .untilResumed: "Until I resume"
        }
    }

    /// Seconds the pause lasts, or nil when it lasts until resumed.
    public var duration: TimeInterval? {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .oneHour: 60 * 60
        case .untilResumed: nil
        }
    }
}

/// An active pause: when it ends, or nil when it lasts until the person resumes.
/// This is all that is stored; it holds no counts, apps, keys or text.
public struct PauseState: Codable, Equatable, Sendable {
    public var until: Date?
}

/// Pauses counting. While paused, the key press pipeline ignores every key press and
/// click for every app. The pause is saved in the data folder, so it survives a restart
/// until its end time (or for good, when it lasts until resumed).
@MainActor
@Observable
public final class PauseControl {
    public static let fileName = "pause.json"
    public static let runningSymbol = "keyboard"
    public static let pausedSymbol = "pause.circle.fill"

    /// The saved pause, if any. It can be past its end time until `refresh()` clears it
    /// (the app calls that every few seconds), so the popup and menu bar icon follow it.
    public private(set) var state: PauseState?

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let now: () -> Date

    public init(directory: URL, now: @escaping () -> Date = Date.init) {
        fileURL = directory.appendingPathComponent(Self.fileName)
        self.now = now
        state = Self.load(fileURL)
        // A pause that ended while the app was closed is dropped (the old file is left alone).
        if !isPaused { state = nil }
    }

    /// True while counting is paused. Checked against the clock on every event, so counting
    /// resumes exactly at the end time even before `refresh()` has run.
    public var isPaused: Bool {
        guard let state else { return false }
        guard let until = state.until else { return true }
        return now() < until
    }

    public func pause(_ choice: PauseChoice) {
        state = PauseState(until: choice.duration.map { now().addingTimeInterval($0) })
        save()
    }

    public func resume() {
        state = nil
        save()
    }

    /// Forgets a pause whose end time has passed.
    public func refresh() {
        if state != nil, !isPaused { resume() }
    }

    /// The menu bar icon: a keyboard while counting, a pause sign while paused.
    public var menuBarSymbol: String { state == nil ? Self.runningSymbol : Self.pausedSymbol }

    /// "Paused until 10:15 AM" (with the weekday when that is not today) or
    /// "Paused until you resume"; nil when not paused.
    public func statusText(calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let state else { return nil }
        guard let until = state.until else { return "Paused until you resume" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(until, inSameDayAs: now()) ? "jmm" : "EEEjmm")
        return "Paused until \(formatter.string(from: until))"
    }

    /// Test seams `--pause` and `--resume`: what a click on the popup's menu does.
    public func apply(pause choice: PauseChoice?, resume: Bool) {
        if resume { self.resume() }
        if let choice { pause(choice) }
    }

    private func save() {
        do {
            if let state {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            FileHandle.standardError.write(Data("TypeStats: cannot save pause state: \(error)\n".utf8))
        }
    }

    /// A missing or unreadable file means not paused.
    private static func load(_ url: URL) -> PauseState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PauseState.self, from: data)
    }
}
