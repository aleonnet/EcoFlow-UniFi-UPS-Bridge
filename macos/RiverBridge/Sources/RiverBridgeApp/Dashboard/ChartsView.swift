// Dense Tesla-style chart: 60-minute sliding window, 10 s buckets, thin
// BarMarks (~2 px), "Pico" annotation, consumption header with live value.
// No glass — the chart is content and lives on the ground.

import Charts
import RiverBridgeCore
import SwiftUI

struct ChartsView: View {
    var store: TelemetryStore

    @State private var metric: Metric = .powerW
    @State private var rows: [HistoryRow] = []
    @State private var scrubTS: Int?
    @State private var narrow = false

    enum Metric: String, CaseIterable, Identifiable {
        case powerW, charge
        var id: String { rawValue }
        var label: String { self == .charge ? "Bateria" : "Potência" }
        var apiName: String { self == .charge ? "charge" : "power_w" }
    }

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    private var peak: HistoryRow? {
        rows.compactMap { row in row.avg.map { _ in row } }
            .max { ($0.avg ?? 0) < ($1.avg ?? 0) }
    }

    private func format(_ value: Double?) -> String {
        metric == .charge
            ? TelemetryStore.percentText(value)
            : TelemetryStore.wattsText(value)
    }

    private var nowValue: String {
        metric == .charge ? store.chargeText : store.powerText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if rows.isEmpty {
                Text("Sem histórico ainda — os dados aparecem conforme o serviço coleta.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
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
                Text("Consumo — última hora").eyebrow()
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Consumo — última hora").eyebrow()
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
        if let response = try? await client.history(
            metric: metric.apiName, bucketSeconds: 10, from: from
        ) {
            rows = response.rows
        }
    }
}
