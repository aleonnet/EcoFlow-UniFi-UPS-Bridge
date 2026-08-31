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
    @State private var appeared = false
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

                // Entrance choreography: circles land first (staggered
                // springs), then the lines flash into existence.
                sideNode(
                    symbol: "bolt.horizontal.fill", label: "Rede elétrica",
                    value: gridActive ? "CA" : "—",
                    color: gridActive ? gridColor : .secondary, active: gridActive,
                    radius: sideRadius
                )
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .animation(.spring(duration: 0.45), value: appeared)
                .position(left.center)

                EnergyRing(store: store)
                    .frame(width: ringRadius * 2, height: ringRadius * 2)
                    .hoverLift(glow: accent, scale: 1.01)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.5)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .animation(.spring(duration: 0.5).delay(0.08), value: appeared)
                    .position(center.center)

                sideNode(
                    symbol: "server.rack", label: "Equipamentos",
                    value: store.powerText,
                    color: live ? gridColor : .secondary, active: live,
                    radius: sideRadius
                )
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .animation(.spring(duration: 0.45).delay(0.16), value: appeared)
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
            .onAppear { appeared = true }
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

// Straight lines with a birth choreography (owner 2026-08-31): the circles
// land first, then each line is REBORN as a laser flash sweeping start→end,
// and only then the energy pulses resume. Reactivating a segment (e.g.
// power restored) replays its flash.
private struct ConnectorLayer: View {
    struct Segment {
        let circles: (FlowGeometry.Circle, FlowGeometry.Circle)
        let active: Bool
        let color: Color
    }

    let segments: [Segment]
    let reduceMotion: Bool

    @State private var flashStart: [Int: Date] = [:]
    @State private var wasActive: [Int: Bool] = [:]

    private let flashDuration: TimeInterval = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            Canvas { canvas, _ in
                let now = context.date
                let travel = reduceMotion
                    ? 0.5
                    : now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
                for (index, segment) in segments.enumerated() {
                    guard let conn = FlowGeometry.connector(
                        from: segment.circles.0, to: segment.circles.1
                    ) else { continue }

                    var line = Path()
                    line.move(to: conn.start)
                    line.addLine(to: conn.end)

                    let flashElapsed = flashStart[index].map { now.timeIntervalSince($0) } ?? .infinity
                    // Not born yet: during the circles' entrance the line
                    // simply does not exist.
                    if segment.active && !reduceMotion && flashElapsed < 0 { continue }
                    let flashing = segment.active && !reduceMotion
                        && flashElapsed >= 0 && flashElapsed < flashDuration

                    if flashing {
                        // Laser rebirth: bright head sweeping left→right with
                        // an ease-out, trailing the settled line behind it.
                        let t = flashElapsed / flashDuration
                        let eased = 1 - pow(1 - t, 3)
                        let head = CGPoint(
                            x: conn.start.x + (conn.end.x - conn.start.x) * eased,
                            y: conn.start.y + (conn.end.y - conn.start.y) * eased
                        )
                        var swept = Path()
                        swept.move(to: conn.start)
                        swept.addLine(to: head)
                        var glow = canvas
                        glow.addFilter(.blur(radius: 4))
                        glow.stroke(swept, with: .color(segment.color.opacity(0.9)),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        canvas.stroke(swept, with: .color(.white.opacity(0.95)),
                                      style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        var headGlow = canvas
                        headGlow.addFilter(.blur(radius: 6))
                        headGlow.fill(
                            Path(ellipseIn: CGRect(x: head.x - 7, y: head.y - 7, width: 14, height: 14)),
                            with: .color(.white.opacity(0.9))
                        )
                        continue
                    }

                    canvas.stroke(
                        line,
                        with: .color(segment.active ? segment.color.opacity(0.55)
                                                    : Color.secondary.opacity(0.18)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    guard segment.active, flashElapsed >= flashDuration || reduceMotion else { continue }
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
        .onAppear {
            // Circles land first (FlowScene entrance ~0.5 s), then the lines
            // are born, staggered left→right.
            for index in segments.indices {
                flashStart[index] = Date().addingTimeInterval(0.55 + Double(index) * 0.18)
                wasActive[index] = segments[index].active
            }
        }
        .onChange(of: segments.map(\.active)) { _, actives in
            for (index, active) in actives.enumerated() {
                if active && wasActive[index] != true {
                    flashStart[index] = Date()   // reborn on reactivation
                }
                wasActive[index] = active
            }
        }
    }
}
