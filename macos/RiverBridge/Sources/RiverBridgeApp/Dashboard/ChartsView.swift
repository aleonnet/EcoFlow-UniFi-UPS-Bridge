// History charts (Swift Charts): battery % and power W, with a scrub cursor.
// Exactly two time-series charts + the event timeline (YAGNI fence §7A.7).

import Charts
import RiverBridgeCore
import SwiftUI

struct ChartsView: View {
    var store: TelemetryStore

    @State private var metric: Metric = .charge
    @State private var rows: [HistoryRow] = []
    @State private var scrubTS: Int?

    enum Metric: String, CaseIterable, Identifiable {
        case charge, powerW
        var id: String { rawValue }
        var label: String { self == .charge ? "Bateria %" : "Potência W" }
        var apiName: String { self == .charge ? "charge" : "power_w" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Histórico").eyebrow()
                Spacer()
                Picker("Métrica", selection: $metric) {
                    ForEach(Metric.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery))
                .frame(width: 220)
            }

            if rows.isEmpty {
                emptyChart
            } else {
                chart
            }
        }
        .task(id: metric) { await load() }
        .task {
            // Refresh every 30 s while the view is on screen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await load()
            }
        }
    }

    private var emptyChart: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary.opacity(0.4))
            .frame(height: 150)
            .overlay {
                Text("Sem histórico ainda — os dados aparecem conforme o serviço coleta.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
    }

    @ViewBuilder
    private var chart: some View {
        if metric == .charge {
            baseChart.chartYScale(domain: 0...100)
        } else {
            baseChart
        }
    }

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    private var baseChart: some View {
        Chart(rows, id: \.ts) { row in
            if let avg = row.avg {
                AreaMark(
                    x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))),
                    y: .value(metric.label, avg)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.30), accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                // Glow pass: the same line, wide and translucent, under the
                // crisp one — the luminous stroke of the reference apps.
                LineMark(
                    x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))),
                    y: .value(metric.label, avg),
                    series: .value("s", "glow")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 7, lineCap: .round))
                .foregroundStyle(accent.opacity(0.22))
                LineMark(
                    x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))),
                    y: .value(metric.label, avg),
                    series: .value("s", "core")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .foregroundStyle(accent)
            }
            if let scrubTS, scrubTS == row.ts, let avg = row.avg {
                RuleMark(x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))))
                    .foregroundStyle(.secondary.opacity(0.5))
                PointMark(
                    x: .value("Hora", Date(timeIntervalSince1970: Double(row.ts))),
                    y: .value(metric.label, avg)
                )
                .annotation(position: .top) {
                    Text(metric == .charge
                         ? TelemetryStore.percentText(avg)
                         : TelemetryStore.wattsText(avg))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.background.opacity(0.9), in: Capsule())
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(.quaternary)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 150)
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

    private func load() async {
        guard let endpoint = ApiEndpoint.discover() else { return }
        let client = APIClient(endpoint: endpoint)
        let from = Int(Date().addingTimeInterval(-6 * 3600).timeIntervalSince1970)
        if let response = try? await client.history(
            metric: metric.apiName, bucketSeconds: 120, from: from
        ) {
            rows = response.rows
        }
    }
}
