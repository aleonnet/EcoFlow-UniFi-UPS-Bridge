// River Bridge — menu bar + janela (spec §7A). A UI é cliente do daemon:
// some o daemon, a UI degrada para "serviço parado"; nunca o contrário.

import RiverBridgeCore
import SwiftUI

@main
struct RiverBridgeApp: App {
    @State private var store = TelemetryStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("River Bridge", id: "main") {
            DashboardWindow(store: store)
                .frame(minWidth: 780, minHeight: 520)
                .task { store.start() }
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView(store: store)
                .frame(width: 480)
        }
    }
}
