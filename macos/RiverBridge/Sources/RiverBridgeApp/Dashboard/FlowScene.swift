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
            // The ring BAND is drawn 8pt inside its frame (EnergyRing inset);
            // anchoring at the frame radius left a visible gap (owner's
            // print). Anchor at the visual band edge, tucked 2pt under it.
            let centerAnchor = FlowGeometry.Circle(
                center: center.center, radius: ringRadius - 10
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
                        .init(circles: (left, centerAnchor), active: gridActive, color: accent),
                        .init(circles: (centerAnchor, right), active: live, color: accent),
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
            // No implicit animation on geometry: during a live resize the
            // nodes track every frame and the Canvas lines stay GLUED to the
            // circle edges (a spring here made them detach — owner's report).
        }
        // Height follows the MEASURED width (never negotiates a wider frame —
        // aspectRatio + minHeight overflowed the window edge, seen on screen).
        .frame(height: sceneHeight)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // Compact (phone) stacks vertically; 400 keeps the bottom node
            // (center at h−48, edge at ~392) INSIDE the min-window viewport —
            // 430 clipped the Equipamentos circle (owner's print, 414pt).
            sceneHeight = width < 520 ? 400 : min(max(width / 2.7, 280), 430)
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

// Straight connectors, no entrance theatrics (owner 2026-08-31: keep only
// the responsiveness). Line + traveling energy pulses; inactive paths dim.
private struct ConnectorLayer: View {
    struct Segment {
        let circles: (FlowGeometry.Circle, FlowGeometry.Circle)
        let active: Bool
        let color: Color
    }

    let segments: [Segment]
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || segments.allSatisfy { !$0.active })) { context in
            Canvas { canvas, _ in
                let travel = reduceMotion
                    ? 0.5
                    : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
                for segment in segments {
                    guard let conn = FlowGeometry.connector(
                        from: segment.circles.0, to: segment.circles.1
                    ) else { continue }

                    var line = Path()
                    line.move(to: conn.start)
                    line.addLine(to: conn.end)
                    if segment.active {
                        // The ring's glow language on the lines too (owner):
                        // a wide blurred pass under the crisp stroke.
                        var glow = canvas
                        glow.addFilter(.blur(radius: 5))
                        glow.stroke(line, with: .color(segment.color.opacity(0.45)),
                                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    }
                    canvas.stroke(
                        line,
                        with: .color(segment.active ? segment.color.opacity(0.75)
                                                    : Color.secondary.opacity(0.18)),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                    guard segment.active else { continue }
                    for i in 0..<3 {
                        let phase = (travel + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        let p = CGPoint(
                            x: conn.start.x + (conn.end.x - conn.start.x) * phase,
                            y: conn.start.y + (conn.end.y - conn.start.y) * phase
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
