import ServiceManagement
import TypeStatsCore

/// The real login item: this app bundle, registered with `SMAppService.mainApp`.
/// macOS remembers the bundle's path, so the owner should run the installed copy
/// (scripts/install-app.sh) before turning this on.
@MainActor
final class MainLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled  // .notRegistered, .notFound
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }

    static func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
