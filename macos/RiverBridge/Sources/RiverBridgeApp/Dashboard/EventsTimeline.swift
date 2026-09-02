// Event timeline: what happened, when, in the interface's voice.
// Rows hover-lift and CLICK opens a detail popover (owner 2026-08-31).

import RiverBridgeCore
import SwiftUI

/// Type filter chips: each chip covers the event types a person thinks of
/// as one subject (Comunicação = lost + restored).
enum EventChip: String, CaseIterable, Identifiable {
    case queda, restaurada, bateria, comunicacao, protecao

    var id: String { rawValue }
    /// O chip de proteção leva o NOME que o usuário deu ao dispositivo; os demais
    /// são assuntos do próprio bridge e não pertencem a plugin nenhum.
    func label(names: DeviceNames) -> String {
        switch self {
        case .queda: L10n.t("Queda", "Loss")
        case .restaurada: L10n.t("Restaurada", "Restored")
        case .bateria: L10n.t("Bateria baixa", "Low battery")
        case .comunicacao: L10n.t("Comunicação", "Comm")
        case .protecao: names.name(for: .udr7)
        }
    }
    var symbol: String {
        switch self {
        case .queda: "bolt.slash.fill"
        case .restaurada: "bolt.badge.checkmark.fill"
        case .bateria: "battery.25percent"
        case .comunicacao: "antenna.radiowaves.left.and.right"
        case .protecao: "shield.lefthalf.filled"
        }
    }
    var color: Color {
        switch self {
        case .queda: .orange
        case .bateria: .yellow   // matches the chart legend (owner 2026-08-31)
        case .restaurada: .green
        case .comunicacao: .red
        case .protecao: .purple  // protection family (chart legend uses the same hue)
        }
    }
    var types: [String] {
        switch self {
        case .queda: ["POWER_LOSS"]
        case .restaurada: ["POWER_RESTORED"]
        case .bateria: ["LOW_BATTERY"]
        case .comunicacao: ["COMM_LOST", "COMM_RESTORED"]
        case .protecao: DevicePluginRegistry.allEventTypes
        }
    }
}

/// Period scopes (Safari-style recorte temporal; Personalizado = DatePickers).
enum EventPeriod: String, CaseIterable, Identifiable {
    case hoje = "Hoje"
    case dias7 = "7 dias"
    case dias30 = "30 dias"
    case tudo = "Tudo"
    case personalizado = "Personalizado"

    var id: String { rawValue }

    /// Segment label — short enough for five segments at 414 pt.
    var short: String {
        switch self {
        case .hoje: L10n.t("Hoje", "Today")
        case .dias7: "7 d"
        case .dias30: "30 d"
        case .tudo: L10n.t("Tudo", "All")
        case .personalizado: L10n.t("Datas", "Dates")
        }
    }

    func fromTS(now: Date = .now) -> Int? {
        switch self {
        case .hoje: Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        case .dias7: Int(now.addingTimeInterval(-7 * 86400).timeIntervalSince1970)
        case .dias30: Int(now.addingTimeInterval(-30 * 86400).timeIntervalSince1970)
        case .tudo, .personalizado: nil
        }
    }
}

struct EventsTimeline: View {
    var store: TelemetryStore
    var chips: Set<EventChip>
    var period: EventPeriod
    var customFrom: Date
    var customTo: Date

    @State private var rows: [BridgeEvent] = []
    @State private var loadFailed = false
    @State private var selected: BridgeEvent?
    @State private var narrow = false

    private var filterKey: String {
        chips.map(\.rawValue).sorted().joined(separator: ",")
            + "|\(period.rawValue)|\(Int(customFrom.timeIntervalSince1970))"
            + "|\(Int(customTo.timeIntervalSince1970))"
    }

