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
    }

    private func row(_ event: BridgeEvent) -> some View {
        Button {
            selected = selected?.id == event.id ? nil : event
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
        // Native macOS pattern for contextual detail: a POPOVER anchored to
        // the clicked row (system glass material, click-away dismiss) — the
        // generic sheet clashed with the design (owner 2026-08-31).
        .popover(
            isPresented: Binding(
                get: { selected?.id == event.id },
                set: { if !$0 { selected = nil } }
            ),
            arrowEdge: .trailing
        ) {
            EventDetailPopover(event: event)
        }
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

// Detail popover: system glass material, our type voice, friendly time with
// the raw value kept small and selectable — honest data, native dress.
struct EventDetailPopover: View {
    let event: BridgeEvent

    private var friendlyWhen: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: event.ts) else { return event.ts }
        let out = DateFormatter()
        out.locale = Locale(identifier: "pt_BR")
        out.dateFormat = "HH:mm:ss · dd/MM/yyyy"
        return out.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: EventsTimeline.symbol(for: event.event))
                    .font(.title3)
                    .foregroundStyle(EventsTimeline.color(for: event.event))
                Text(EventsTimeline.label(for: event.event))
                    .font(.system(.headline, design: .rounded))
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                detailRow("Quando", friendlyWhen)
                if let state = event.state { detailRow("Estado do UPS", state) }
                if let charge = event.charge {
                    detailRow("Bateria", TelemetryStore.percentText(charge))
                }
                if let reason = event.reason { detailRow("Detalhe", reason) }
            }

            Text(event.ts + " · " + event.event)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(minWidth: 300, maxWidth: 380, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).eyebrow()
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
    }
}
