// Event timeline: what happened, when, in the interface's voice.
// Rows hover-lift and CLICK opens a detail popover (owner 2026-08-31).

import RiverBridgeCore
import SwiftUI

struct EventsTimeline: View {
    var store: TelemetryStore
    @State private var selected: BridgeEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eventos").eyebrow()
            if store.events.isEmpty {
                Text("Nenhum evento até agora — bom sinal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.events) { event in
                            row(event)
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
        .sheet(item: $selected) { event in
            EventDetailSheet(event: event)
        }
    }

    private func row(_ event: BridgeEvent) -> some View {
        Button {
            selected = event
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol(for: event.event))
                    .foregroundStyle(Self.color(for: event.event))
                    .frame(width: 18)
                Text(Self.label(for: event.event))
                    .font(.system(.callout, design: .rounded).weight(.medium))
                Spacer()
                Text(event.timeText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(RowHover())
        .hoverLift(glow: Self.color(for: event.event), scale: 1.005)
    }

    static func label(for event: String) -> String {
        switch event {
        case "POWER_LOSS": return "Queda de energia — na bateria"
        case "POWER_RESTORED": return "Energia restaurada"
        case "LOW_BATTERY": return "Bateria baixa"
        case "COMM_LOST": return "Comunicação perdida com o RIVER"
        case "COMM_RESTORED": return "Comunicação restabelecida"
        default: return event
        }
    }

    static func symbol(for event: String) -> String {
        switch event {
        case "POWER_LOSS": return "bolt.slash.fill"
        case "POWER_RESTORED": return "bolt.badge.checkmark.fill"
        case "LOW_BATTERY": return "battery.25percent"
        case "COMM_LOST": return "antenna.radiowaves.left.and.right.slash"
        case "COMM_RESTORED": return "antenna.radiowaves.left.and.right"
        default: return "circle.fill"
        }
    }

    static func color(for event: String) -> Color {
        switch event {
        case "POWER_LOSS", "LOW_BATTERY": return .orange
        case "COMM_LOST": return .red
        case "POWER_RESTORED", "COMM_RESTORED": return .green
        default: return .secondary
        }
    }
}

/// Subtle full-row highlight under the cursor (separate from the lift).
private struct RowHover: View {
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            .onHover { hovering = $0 }
    }
}

// Detail sheet: everything the event carries — honest raw data included.
struct EventDetailSheet: View {
    let event: BridgeEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: EventsTimeline.symbol(for: event.event))
                    .font(.title2)
                    .foregroundStyle(EventsTimeline.color(for: event.event))
                Text(EventsTimeline.label(for: event.event))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                detailRow("Quando", event.ts)
                detailRow("Evento", event.event)
                if let state = event.state { detailRow("Estado do UPS", state) }
                if let charge = event.charge {
                    detailRow("Bateria no momento", TelemetryStore.percentText(charge))
                }
                if let reason = event.reason { detailRow("Detalhe", reason) }
            }

            HStack {
                Spacer()
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).eyebrow()
            Text(value)
                .font(.system(.body, design: .rounded))
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }
}
