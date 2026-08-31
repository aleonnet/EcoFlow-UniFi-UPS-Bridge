// Compact glance: mini ring, three facts, one action. The full story lives
// in the window.

import RiverBridgeCore
import SwiftUI

struct MenuBarPopover: View {
    var store: TelemetryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                EnergyRing(store: store, lineWidth: 7, showsDetail: false)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.stateLabel)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .contentTransition(.numericText())
                    Text("Autonomia \(store.runtimeText)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if case .serviceDown(let reason) = store.phase {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 16) {
                    fact("Bateria", store.chargeText)
                    fact("Carga", store.powerText)
                    fact("Saída", store.outputVoltageText)
                }
            }

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Abrir painel", systemImage: "rectangle.expand.diagonal")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).eyebrow()
            Text(value)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
    }
}
