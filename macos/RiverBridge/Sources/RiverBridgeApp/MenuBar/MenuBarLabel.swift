// Menu bar item: shield that fills with the charge (MenuBarIcon) + optional
// percentage text (user preference, toggled from the dropdown).

import RiverBridgeCore
import SwiftUI

struct MenuBarLabel: View {
    var store: TelemetryStore
    @AppStorage("menuBarShowsPercent") private var showsPercent = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image(
                fraction: store.chargeFraction,
                live: store.phase == .live
            ))
            if showsPercent, store.phase == .live, store.chargeFraction != nil {
                Text(store.chargeText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
        .task {
            store.start()
            // Dev affordance: `--abrir-painel` opens the dashboard at launch
            // (screenshots, demos); normal launches stay menu-bar-only.
            if ProcessInfo.processInfo.arguments.contains("--abrir-painel") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
