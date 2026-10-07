/// The app a key press or click is attributed to. Only identity, never key or click data.
public struct AppIdentity: Hashable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    public static let unknown = AppIdentity(bundleID: "unknown", name: "Unknown")
}

/// One app's key and click counts for a day or a period, with its typing-time totals.
public struct AppCount: Identifiable, Hashable, Sendable {
    public let bundleID: String
    public var name: String
    /// Key presses.
    public var count: Int
    public var clicks: Int
    /// Net characters and seconds in qualifying stretches; historical data keeps its old totals.
    public var burstCount: Int
    public var activeSeconds: Double
    /// True when the app is on the exclusion list: its history is shown, but no more is counted.
    public var excluded = false

    public var id: String { bundleID }

    /// Estimated words per minute, or nil when there is too little typing.
    public var wpm: Double? { TypingSpeed.wpm(burstCount: burstCount, activeSeconds: activeSeconds) }

    public init(bundleID: String, name: String, count: Int, clicks: Int = 0,
                burstCount: Int = 0, activeSeconds: Double = 0) {
        self.bundleID = bundleID
        self.name = name
        self.count = count
        self.clicks = clicks
        self.burstCount = burstCount
        self.activeSeconds = activeSeconds
    }

    /// Adds another row's counts and typing time to this one.
    public mutating func add(_ other: AppCount) {
        count += other.count
        clicks += other.clicks
        burstCount += other.burstCount
        activeSeconds += other.activeSeconds
    }
}

extension Array where Element == AppCount {
    /// Most keys first, then most clicks; ties broken by name, then bundle id,
    /// so order is stable.
    public func rankedByCount() -> [AppCount] {
        sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.clicks != $1.clicks { return $0.clicks > $1.clicks }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.bundleID < $1.bundleID
        }
    }
}
