// Menu bar item: a UPS is protected power, not a battery — the glyph is a
// bolt shield (owner's call: never mistakable for Apple's battery item).
// Symbol names measured against the SDK on 2026-08-31 (NSImage probe).

import RiverBridgeCore
import SwiftUI

struct MenuBarLabel: View {
    var store: TelemetryStore

    private var glyph: String {
        guard store.phase == .live else { return "shield.slash" }
        if store.isLowBattery { return "bolt.shield" }
        return "bolt.shield.fill"
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
