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

    /// Dev seam (like --secao): open on the events chart for screenshot runs.
    static func initialMetric() -> Metric {
        ProcessInfo.processInfo.arguments.contains("--grafico-eventos") ? .eventos : .powerW
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
        metric == .eventos ? "Eventos — última hora" : "Consumo — última hora"
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
        .task(id: metric) { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await load()
            }
        }
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
            }
        }
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
                x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts / 120 * 120))),
                y: .value("Eventos", 1),
                width: .fixed(7)
            )
            .foregroundStyle(by: .value("Tipo", shortLabel(row.type)))
        }
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
        .frame(height: 150)
        .padding(.trailing, 26)   // room for trailing labels — nothing clips
        .chartOverlay { proxy in
            GeometryReader { _ in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                if let date: Date = proxy.value(atX: drag.location.x) {
                                    scrubTS = rows.min(by: {
                                        abs(Double($0.ts) - date.timeIntervalSince1970)
                                            < abs(Double($1.ts) - date.timeIntervalSince1970)
                                    })?.ts
                                }
                            }
                            .onEnded { _ in scrubTS = nil }
                    )
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
        let client = APIClient(endpoint: endpoint)
        let from = Int(Date().addingTimeInterval(-3600).timeIntervalSince1970)
        if metric == .eventos {
            if let result = try? await client.eventsLog(from: from, limit: 1000) {
                eventRows = result
            }
        } else if let response = try? await client.history(
            metric: metric.apiName, bucketSeconds: 10, from: from
        ) {
            rows = response.rows
        }
    }
}
