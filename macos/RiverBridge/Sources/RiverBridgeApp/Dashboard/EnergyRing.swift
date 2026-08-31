// The signature element: a circular energy ring whose gradient IS the power
// state. Hero number inside is the AUTONOMY (what the owner actually needs),
// not the raw percentage. Charging = slow 6 s breath; Reduce Motion disables
// every non-essential movement.

import RiverBridgeCore
import SwiftUI

struct EnergyRing: View {
    var store: TelemetryStore
    var lineWidth: CGFloat = 14
    var showsDetail = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { store.chargeFraction ?? 0 }
    private var hasData: Bool { store.phase == .live && store.chargeFraction != nil }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: reduceMotion || !store.isCharging)) { context in
            let breath = breathScale(at: context.date)
            ZStack {
                Circle()
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Circle()
                    .trim(from: 0, to: hasData ? fraction : 0)
                    .stroke(
                        Theme.accentGradient(onBattery: store.isOnBattery, lowBattery: store.isLowBattery),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(breath)
                    .shadow(
                        color: Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
                            .opacity(hasData ? 0.35 : 0),
                        radius: 8
                    )
                    .animation(reduceMotion ? nil : .spring(duration: 0.8), value: fraction)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: store.isOnBattery)

                if showsDetail {
                    detail
                } else if hasData {
                    Text(store.chargeText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: "bolt.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bateria \(store.chargeText), autonomia \(store.runtimeText), \(store.stateLabel)")
    }

    private var detail: some View {
        VStack(spacing: 2) {
            Text("Autonomia").eyebrow()
            Text(store.runtimeText)
                .modifier(HeroNumber(value: store.runtimeText))
            Text(hasData ? "\(store.chargeText) · \(store.stateLabel)" : store.stateLabel)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    /// 6 s sine breath while charging — the ring is alive, not blinking.
    private func breathScale(at date: Date) -> CGFloat {
        guard store.isCharging, !reduceMotion else { return 1 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
        return 1 + 0.012 * sin(phase * 2 * .pi)
    }
}
