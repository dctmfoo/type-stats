import SwiftUI
import TypeStatsCore

struct TypeStatsApp: App {
    private let controller = AppController.shared!

    var body: some Scene {
        MenuBarExtra {
            PopupView(controller: controller, period: .today)
        } label: {
            Image(systemName: controller.pause.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
