// Menu bar item: shield that fills with the charge (MenuBarIcon) + optional
// percentage text (user preference, toggled from the dropdown).

import RiverBridgeCore
import SwiftUI

struct MenuBarLabel: View {
    var store: TelemetryStore
    @AppStorage("menuBarShowsPercent") private var showsPercent = true

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
        .task { store.start() }
    }
}
