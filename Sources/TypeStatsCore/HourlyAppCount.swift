import Foundation

/// A value projection of existing app-hour rows. No new stored fields or tracking.
public struct HourlyAppCount: Equatable, Sendable {
    public let app: AppIdentity
    public var keys: Int
    public var clicks: Int

    public init(app: AppIdentity, keys: Int, clicks: Int = 0) {
        self.app = app
        self.keys = keys
        self.clicks = clicks
    }
}
