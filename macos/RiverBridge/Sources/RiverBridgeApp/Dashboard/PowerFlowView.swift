// Power flow, Tesla-grade: glowing ring nodes with live values inside, thin
// luminous connectors with energy dots traveling ALONG the line. Inactive
// paths dim — the diagram encodes input_present and nothing else.

import RiverBridgeCore
import SwiftUI

struct PowerFlowView: View {
    var store: TelemetryStore

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }
    private var gridActive: Bool { store.phase == .live && !store.isOnBattery }
    private var live: Bool { store.phase == .live }
    private let netColor = Color(red: 0.35, green: 0.65, blue: 1.0)

    var body: some View {
        HStack(spacing: 6) {
            FlowNode(
                symbol: "powerplug.fill", label: "Tomada",
                value: gridActive ? "CA" : "—",
                color: gridActive ? Color(red: 0.45, green: 0.75, blue: 1.0) : .secondary,
                active: gridActive
            )
            FlowConnector(active: gridActive, color: accent)
            FlowNode(
                symbol: "minus.plus.batteryblock.fill", label: "RIVER",
                value: store.chargeText, color: accent, active: live
            )
            FlowConnector(active: live, color: accent)
            FlowNode(
                symbol: "network", label: "Rede",
                value: store.powerText, color: live ? netColor : .secondary, active: live
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            store.isOnBattery ? "Rede alimentada pela bateria do RIVER" : "Rede alimentada pela tomada"
        )
    }
}

private struct FlowNode: View {
    let symbol: String
    let label: String
    let value: String
    let color: Color
    let active: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(active ? 0.9 : 0.3), lineWidth: 2)
                    .shadow(color: color.opacity(active ? 0.8 : 0), radius: 6)
                    .shadow(color: color.opacity(active ? 0.4 : 0), radius: 14)
                VStack(spacing: 1) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(active ? .primary : .secondary)
                    Text(value)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 62, height: 62)
            .animation(.easeInOut(duration: 0.6), value: active)

            Text(label).eyebrow()
        }
    }
}

private struct FlowConnector: View {
    let active: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active || reduceMotion)) { context in
            Canvas { canvas, size in
                let midY = size.height / 2
                // The line itself: thin, continuous, alive when active.
                var line = Path()
                line.move(to: CGPoint(x: 0, y: midY))
                line.addLine(to: CGPoint(x: size.width, y: midY))
                canvas.stroke(
                    line,
                    with: .color(active ? color.opacity(0.55) : Color.secondary.opacity(0.2)),
                    lineWidth: 1.5
                )
                guard active else { return }
                // Energy dots traveling along the line, each with a soft halo.
                let t = reduceMotion
                    ? 0.5
                    : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                for i in 0..<2 {
                    let phase = (t + Double(i) / 2).truncatingRemainder(dividingBy: 1)
                    let x = phase * size.width
                    let halo = CGRect(x: x - 5, y: midY - 5, width: 10, height: 10)
                    var haloCtx = canvas
                    haloCtx.addFilter(.blur(radius: 3))
                    haloCtx.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.7)))
                    let core = CGRect(x: x - 2, y: midY - 2, width: 4, height: 4)
                    canvas.fill(Path(ellipseIn: core), with: .color(.white.opacity(0.95)))
                }
            }
            .frame(height: 16)
        }
        .frame(minWidth: 30, maxWidth: .infinity)
    }
}
