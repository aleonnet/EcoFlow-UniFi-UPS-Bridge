// Live menu bar icon: battery glyph + percentage, like the system battery
// item. Absent data = "—" and outline glyph — never a fabricated level.

import RiverBridgeCore
import SwiftUI

struct MenuBarLabel: View {
    var store: TelemetryStore

    private var glyph: String {
        guard store.phase == .live, let fraction = store.chargeFraction else {
            return "bolt.slash"
        }
        if store.isCharging { return "battery.100percent.bolt" }
        switch fraction {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: glyph)
            if store.phase == .live {
                Text(store.chargeText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
        .task { store.start() }
    }
}
