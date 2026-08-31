// Power path: Tomada -> RIVER -> Rede. Flow dots run left-to-right on AC,
// and the battery segment reverses amber when discharging. Decoration with
// meaning: the arrows encode input_present, nothing else.

import RiverBridgeCore
import SwiftUI

struct PowerFlowView: View {
    var store: TelemetryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            node("powerplug.fill", "Tomada", dimmed: store.isOnBattery)
            FlowLink(active: store.phase == .live && !store.isOnBattery, reversed: false,
                     onBattery: store.isOnBattery, low: store.isLowBattery)
            node("minus.plus.batteryblock.fill", "RIVER", dimmed: false)
            FlowLink(active: store.phase == .live, reversed: false,
                     onBattery: store.isOnBattery, low: store.isLowBattery)
            node("network", "Rede", dimmed: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.isOnBattery ? "Rede alimentada pela bateria" : "Rede alimentada pela tomada")
    }

    private func node(_ symbol: String, _ label: String, dimmed: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(.quaternary.opacity(0.5), in: Circle())
                .opacity(dimmed ? 0.35 : 1)
            Text(label).eyebrow()
        }
    }
}

private struct FlowLink: View {
    let active: Bool
    let reversed: Bool
    let onBattery: Bool
    let low: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !active || reduceMotion)) { context in
            Canvas { canvas, size in
                let midY = size.height / 2
                let dotCount = 3
                let travel = size.width + 8
                let t = active && !reduceMotion
                    ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    : 0.5
                for i in 0..<dotCount {
                    let phase = (t + Double(i) / Double(dotCount)).truncatingRemainder(dividingBy: 1)
                    let x = phase * travel - 4
                    let rect = CGRect(x: x, y: midY - 2, width: 4, height: 4)
                    let color: Color = low ? .red : (onBattery ? .orange : .teal)
                    canvas.fill(Path(ellipseIn: rect), with: .color(color.opacity(active ? 0.9 : 0.25)))
                }
            }
            .frame(width: 34, height: 12)
        }
    }
}
