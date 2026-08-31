// The hero: Tesla-style power flow with the RIVER's energy ring as the
// CENTRAL node. One scene owns every node position and draws connectors
// with FlowGeometry anchors — lines are born and die on circle edges by
// proved construction, never by eye.
//
// Semantics (owner, 2026-08-31): left node is the ELECTRICAL grid
// (rede elétrica), right node is the protected equipment — never internet.

import RiverBridgeCore
import SwiftUI

struct FlowScene: View {
    var store: TelemetryStore

    @State private var sceneHeight: CGFloat = 330
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }
    private var live: Bool { store.phase == .live }
    private var gridActive: Bool { live && !store.isOnBattery }
    private let gridColor = Color(red: 0.45, green: 0.75, blue: 1.0)

    var body: some View {
        GeometryReader { geo in
            // Compact widths (iPhone-class, narrow windows) stack the flow
            // vertically; FlowGeometry anchors are axis-agnostic and proved.
            let compact = geo.size.width < 520
            // Owner's ask (2026-08-31): the widgets scale with the window.
            // Radii derive from the AVAILABLE space, spring-animated below.
            let ringRadius: CGFloat = min(max(min(geo.size.width * 0.14, geo.size.height * 0.42), 92), 168)
            let sideRadius: CGFloat = max(ringRadius * 0.40, 40)
            let cy = geo.size.height / 2 - (compact ? 0 : 14)
            let cx = geo.size.width / 2
            let left = FlowGeometry.Circle(
                center: compact
                    ? .init(x: cx, y: sideRadius + 8)
                    : .init(x: sideRadius + 24, y: cy),
                radius: sideRadius
            )
            let center = FlowGeometry.Circle(
                center: .init(x: cx, y: cy), radius: ringRadius
            )
            let right = FlowGeometry.Circle(
                center: compact
                    ? .init(x: cx, y: geo.size.height - sideRadius - 8)
                    : .init(x: geo.size.width - sideRadius - 24, y: cy),
                radius: sideRadius
            )

            ZStack {
                // Connectors first (under the nodes), anchored edge-to-edge.
                ConnectorLayer(
                    segments: [
                        .init(circles: (left, center), active: gridActive, color: accent),
                        .init(circles: (center, right), active: live, color: accent),
                    ],
                    reduceMotion: reduceMotion
                )

                sideNode(
                    symbol: "bolt.horizontal.fill", label: "Rede elétrica",
                    value: gridActive ? "CA" : "—",
                    color: gridActive ? gridColor : .secondary, active: gridActive,
                    radius: sideRadius
                )
                .position(left.center)

                EnergyRing(store: store)
                    .frame(width: ringRadius * 2, height: ringRadius * 2)
                    .hoverLift(glow: accent, scale: 1.01)
                    .position(center.center)

                sideNode(
                    symbol: "server.rack", label: "Equipamentos",
                    value: store.powerText,
                    color: live ? gridColor : .secondary, active: live,
                    radius: sideRadius
                )
                .position(right.center)

                // Labels outside the circles: below in wide mode, beside in
                // compact (below would collide with the vertical connector).
                Text("Rede elétrica").eyebrow()
                    .position(
                        x: compact ? left.center.x + sideRadius + 70 : left.center.x,
                        y: compact ? left.center.y : left.center.y + sideRadius + 16
                    )
                Text("Equipamentos").eyebrow()
                    .position(
                        x: compact ? right.center.x + sideRadius + 70 : right.center.x,
                        y: compact ? right.center.y : right.center.y + sideRadius + 16
                    )
            }
            .animation(.spring(duration: 0.5), value: geo.size)
        }
        // Height follows the MEASURED width (never negotiates a wider frame —
        // aspectRatio + minHeight overflowed the window edge, seen on screen).
        .frame(height: sceneHeight)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            sceneHeight = min(max(width / 2.7, 280), 430)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            store.isOnBattery
                ? "Equipamentos alimentados pela bateria do RIVER, \(store.runtimeText) de autonomia"
                : "Equipamentos alimentados pela rede elétrica através do RIVER"
        )
    }

    private func sideNode(symbol: String, label: String, value: String,
                          color: Color, active: Bool, radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(active ? 0.9 : 0.3), lineWidth: 2)
                .shadow(color: color.opacity(active ? 0.7 : 0), radius: 7)
                .shadow(color: color.opacity(active ? 0.35 : 0), radius: 16)
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: radius * 0.42, weight: .medium))
                    .foregroundStyle(active ? .primary : .secondary)
                Text(value)
                    .font(.system(size: max(radius * 0.24, 10), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .hoverLift(glow: color, scale: 1.04)
        .animation(.easeInOut(duration: 0.6), value: active)
    }
}

// Cables, not wires (owner 2026-08-31): each connector is a quadratic
// bezier that HANGS like a real cable, sways almost imperceptibly, and the
// energy pulses travel ALONG the curve (FlowGeometry.quadPoint — tested).
private struct ConnectorLayer: View {
    struct Segment {
        let circles: (FlowGeometry.Circle, FlowGeometry.Circle)
        let active: Bool
        let color: Color
    }

    let segments: [Segment]
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            Canvas { canvas, _ in
                let now = context.date.timeIntervalSinceReferenceDate
                let travel = reduceMotion ? 0.5 : now.truncatingRemainder(dividingBy: 2.2) / 2.2
                for (index, segment) in segments.enumerated() {
                    guard let conn = FlowGeometry.connector(
                        from: segment.circles.0, to: segment.circles.1
                    ) else { continue }
                    let span = abs(conn.end.x - conn.start.x) + abs(conn.end.y - conn.start.y)
                    // Organic: the sag breathes ±2pt slowly, out of phase per cable.
                    let baseSag = max(span * 0.06, 10)
                    let sway = reduceMotion ? 0 : sin(now / 3.1 + Double(index) * 1.7) * 2.0
                    let control = FlowGeometry.cableControl(
                        start: conn.start, end: conn.end, sag: baseSag + sway
                    )

                    var cable = Path()
                    cable.move(to: conn.start)
                    cable.addQuadCurve(to: conn.end, control: control)
                    canvas.stroke(
                        cable,
                        with: .color(segment.active ? segment.color.opacity(0.55)
                                                    : Color.secondary.opacity(0.18)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    guard segment.active else { continue }
                    for i in 0..<3 {
                        let phase = (travel + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        let p = FlowGeometry.quadPoint(
                            start: conn.start, control: control, end: conn.end, t: phase
                        )
                        var halo = canvas
                        halo.addFilter(.blur(radius: 3))
                        halo.fill(
                            Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                            with: .color(segment.color.opacity(0.7))
                        )
                        canvas.fill(
                            Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)),
                            with: .color(.white.opacity(0.95))
                        )
                    }
                }
            }
        }
    }
}
