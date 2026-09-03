// Dense Tesla-style chart: 60-minute sliding window, 10 s buckets, thin
// BarMarks (~2 px), "Pico" annotation, consumption header with live value.
// No glass — the chart is content and lives on the ground.

import Charts
import RiverBridgeCore
import SwiftUI

struct ChartsView: View {
    var store: TelemetryStore
    /// Type chips shared with the events list (owner): in Events mode the
    /// histogram honours the same filter; empty = everything.
    var chips: [EventChip] = []

    @State private var metric: Metric = ChartsView.initialMetric()
    @State private var rows: [HistoryRow] = []
    @State private var eventRows: [EventLogRow] = []
    @State private var scrubTS: Int?
    @State private var narrow = false
    // Time-scale state (owner-approved SOTA blend, 2026-08-31): segmented
    // scopes reset/anchor the window; pinch compresses/expands X (trackpad
    // and touch are the same gesture); double-click zooms out ×2 (Grafana);
    // panning is the native horizontal chart scroll.
    @State private var scope: ChartScope = ChartsView.initialScope()
    @State private var visibleSeconds: Double = ChartsView.initialScope().seconds
    @State private var scrollDate = Date.now.addingTimeInterval(-ChartsView.initialScope().seconds)
    @State private var magnifyBase: Double?

    enum ChartScope: String, CaseIterable, Identifiable {
        case h1 = "1 h", h6 = "6 h", h24 = "24 h", d7 = "7 d"
        var id: String { rawValue }
        var seconds: Double {
            switch self {
            case .h1: 3600
            case .h6: 6 * 3600
            case .h24: 24 * 3600
            case .d7: 7 * 24 * 3600
            }
        }
        var eyebrowSuffix: String {
            switch self {
            case .h1: L10n.t("última hora", "last hour")
            case .h6: L10n.t("últimas 6 h", "last 6 h")
            case .h24: L10n.t("últimas 24 h", "last 24 h")
            case .d7: L10n.t("últimos 7 dias", "last 7 days")
            }
        }
    }

    /// The X domain is the SCOPE anchored at now — never the data extent.
    /// Refreshed by load(); keeps the viewport from drifting into the future
    /// (owner's print: bars ending mid-plot with an empty right side).
    @State private var chartNow = Date.now

    /// The REAL compression: zooming re-aggregates. Bucket keeps ~360 bars
    /// in the visible window (1 h→10 s … 7 d→28 min), never stretched pixels.
    private var fetchBucket: Int { max(Int(visibleSeconds / 360), 1) }

    enum Metric: String, CaseIterable, Identifiable {
        case powerW, charge, eventos
        var id: String { rawValue }
        var label: String {
            switch self {
            case .powerW: L10n.t("Potência", "Power")
            case .charge: L10n.t("Bateria", "Battery")
            case .eventos: L10n.t("Eventos", "Events")
            }
        }
        var apiName: String { self == .charge ? "charge" : "power_w" }
    }

    /// Dev seams (like --secao): open on the events chart / a scope for
    /// screenshot runs.
    static func initialMetric() -> Metric {
        ProcessInfo.processInfo.arguments.contains("--grafico-eventos") ? .eventos : .powerW
    }

    static func initialScope() -> ChartScope {
        ProcessInfo.processInfo.arguments.contains("--escopo-6h") ? .h6 : .h1
    }

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    private var peak: HistoryRow? {
        guard metric != .eventos else { return nil }   // rows belong to power/charge
        return rows.compactMap { row in row.avg.map { _ in row } }
            .max { ($0.avg ?? 0) < ($1.avg ?? 0) }
    }

    private func format(_ value: Double?) -> String {
        metric == .charge
            ? TelemetryStore.percentText(value)
            : TelemetryStore.wattsText(value)
    }

    private var nowValue: String {
        switch metric {
        case .charge: store.chargeText
        case .powerW: store.powerText
        case .eventos: "\(filteredEventRows.count)"
        }
    }

