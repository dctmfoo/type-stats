import Foundation
import SwiftData

/// How many keys were pressed and how many mouse clicks were made in an app on a day,
/// plus typing-time totals for the speed estimate. There is deliberately no field for
/// key codes, characters, text or click positions.
@Model
public final class AppDayCount {
    public var day: String
    public var bundleID: String
    public var appName: String
    /// Key presses.
    public var count: Int
    /// Mouse clicks. The default lets SwiftData migrate a task-01 store (keys only)
    /// in place: existing rows keep their key counts and start at 0 clicks.
    public var clicks: Int = 0
    /// Net characters in qualifying steady stretches from 2026-10-07 onward.
    /// Historical rows keep their burst-press totals; the field name stays for store compatibility.
    public var burstCount: Int = 0
    /// Duration of qualifying stretches. Historical rows retain their active-gap totals.
    public var activeSeconds: Double = 0

    public init(day: String, bundleID: String, appName: String, count: Int, clicks: Int = 0,
                burstCount: Int = 0, activeSeconds: Double = 0) {
        self.day = day
        self.bundleID = bundleID
        self.appName = appName
        self.count = count
        self.clicks = clicks
        self.burstCount = burstCount
        self.activeSeconds = activeSeconds
    }
}

/// Key presses and clicks in an app during one local hour of a day (hour 0...23).
/// Only kept from task 03 on; earlier days have daily rows only.
@Model
public final class AppHourCount {
    public var day: String
    public var hour: Int
    public var bundleID: String
    /// Key presses.
    public var count: Int
    public var clicks: Int

    public init(day: String, hour: Int, bundleID: String, count: Int, clicks: Int) {
        self.day = day
        self.hour = hour
        self.bundleID = bundleID
        self.count = count
        self.clicks = clicks
    }
}
