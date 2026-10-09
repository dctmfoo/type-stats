import Foundation
import Observation

/// Release tags and cask versions use two or three numeric components.
public struct AppVersion: Comparable, Equatable, Sendable {
    public let text: String
    private let parts: [Int]

    public init?(_ text: String) {
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(fields.count),
              fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              fields.allSatisfy({ Int($0) != nil }) else { return nil }
        self.text = text
        parts = fields.map { Int($0)! } + Array(repeating: 0, count: 3 - fields.count)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.parts == rhs.parts }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }

    /// Read the published cask as data. Never execute downloaded Ruby.
    public static func published(in cask: String) -> AppVersion? {
        let pattern = #"(?m)^\s*version\s+"([0-9]+(?:\.[0-9]+){1,2})"\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cask, range: NSRange(cask.startIndex..., in: cask)),
              let range = Range(match.range(at: 1), in: cask) else { return nil }
        return AppVersion(String(cask[range]))
    }
}

@MainActor
public protocol AppUpdateService {
    func latestVersion() async throws -> AppVersion
    func upgrade(to version: AppVersion) async throws
}

/// One state shared by the footer and the App Updates window.
@MainActor @Observable
public final class AppUpdate {
    public let currentVersion: String
    public private(set) var latest: AppVersion?
    public private(set) var isChecking = false
    public private(set) var isUpdating = false
    public private(set) var error: String?
    @ObservationIgnored private let service: any AppUpdateService
    @ObservationIgnored private var lastCheck: Date?

    public init(currentVersion: String, service: any AppUpdateService) {
        self.currentVersion = currentVersion
        self.service = service
    }

    public var updateAvailable: Bool {
        guard let current = AppVersion(currentVersion), let latest else { return false }
        return latest > current
    }

    public var footerLabel: String { updateAvailable ? "Update available" : "Version \(currentVersion)" }
    public var buttonLabel: String { updateAvailable ? "Update from Homebrew" : "Check for Updates" }
    public var status: String {
        if isUpdating { return "Updating with Homebrew. TypeStats will restart when ready." }
        if isChecking { return "Checking for updates…" }
        guard let latest else { return "Check for the latest Homebrew release." }
        guard let current = AppVersion(currentVersion) else { return "Could not read the running app version." }
        if latest > current { return "A new version is available." }
        if latest == current { return "You're using the latest release." }
        return "This version is newer than the Homebrew release."
    }

    public func checkIfNeeded() async {
        guard lastCheck.map({ Date().timeIntervalSince($0) >= 3600 }) ?? true else { return }
        await check()
    }

    public func check() async {
        guard !isChecking && !isUpdating else { return }
        isChecking = true
        error = nil
        defer { isChecking = false }
        do {
            latest = try await service.latestVersion()
            lastCheck = Date()
        } catch {
            self.error = "Could not check for updates: \(error.localizedDescription)"
            // Don't offer an upgrade based on a check that is now known to have failed.
            latest = nil
        }
    }

    public func update() async {
        guard updateAvailable, let latest, !isChecking && !isUpdating else { return }
        isUpdating = true
        error = nil
        defer { isUpdating = false }
        do { try await service.upgrade(to: latest) }
        catch { self.error = "Could not update TypeStats: \(error.localizedDescription)" }
    }
}
