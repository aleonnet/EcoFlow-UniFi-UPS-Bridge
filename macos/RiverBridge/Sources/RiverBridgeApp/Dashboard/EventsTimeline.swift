// Event timeline: what happened, when, in the interface's voice.

import RiverBridgeCore
import SwiftUI

struct EventsTimeline: View {
    var store: TelemetryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eventos").eyebrow()
            if store.events.isEmpty {
                Text("Nenhum evento até agora — bom sinal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.events) { event in
                            row(event)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
    }

    private func row(_ event: BridgeEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(for: event.event))
                .foregroundStyle(color(for: event.event))
                .frame(width: 18)
            Text(label(for: event.event))
                .font(.system(.callout, design: .rounded).weight(.medium))
            Spacer()
            Text(event.ts.suffix(14).prefix(8))  // HH:MM:SS from RFC3339-ish ts
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func label(for event: String) -> String {
        switch event {
        case "POWER_LOSS": return "Queda de energia — na bateria"
        case "POWER_RESTORED": return "Energia restaurada"
        case "LOW_BATTERY": return "Bateria baixa"
        case "COMM_LOST": return "Comunicação perdida com o RIVER"
        case "COMM_RESTORED": return "Comunicação restabelecida"
        default: return event
        }
    }

    private func symbol(for event: String) -> String {
        switch event {
        case "POWER_LOSS": return "bolt.slash.fill"
        case "POWER_RESTORED": return "bolt.badge.checkmark.fill"
        case "LOW_BATTERY": return "battery.25percent"
        case "COMM_LOST": return "antenna.radiowaves.left.and.right.slash"
        case "COMM_RESTORED": return "antenna.radiowaves.left.and.right"
        default: return "circle.fill"
        }
    }

    private func color(for event: String) -> Color {
        switch event {
        case "POWER_LOSS", "LOW_BATTERY": return .orange
        case "COMM_LOST": return .red
        case "POWER_RESTORED", "COMM_RESTORED": return .green
        default: return .secondary
        }
    }
}
