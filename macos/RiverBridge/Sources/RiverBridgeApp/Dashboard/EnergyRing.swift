// The signature: an energy ring with tick marks, angular gradient sweep and
// layered glow, around a glass disc holding the AUTONOMY hero. Charging =
// 6 s breath. Reduce Motion disables every non-essential movement.

import RiverBridgeCore
import SwiftUI

struct EnergyRing: View {
    var store: TelemetryStore
    var lineWidth: CGFloat = 16
    var showsDetail = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { store.chargeFraction ?? 0 }
    private var hasData: Bool { store.phase == .live && store.chargeFraction != nil }

    private var palette: [Color] {
        Theme.colors(onBattery: store.isOnBattery, low: store.isLowBattery)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: reduceMotion || !store.isCharging)) { context in
            let breath = breathScale(at: context.date)
            ZStack {
                ticks

                Circle()
                    .stroke(.quaternary.opacity(0.6),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(lineWidth / 2 + 8)

                Circle()
                    .trim(from: 0, to: hasData ? fraction : 0)
                    .stroke(
                        AngularGradient(
                            colors: [palette[0], palette[1], palette[0]],
                            center: .center, startAngle: .degrees(0), endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .padding(lineWidth / 2 + 8)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(breath)
                    .shadow(color: palette[0].opacity(hasData ? 0.5 : 0), radius: 14)
                    .shadow(color: palette[1].opacity(hasData ? 0.25 : 0), radius: 30)
                    .animation(reduceMotion ? nil : .spring(duration: 0.8), value: fraction)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: store.isOnBattery)

                inner
                    .padding(lineWidth + 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bateria \(store.chargeText), autonomia \(store.runtimeText), \(store.stateLabel)")
    }

    /// 60 fine ticks — the instrument face behind the ring.
    private var ticks: some View {
        ForEach(0..<60, id: \.self) { i in
            RoundedRectangle(cornerRadius: 1)
                .fill(.secondary.opacity(i % 5 == 0 ? 0.35 : 0.15))
                .frame(width: i % 5 == 0 ? 2 : 1, height: i % 5 == 0 ? 7 : 4)
                .offset(y: -2)
                .frame(maxHeight: .infinity, alignment: .top)
                .rotationEffect(.degrees(Double(i) * 6))
        }
    }

    @ViewBuilder
    private var inner: some View {
        Group {
            if showsDetail {
                VStack(spacing: 2) {
                    Text("Autonomia").eyebrow()
                    Text(store.runtimeText)
                        .modifier(HeroNumber(value: store.runtimeText))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(hasData ? "\(store.chargeText) · \(store.stateLabel)" : store.stateLabel)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: Circle())
            } else if hasData {
                Text(store.chargeText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Image(systemName: "shield.slash")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 6 s sine breath while charging — alive, never blinking.
    private func breathScale(at date: Date) -> CGFloat {
        guard store.isCharging, !reduceMotion else { return 1 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
        return 1 + 0.012 * sin(phase * 2 * .pi)
    }
}
