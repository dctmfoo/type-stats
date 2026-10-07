import Foundation
import SwiftData

/// An app the owner excluded from counting (for example a password manager). Identity
/// only: the bundle id and the name to show. Its earlier counts stay in the other models.
@Model
public final class ExcludedApp {
    public var bundleID: String
    public var appName: String

    public init(bundleID: String, appName: String) {
        self.bundleID = bundleID
        self.appName = appName
    }
}
