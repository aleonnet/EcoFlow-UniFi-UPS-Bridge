// Dense Tesla-style chart: 60-minute sliding window, 10 s buckets, thin
// BarMarks (~2 px), "Pico" annotation, consumption header with live value.
// No glass — the chart is content and lives on the ground.

import Charts
import RiverBridgeCore
import SwiftUI

struct ChartsView: View {
    var store: TelemetryStore

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
            case .h1: "última hora"
            case .h6: "últimas 6 h"
            case .h24: "últimas 24 h"
            case .d7: "últimos 7 dias"
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
            case .powerW: "Potência"
            case .charge: "Bateria"
            case .eventos: "Eventos"
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
        case .eventos: "\(eventRows.count)"
        }
    }

    private var eyebrowText: String {
        (metric == .eventos ? "Eventos — " : "Consumo — ") + scope.eyebrowSuffix
    }

    private var isEmpty: Bool {
        metric == .eventos ? eventRows.isEmpty : rows.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if isEmpty {
                Text(metric == .eventos
                     ? "Nenhum evento na última hora — bom sinal."
                     : "Sem histórico ainda — os dados aparecem conforme o serviço coleta.")
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
            narrow = width < 620
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
            for row in eventRows where Double(row.ts) >= fromT && Double(row.ts) <= toT {
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
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrowText).eyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(nowValue)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .fixedSize()
                        .contentTransition(.numericText())
                    if let peak, let avg = peak.avg {
                        Text("pico \(format(avg)) às \(timeLabel(peak.ts))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    chip("Uso", store.loadText)
                    chip("Saída", store.outputVoltageText)
                    Spacer(minLength: 0)
                    picker
                }
                HStack {
                    scopePicker
                    Spacer(minLength: 0)
                }
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
                            Text("pico \(format(avg)) às \(timeLabel(peak.ts))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer()
                chip("Uso", store.loadText)
                chip("Saída", store.outputVoltageText)
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
                    Text(s.rawValue)
                        .fixedSize()
                        .font(.callout.weight(scope == s ? .semibold : .regular))
                        .foregroundStyle(scope == s ? .primary : .secondary)
                        .padding(.horizontal, 9)
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
                        .font(.callout.weight(metric == m ? .semibold : .regular))
                        .padding(.horizontal, 10)
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

    /// Chart legend label per type — distinct hues so the stacked histogram
    /// separates types that share a color in the list (Queda × Bateria baixa).
    private func shortLabel(_ type: String) -> String {
        switch type {
        case "POWER_LOSS": "Queda"
        case "POWER_RESTORED": "Restaurada"
        case "LOW_BATTERY": "Bateria baixa"
        case "COMM_LOST": "Comm perdida"
        case "COMM_RESTORED": "Comm restabelecida"
        default: type
        }
    }

    // Events over time (owner 2026-08-31): stacked histogram — color = type,
    // bar height = FREQUENCY in each 2-minute bucket, legend names the hues.
    private var eventsChart: some View {
        Chart(eventRows) { row in
            BarMark(
                x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts / eventsBucket * eventsBucket))),
                y: .value("Eventos", 1),
                width: .fixed(7)
            )
            .foregroundStyle(by: .value("Tipo", shortLabel(row.type)))
        }
        .chartXScale(domain: chartNow.addingTimeInterval(-scope.seconds)...chartNow)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleSeconds)
        .chartScrollPosition(x: $scrollDate)
        .chartYScale(domain: 0...visibleYMax)
        .simultaneousGesture(magnify)
        .onTapGesture(count: 2) { zoomOut() }
        .chartForegroundStyleScale([
            "Queda": Color.orange,
            "Restaurada": Color.green,
            "Bateria baixa": Color.yellow,
            "Comm perdida": Color.red,
            "Comm restabelecida": Color.teal,
        ])
        .chartLegend(position: .bottom, spacing: 6)
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
                    Text("Pico")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let scrubTS, scrubTS == row.ts, let avg = row.avg {
                RuleMark(x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top) {
                        Text(format(avg))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.background.opacity(0.9), in: Capsule())
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
