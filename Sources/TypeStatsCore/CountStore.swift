import Foundation
import SwiftData

/// SwiftData store of per-app counts by day (and, from task 03 on, by hour) in a
/// chosen directory.
@MainActor
public final class CountStore {
    public static let fileName = "TypeStats.store"

    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: directory.appendingPathComponent(Self.fileName))
        container = try ModelContainer(for: AppDayCount.self, AppHourCount.self, ExcludedApp.self, configurations: config)
        container.mainContext.autosaveEnabled = false
    }

    /// Default location: ~/Library/Application Support/TypeStats/
    public static func defaultDirectory() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("TypeStats", isDirectory: true)
    }

    /// Adds key presses, clicks and typing time to an app's counts for `day`, and the
    /// presses and clicks to its row for `hour` when given. Call `save()` afterwards.
    public func add(day: String, hour: Int? = nil, app: AppIdentity, keys: Int, clicks: Int = 0,
                    burstCount: Int = 0, activeSeconds: Double = 0) throws {
        let bundleID = app.bundleID
        var fetch = FetchDescriptor<AppDayCount>(
            predicate: #Predicate { $0.day == day && $0.bundleID == bundleID })
        fetch.fetchLimit = 1
        if let row = try context.fetch(fetch).first {
            row.count += keys
            row.clicks += clicks
            row.burstCount += burstCount
            row.activeSeconds += activeSeconds
            row.appName = app.name
        } else {
            context.insert(AppDayCount(day: day, bundleID: bundleID, appName: app.name, count: keys, clicks: clicks,
                                       burstCount: burstCount, activeSeconds: activeSeconds))
        }
        guard let hour, keys > 0 || clicks > 0 else { return }
        var hourFetch = FetchDescriptor<AppHourCount>(
            predicate: #Predicate { $0.day == day && $0.hour == hour && $0.bundleID == bundleID })
        hourFetch.fetchLimit = 1
        if let row = try context.fetch(hourFetch).first {
            row.count += keys
            row.clicks += clicks
        } else {
            context.insert(AppHourCount(day: day, hour: hour, bundleID: bundleID, count: keys, clicks: clicks))
        }
    }

    /// The apps excluded from counting, by name.
    public func excludedApps() throws -> [AppIdentity] {
        try context.fetch(FetchDescriptor<ExcludedApp>())
            .map { AppIdentity(bundleID: $0.bundleID, name: $0.appName) }
            .sorted { ($0.name, $0.bundleID) < ($1.name, $1.bundleID) }
    }

    /// Adds an app to the exclusion list (or refreshes its name) and saves at once.
    public func exclude(_ app: AppIdentity) throws {
        let bundleID = app.bundleID
        var fetch = FetchDescriptor<ExcludedApp>(predicate: #Predicate { $0.bundleID == bundleID })
        fetch.fetchLimit = 1
        if let row = try context.fetch(fetch).first {
            row.appName = app.name
        } else {
            context.insert(ExcludedApp(bundleID: bundleID, appName: app.name))
        }
        try save()
    }

    /// Removes an app from the exclusion list and saves at once.
    public func include(bundleID: String) throws {
        for row in try context.fetch(FetchDescriptor<ExcludedApp>(predicate: #Predicate { $0.bundleID == bundleID })) {
            context.delete(row)
        }
        try save()
    }

    public func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func counts(day: String) throws -> [AppCount] {
        let fetch = FetchDescriptor<AppDayCount>(predicate: #Predicate { $0.day == day })
        return try context.fetch(fetch).map(Self.appCount).rankedByCount()
    }

    /// Every app's row for each of `days`.
    public func counts(days: [String]) throws -> [(day: String, app: AppCount)] {
        let fetch = FetchDescriptor<AppDayCount>(predicate: #Predicate { days.contains($0.day) })
        return try context.fetch(fetch).map { ($0.day, Self.appCount($0)) }
    }

    /// Keys and clicks per hour of `day` across all apps, only hours with a row.
    public func hours(day: String) throws -> [Int: HourCount] {
        let fetch = FetchDescriptor<AppHourCount>(predicate: #Predicate { $0.day == day })
        var hours: [Int: HourCount] = [:]
        for row in try context.fetch(fetch) {
            hours[row.hour, default: HourCount(hour: row.hour)].keys += row.count
            hours[row.hour, default: HourCount(hour: row.hour)].clicks += row.clicks
        }
        return hours
    }

    private static func appCount(_ row: AppDayCount) -> AppCount {
        AppCount(bundleID: row.bundleID, name: row.appName, count: row.count, clicks: row.clicks,
                 burstCount: row.burstCount, activeSeconds: row.activeSeconds)
    }
}