    // The filter bar lives in the parent's pinned section header; this view
    // is the list — SOURCE OF TRUTH is the daemon's persisted log (survives
    // app restarts; coherent with Limpar). SSE arrivals just trigger reload.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loadFailed {
                Text(L10n.t("Histórico indisponível — a UI não alcança o serviço.", "History unavailable — the UI can’t reach the service."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if rows.isEmpty {
                Text(chips.isEmpty && period == .tudo
                     ? L10n.t("Nenhum evento até agora — bom sinal.", "No events so far — a good sign.")
                     : L10n.t("Nenhum evento nesse recorte.", "No events in this range."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { event in
                    EventRow(event: event, selected: $selected, narrow: narrow,
                             names: store.deviceNames)
                }
            }
        }
        // Compact block: kills the void between the label and the
        // timestamp columns (owner's print).
        .frame(maxWidth: 860, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            narrow = width < 560
        }
        .task(id: filterKey) { await load() }
        .onChange(of: store.events.count) {
            Task { await load() }
        }
    }

    private func load() async {
        guard let endpoint = ApiEndpoint.discover() else {
            loadFailed = true
            return
        }
        var fromTS = period.fromTS()
        var toTS: Int? = nil
        if period == .personalizado {
            fromTS = Int(Calendar.current.startOfDay(for: customFrom).timeIntervalSince1970)
            // inclusive end of the chosen day
            toTS = Int(Calendar.current.startOfDay(for: customTo)
                .addingTimeInterval(86400).timeIntervalSince1970) - 1
        }
        let types = chips.flatMap(\.types)
        do {
            let result = try await APIClient(endpoint: endpoint)
                .eventsLog(from: fromTS, to: toTS, types: types)
            rows = result.map(\.asBridgeEvent)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    static func label(for event: String, names: DeviceNames) -> String {
        // Os eventos de DISPOSITIVO saem do registro, com o nome do usuário; só os
        // do próprio bridge ficam escritos aqui.
        if let kind = DevicePluginRegistry.eventKind(event) {
            return kind.long(name: names.name(forEventType: event))
        }
        switch event {
        case "POWER_LOSS": return L10n.t("Queda de energia — na bateria", "Power loss — on battery")
        case "POWER_RESTORED": return L10n.t("Energia restaurada", "Power restored")
        case "LOW_BATTERY": return L10n.t("Bateria baixa", "Low battery")
        case "COMM_LOST": return L10n.t("Comunicação perdida com o RIVER", "Communication with the RIVER lost")
        case "COMM_RESTORED": return L10n.t("Comunicação restabelecida", "Communication restored")
        default: return event
        }
    }

    static func symbol(for event: String) -> String {
        if let kind = DevicePluginRegistry.eventKind(event) { return kind.symbol }
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
        if let kind = DevicePluginRegistry.eventKind(event) { return kind.tone.color }
        switch event {
        case "POWER_LOSS": return .orange
        case "LOW_BATTERY": return .yellow   // matches the chart legend
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
    var narrow = false
    var names: DeviceNames

    @State private var hovering = false

    private var isSelected: Bool { selected?.id == event.id }
    private var lit: Bool { hovering || isSelected }
    private var color: Color { EventsTimeline.color(for: event.event) }

    var body: some View {
        // Inline expansion (owner 2026-08-31): a system popover is its own
        // window and ALWAYS leaks past the app frame near edges. The detail
        // opens INSIDE the row card — accordion, phone-identical, never
        // overflows, scrolls with the list.
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    selected = isSelected ? nil : event
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: EventsTimeline.symbol(for: event.event))
                        .foregroundStyle(color)
                        .frame(width: 18)
                    Text(EventsTimeline.label(for: event.event, names: names))
                        .font(.system(.callout, design: .rounded).weight(.medium))
                    Spacer()
                    Text(event.dayTimeText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isSelected ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            if isSelected {
                EventDetailInline(event: event)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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

// Inline detail (expands inside the row card): our type voice, friendly
// time, raw value small and selectable — honest data that never overflows.
struct EventDetailInline: View {
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
        VStack(alignment: .leading, spacing: 10) {
            // No title here: the row above already carries icon + label.
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                detailRow(L10n.t("Quando", "When"), friendlyWhen)
                if let state = event.state { detailRow(L10n.t("Estado do UPS", "UPS state"), state) }
                if let charge = event.charge {
                    detailRow(L10n.t("Bateria", "Battery"), TelemetryStore.percentText(charge))
                }
                if let reason = event.reason { detailRow(L10n.t("Detalhe", "Detail"), reason) }
            }

            Text(event.ts + " · " + event.event)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// The pinned EVENTOS header as a utility bar: eyebrow + period scope +
/// type chips (token/scope pattern — Mail/Finder). Multi-select; empty
/// selection = everything.
struct EventsFilterBar: View {
    @Binding var chips: Set<EventChip>
    var names: DeviceNames
    @Binding var period: EventPeriod
    @Binding var customFrom: Date
    @Binding var customTo: Date
    @State private var narrow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(L10n.t("Eventos", "Events")).eyebrow().fixedSize()
                Spacer(minLength: 8)
                // Segmented buttons, not a menu (owner 2026-08-31). With
                // Datas active the De/Até pickers TAKE THE SEGMENTS' PLACE
                // inside the same capsule (owner: no extra row, no leftover
                // Tudo); the ✕ returns to Tudo.
                HStack(spacing: 2) {
                    if period == .personalizado {
                        HStack(spacing: narrow ? 5 : 8) {
                            DatePicker(L10n.t("De", "From"), selection: $customFrom, displayedComponents: .date)
                            DatePicker(L10n.t("Até", "To"), selection: $customTo, displayedComponents: .date)
                        }
                        .datePickerStyle(.compact)
                        .controlSize(narrow ? .small : .regular)
                        .font(narrow ? .caption : .callout)
                        .padding(.horizontal, narrow ? 3 : 6)
                        Button {
                            period = .tudo
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("Fechar o recorte por datas", "Close the date range"))
                    } else {
                        ForEach(EventPeriod.allCases) { p in
                            Button {
                                period = p
                            } label: {
                                // Same compact scale as the chart capsules
                                // (owner): "7 d" -> "7d", caption, pad 7.
                                Text(narrow ? p.short.replacingOccurrences(of: " ", with: "") : p.short)
                                    .fixedSize()
                                    .font((narrow ? Font.caption : .callout).weight(period == p ? .semibold : .regular))
                                    .foregroundStyle(period == p ? .primary : .secondary)
                                    .padding(.horizontal, narrow ? 7 : 9)
                                    .padding(.vertical, 4)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .background {
                                if period == p {
                                    Capsule().fill(.primary.opacity(0.14))
                                }
                            }
                            .help(p.rawValue)
                        }
                    }
                }
                .padding(2)
                .glassEffect(.regular, in: Capsule())
                .fixedSize()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EventChip.allCases) { chip in
                        chipButton(chip)
                    }
                }
            }

        }
        .animation(.snappy(duration: 0.2), value: period)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            narrow = width < 500
        }
    }

    private func chipButton(_ chip: EventChip) -> some View {
        let isOn = chips.contains(chip)
        return Button {
            if isOn { chips.remove(chip) } else { chips.insert(chip) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: chip.symbol)
                    .foregroundStyle(chip.color)
                Text(chip.label(names: names)).fixedSize()
            }
            .font(.system(.callout, design: .rounded).weight(isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? .primary : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            Capsule().fill(isOn ? chip.color.opacity(0.18) : Color.primary.opacity(0.05))
                .overlay {
                    Capsule().strokeBorder(chip.color.opacity(isOn ? 0.45 : 0), lineWidth: 1)
                }
        }
        .animation(.snappy(duration: 0.18), value: isOn)
    }
}
