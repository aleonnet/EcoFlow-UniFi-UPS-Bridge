// River Bridge — menu bar + janela (spec §7A). A UI é cliente do daemon:
// some o daemon, a UI degrada para "serviço parado"; nunca o contrário.
// Janela sem barra de título: o conteúdo (aurora + vidro) vai até a borda.

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
                .frame(minWidth: 820, minHeight: 560)
                .task { store.start() }
        }
        .defaultSize(width: 960, height: 640)
        .windowStyle(.hiddenTitleBar)
    }
}