    private var filteredEventRows: [EventLogRow] {
        guard !chips.isEmpty else { return eventRows }
        return eventRows.filter { row in
            chips.contains { $0.matches(type: row.type, device: row.device, devices: store.devices) }
        }
    }

    private var eyebrowText: String {
        (metric == .eventos ? L10n.t("Eventos — ", "Events — ") : L10n.t("Consumo — ", "Usage — ")) + scope.eyebrowSuffix
    }

    private var isEmpty: Bool {
        metric == .eventos ? filteredEventRows.isEmpty : rows.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if isEmpty {
                Text(metric == .eventos
                     ? L10n.t("Nenhum evento nesse recorte — bom sinal.", "No events in this window — a good sign.")
                     : L10n.t("Sem histórico ainda — os dados aparecem conforme o serviço coleta.", "No history yet — data appears as the service collects."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if metric == .eventos {
                eventsChart
            } else {
                chart
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // Measured single-line need: hero + peak + Uso/Saída + the two
            // capsules ≈ 950 pt — below that the one-liner squeezes (owner's
            // print at ~790 pt), so the header stacks.
            narrow = width < 960
        }
        .task(id: "\(metric.rawValue)|\(scope.rawValue)|\(fetchBucket)") { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await load()
            }
        }
        .onChange(of: scope) {
            chartNow = .now
            visibleSeconds = scope.seconds
            scrollDate = chartNow.addingTimeInterval(-scope.seconds)
        }
    }

    // MARK: - Time-scale mechanics (pinch = same gesture on trackpad/touch)

    /// Every viewport move lands inside [now − scope, now]: the chart can
    /// NEVER show the future (class fix for the owner's hole-on-the-right).
    private func clampedScroll(_ proposedStart: TimeInterval, visible: Double) -> Date {
        let end = chartNow.timeIntervalSince1970
        let earliest = end - scope.seconds
        let latest = end - visible
        return Date(timeIntervalSince1970: min(max(proposedStart, earliest), latest))
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = magnifyBase ?? visibleSeconds
                if magnifyBase == nil { magnifyBase = visibleSeconds }
                // Anchor the CENTER of the window while the domain changes —
                // avoids the documented scroll-position jump when
                // chartXVisibleDomain moves under a scrolled chart.
                let center = scrollDate.timeIntervalSince1970 + visibleSeconds / 2
                let newVisible = min(max(base / value.magnification, scope.seconds / 8), scope.seconds)
                visibleSeconds = newVisible
                scrollDate = clampedScroll(center - newVisible / 2, visible: newVisible)
            }
            .onEnded { _ in magnifyBase = nil }
    }

    /// Grafana convention: double-click doubles the visible window.
    private func zoomOut() {
        let center = scrollDate.timeIntervalSince1970 + visibleSeconds / 2
        visibleSeconds = min(visibleSeconds * 2, scope.seconds)
        scrollDate = clampedScroll(center - visibleSeconds / 2, visible: visibleSeconds)
    }

    /// 96 -> 100, 43 -> 50: the axis top lands on a readable number.
    private func niceCeil(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        for m in [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]
        where value <= m * magnitude {
            return m * magnitude
        }
        return 10 * magnitude
    }

    private var eventsBucket: Int { max(Int(visibleSeconds / 30), 30) }

    /// Y follows the VISIBLE data (Grafana behavior): values accumulating in
    /// the current window raise the axis; leaving them behind lowers it.
    private var visibleYMax: Double {
        let fromT = scrollDate.timeIntervalSince1970 - 1
        let toT = fromT + visibleSeconds + 2
        if metric == .eventos {
            let bucket = eventsBucket
            var counts: [Int: Int] = [:]
            for row in filteredEventRows where Double(row.ts) >= fromT && Double(row.ts) <= toT {
                counts[row.ts / bucket * bucket, default: 0] += 1
            }
            return niceCeil(Double(counts.values.max() ?? 1))
        }
        let maxValue = rows.lazy
            .filter { Double($0.ts) >= fromT && Double($0.ts) <= toT }
            .compactMap(\.avg).max() ?? 0
        return niceCeil(max(maxValue * 1.1, 1))
    }

    @ViewBuilder
    private var header: some View {
        // Narrow/phone (owner's print at min width): stacked layout, smaller
        // hero, chips+picker on their own line — nothing wraps mid-word.
        if narrow {
            // Stacked header (owner 2026-08-31, "layout embolado"): hero and
            // live chips share the first line; BOTH capsules live on their
            // own line, scrolling horizontally when the window is narrower
            // than they are (the chips-row pattern) — nothing ever squeezes.
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(eyebrowText).eyebrow()
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(nowValue)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .fixedSize()
                                .contentTransition(.numericText())
                            if let peak, let avg = peak.avg {
                                Text(L10n.t("pico", "peak") + " \(format(avg)) " + L10n.t("às", "at") + " \(timeLabel(peak.ts))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    chip(L10n.t("Uso", "Load"), store.loadText)
                    chip(L10n.t("Saída", "Output"), store.outputVoltageText)
                }
                // Side by side, CENTERED, and sized to FIT the min width
                // (owner: "7 d" clipped + gray blotch — the horizontal
                // ScrollView here painted backdrop haze over its rect, the
                // same class as the edge-seam fix; killed in favor of
                // compact segments that actually fit).
                HStack(spacing: 6) {
                    picker
                    scopePicker
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            // .center: the right cluster (chips + picker) aligns vertically
            // with the hero block instead of floating on the eyebrow line.
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrowText).eyebrow()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(nowValue)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                            .contentTransition(.numericText())
                        if let peak, let avg = peak.avg {
                            Text(L10n.t("pico", "peak") + " \(format(avg)) " + L10n.t("às", "at") + " \(timeLabel(peak.ts))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer()
                chip(L10n.t("Uso", "Load"), store.loadText)
                chip(L10n.t("Saída", "Output"), store.outputVoltageText)
                picker
                scopePicker
            }
        }
    }

    /// Time-scope segments (Stocks/Health anchor): also the natural zoom
    /// reset — picking a scope re-frames window, bucket and scroll.
    private var scopePicker: some View {
        HStack(spacing: 2) {
            ForEach(ChartScope.allCases) { s in
                Button {
                    scope = s
                } label: {
                    // Compact: "7 d" -> "7d" so all four fit at 414 pt.
                    Text(narrow ? s.rawValue.replacingOccurrences(of: " ", with: "") : s.rawValue)
                        .fixedSize()
                        .font((narrow ? Font.caption : .callout).weight(scope == s ? .semibold : .regular))
                        .foregroundStyle(scope == s ? .primary : .secondary)
                        .padding(.horizontal, narrow ? 7 : 9)
                        .padding(.vertical, 4)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if scope == s {
                        Capsule().fill(.primary.opacity(0.14))
                    }
                }
            }
        }
        .padding(2)
        .glassEffect(.regular, in: Capsule())
    }

    private var picker: some View {
        HStack(spacing: 2) {
            ForEach(Metric.allCases) { m in
                Button {
                    metric = m
                } label: {
                    Text(m.label)
                        .fixedSize()   // never hyphenate ("Potên-cia" no telefone)
                        .font((narrow ? Font.caption : .callout).weight(metric == m ? .semibold : .regular))
                        .padding(.horizontal, narrow ? 7 : 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background {
                    if metric == m {
                        Capsule().fill(.primary.opacity(0.14))
                    }
                }
            }
        }
        .padding(2)
        .glassEffect(.regular, in: Capsule())
    }

    private func chip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label).eyebrow()
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
        .padding(.trailing, 6)
    }

    /// Chart legend label per (instance, type) — distinct hues so the stacked
    /// histogram separates types that share a color in the list (Queda × Bateria
    /// baixa). The colour scale's DOMAIN is this text, so it has to be unique per
    /// instance AND type: the instance goes in by its unique label (ordinal when
    /// two share a name), and an event without an owner falls to the only
    /// instance of its type.
    private func legendLabel(type: String, device: String?) -> String {
        if let kind = DeviceTypeRegistry.eventKind(type) {
            let dono = device.flatMap { uniqueLabels[$0] }
                ?? store.deviceNames.name(forEvent: type, device: device, devices: store.devices)
            return kind.short(name: dono)
        }
        return switch type {
        case "POWER_LOSS": L10n.t("Queda", "Loss")
        case "POWER_RESTORED": L10n.t("Restaurada", "Restored")
        case "LOW_BATTERY": L10n.t("Bateria baixa", "Low battery")
        case "COMM_LOST": "Comm down"
        case "COMM_RESTORED": "Comm up"
        default: type
        }
    }

    // Events over time (owner 2026-08-31): stacked histogram — color = type,
    // bar height = FREQUENCY in each 2-minute bucket, legend names the hues.
    private var eventsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            eventsChartCore
            legendRow
        }
    }

    private static let bridgeTypes = ["POWER_LOSS", "POWER_RESTORED", "LOW_BATTERY", "COMM_LOST", "COMM_RESTORED"]

    private var uniqueLabels: [String: String] { DeviceNames.uniqueLabels(instances: store.devices) }

    /// The legend and the colour domain: one entry per (instance, type) that is
    /// PRESENT in the filtered rows, in a stable order (bridge first, then each
    /// instance's vocabulary). Absent keys never take a hue nor a legend slot.
    private var legendKeys: [(label: String, color: Color)] {
        let present = Set(filteredEventRows.map { legendLabel(type: $0.type, device: $0.device) })
        var ordered: [(String, String?)] = Self.bridgeTypes.map { ($0, nil) }
        for device in store.devices {
            for kind in DeviceTypeRegistry.type(id: device.type)?.events ?? [] { ordered.append((kind.type, device.id)) }
        }
        var seen = Set<String>()
        var out: [(label: String, color: Color)] = []
        for (type, device) in ordered {
            let label = legendLabel(type: type, device: device)
            if present.contains(label), seen.insert(label).inserted { out.append((label, legendColor(type))) }
        }
        return out
    }

    /// Protection events share one family (purple, with red/orange for the
    /// outcomes that matter) instead of falling into the teal default.
    private func legendColor(_ type: String) -> Color {
        if let kind = DeviceTypeRegistry.eventKind(type) { return kind.tone.color }
        return switch type {
        case "POWER_LOSS": .orange
        case "POWER_RESTORED": .green
        case "LOW_BATTERY": .yellow
        case "COMM_LOST": .red
        case "COMM_RESTORED": .teal
        default: .purple
        }
    }

    /// One-line legend (the automatic one wrapped — owner's print): dots +
    /// short names, horizontally scrollable when narrower than its content.
    private var legendRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(legendKeys, id: \.label) { key in
                    HStack(spacing: 5) {
                        Circle().fill(key.color).frame(width: 7, height: 7)
                        Text(key.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
    }

    /// Per-type breakdown for the hovered bucket ("2 Queda · 1 Restaurada")
    /// — owner: show the stacked values, not only a total.
    private func bucketBreakdown(_ bucket: Int) -> String {
        var counts: [String: Int] = [:]
        for row in filteredEventRows where row.ts / eventsBucket * eventsBucket == bucket {
            counts[legendLabel(type: row.type, device: row.device), default: 0] += 1
        }
        let parts = legendKeys.compactMap { key -> String? in
            guard let n = counts[key.label], n > 0 else { return nil }
            return "\(n) \(key.label)"
        }
        return parts.joined(separator: " · ")
    }

    private var eventsChartCore: some View {
        Chart {
            ForEach(filteredEventRows) { row in
                BarMark(
                    x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts / eventsBucket * eventsBucket))),
                    y: .value("Eventos", 1),
                    width: .fixed(7)
                )
                .foregroundStyle(by: .value("Tipo", legendLabel(type: row.type, device: row.device)))
            }
            if let scrubTS {
                let bucket = scrubTS / eventsBucket * eventsBucket
                let resumo = bucketBreakdown(bucket)
                if !resumo.isEmpty {
                    RuleMark(x: .value("Hora", Date(timeIntervalSince1970: Double(bucket))))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
                            hoverCallout(valor: resumo, hora: timeLabel(bucket))
                        }
                }
            }
        }
        .chartXScale(domain: chartNow.addingTimeInterval(-scope.seconds)...chartNow)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleSeconds)
        .chartScrollPosition(x: $scrollDate)
        .chartYScale(domain: 0...visibleYMax)
        .simultaneousGesture(magnify)
        .onTapGesture(count: 2) { zoomOut() }
        .chartForegroundStyleScale(
            domain: legendKeys.map(\.label),
            range: legendKeys.map(\.color)
        )
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let number = value.as(Int.self) {
                        Text("\(number)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .frame(height: 150)
        .padding(.trailing, 26)
        // Hover scrub on the histogram too (drag stays pan): the callout
        // shows the stacked breakdown for the bucket under the cursor.
        .chartOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if let date: Date = proxy.value(atX: point.x) {
                            scrubTS = Int(date.timeIntervalSince1970)
                        }
                    case .ended:
                        scrubTS = nil
                    }
                }
        }
    }

    /// Discreet GLASS callout for hover values (owner): material capsule,
    /// theme-accented hairline, value + time.
    private func hoverCallout(valor: String, hora: String) -> some View {
        HStack(spacing: 6) {
            Text(valor)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
            Text(hora)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1) }
        .shadow(color: accent.opacity(0.20), radius: 6)
    }

    private var chart: some View {
        Chart(rows, id: \.ts) { row in
            if let avg = row.avg {
                BarMark(
                    x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))),
                    y: .value(metric.label, avg),
                    width: .fixed(2)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            if let peak, peak.ts == row.ts, let avg = row.avg {
                PointMark(
                    x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))),
                    y: .value(metric.label, avg)
                )
                .symbolSize(0)
                .annotation(position: .top, spacing: 2) {
                    Text(L10n.t("Pico", "Peak"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let scrubTS, scrubTS == row.ts, let avg = row.avg {
                RuleMark(x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        hoverCallout(valor: format(avg), hora: timeLabel(row.ts))
                    }
            }
        }
        // Axis labels need EXPLICIT Text content: styling an empty
        // AxisValueLabel() does nothing (verified on screen — they rendered
        // in default blue and the edge label truncated).
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number, format: .number.precision(.fractionLength(0)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .chartXScale(domain: chartNow.addingTimeInterval(-scope.seconds)...chartNow)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleSeconds)
        .chartScrollPosition(x: $scrollDate)
        .chartYScale(domain: 0...visibleYMax)
        .simultaneousGesture(magnify)
        .onTapGesture(count: 2) { zoomOut() }
        .frame(height: 150)
        .padding(.trailing, 26)   // room for trailing labels — nothing clips
        // Scrub moved from drag to CONTINUOUS HOVER: drag now belongs to the
        // native pan (scrollable axes) — one gesture, one meaning.
        .chartOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if let date: Date = proxy.value(atX: point.x) {
                            scrubTS = rows.min(by: {
                                abs(Double($0.ts) - date.timeIntervalSince1970)
                                    < abs(Double($1.ts) - date.timeIntervalSince1970)
                            })?.ts
                        }
                    case .ended:
                        scrubTS = nil
                    }
                }
        }
    }

    private func timeLabel(_ ts: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(ts)))
    }

    private func load() async {
        guard let endpoint = ApiEndpoint.discover() else { return }
        chartNow = .now
        let client = APIClient(endpoint: endpoint)
        let from = Int(Date().addingTimeInterval(-scope.seconds).timeIntervalSince1970)
        if metric == .eventos {
            if let result = try? await client.eventsLog(from: from, limit: 1000) {
                eventRows = result
            }
        } else if let response = try? await client.history(
            metric: metric.apiName, bucketSeconds: fetchBucket, from: from
        ) {
            rows = response.rows
        }
    }
}
