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
                            EventRow(event: event, selected: $selected)
                        }
                    }
                    // Compact block: kills the void between the label and the
                    // timestamp columns (owner's print).
                    .frame(maxWidth: 860, alignment: .leading)
                }
                .frame(maxHeight: 190)
            }
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

/// One event row: VISIBLE hover/selection (highlight + event-color glow —
/// the central gauge's language), popover anchored to the LABEL so it never
/// leaks outside the window (a full-width row anchors at the window edge).
private struct EventRow: View {
    let event: BridgeEvent
    @Binding var selected: BridgeEvent?

    @State private var hovering = false

    private var isSelected: Bool { selected?.id == event.id }
    private var lit: Bool { hovering || isSelected }
    private var color: Color { EventsTimeline.color(for: event.event) }

    var body: some View {
        Button {
            selected = isSelected ? nil : event
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: EventsTimeline.symbol(for: event.event))
                        .foregroundStyle(color)
                        .frame(width: 18)
                    Text(EventsTimeline.label(for: event.event))
                        .font(.system(.callout, design: .rounded).weight(.medium))
                }
                .popover(
                    isPresented: Binding(
                        get: { isSelected },
                        set: { if !$0 { selected = nil } }
                    ),
                    arrowEdge: .trailing
                ) {
                    EventDetailPopover(event: event)
                }
                Spacer()
                Text(event.dayTimeText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(lit ? Color.primary.opacity(0.10) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(color.opacity(lit ? 0.4 : 0), lineWidth: 1)
                }
                .shadow(color: color.opacity(lit ? 0.35 : 0), radius: 10)
        }
        .animation(.spring(duration: 0.25), value: lit)
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
