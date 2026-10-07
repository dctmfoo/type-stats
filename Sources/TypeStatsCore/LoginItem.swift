import Observation

/// Whether TypeStats is set to launch at login.
public enum LoginItemStatus: String, Sendable {
    case enabled
    case disabled
    /// Registered, but the person must allow it in System Settings > General > Login Items.
    case requiresApproval
}

/// The system login item for this app (`SMAppService.mainApp` in the app; a fake in tests).
@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Backs the "Start at login" toggle: turning it on registers the login item, off
/// unregisters it, and the toggle always shows the status read back from the system.
@MainActor
@Observable
public final class LoginItem {
    public private(set) var status: LoginItemStatus
    /// The last register or unregister error, cleared by the next success.
    public private(set) var lastError: String?
    @ObservationIgnored private let service: LoginItemService

    public init(service: LoginItemService) {
        self.service = service
        status = service.status
    }

    /// On when registered, including while waiting for approval.
    public var isOn: Bool { status != .disabled }

    public func set(_ on: Bool) {
        do {
            if on { try service.register() } else { try service.unregister() }
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
        refresh()
    }

    /// Reads the status back from the system (it can change in System Settings).
    public func refresh() {
        status = service.status
    }
}

/// A login item that only lives in memory. Used in test mode so a test build can
/// never register itself to launch at login.
@MainActor
public final class InMemoryLoginItemService: LoginItemService {
    public private(set) var status: LoginItemStatus = .disabled
    public init() {}
    public func register() throws { status = .enabled }
    public func unregister() throws { status = .disabled }
}
