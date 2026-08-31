// Design tokens + atmosphere. The whole app breathes with the power state:
// the aurora background drifts mint on line power, amber on battery, red on
// low battery. Glass panels float above it (Liquid Glass, macOS 26).

import RiverBridgeCore
import SwiftUI

enum Theme {
    static let onlineColors = [
        Color(red: 0.20, green: 0.85, blue: 0.62),
        Color(red: 0.10, green: 0.60, blue: 0.95),
    ]
    static let batteryColors = [
        Color(red: 1.00, green: 0.72, blue: 0.25),
        Color(red: 1.00, green: 0.42, blue: 0.22),
    ]
    static let lowColors = [
        Color(red: 1.00, green: 0.36, blue: 0.36),
        Color(red: 0.80, green: 0.12, blue: 0.30),
    ]

    static func colors(onBattery: Bool, low: Bool) -> [Color] {
        low ? lowColors : (onBattery ? batteryColors : onlineColors)
    }

    static func accentGradient(onBattery: Bool, lowBattery: Bool) -> LinearGradient {
        LinearGradient(
            colors: colors(onBattery: onBattery, low: lowBattery),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func accentColor(onBattery: Bool, lowBattery: Bool) -> Color {
        colors(onBattery: onBattery, low: lowBattery)[0]
    }
}

// MARK: - Aurora atmosphere

/// Slow-drifting blurred light field behind the glass. Reduce Motion pins it.
struct AuroraBackground: View {
    var store: TelemetryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Restraint pass (owner's critique 2026-08-31): the aurora is an
        // ACCENT at the window's edges, never a wash — the neutral system
        // ground stays dominant so the glass reads as glass on top of it.
        let palette = Theme.colors(onBattery: store.isOnBattery, low: store.isLowBattery)
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 16
            Canvas { canvas, size in
                canvas.addFilter(.blur(radius: 95))
                blob(&canvas, size, palette[0].opacity(0.20),
                     cx: 0.12 + 0.06 * sin(t), cy: 0.10 + 0.05 * cos(t * 1.3), r: 0.38)
                blob(&canvas, size, palette[1].opacity(0.14),
                     cx: 0.92 + 0.05 * cos(t * 0.8), cy: 0.85 + 0.06 * sin(t * 1.1), r: 0.42)
                blob(&canvas, size, palette[0].opacity(0.09),
                     cx: 0.85 + 0.07 * sin(t * 0.6 + 2), cy: 0.10 + 0.04 * cos(t + 1), r: 0.26)
            }
            .background(scheme == .dark ? Color(white: 0.045) : Color(white: 0.94))
        }
        .animation(.easeInOut(duration: 1.2), value: store.isOnBattery)
        .ignoresSafeArea()
    }

    private func blob(_ canvas: inout GraphicsContext, _ size: CGSize, _ color: Color,
                      cx: Double, cy: Double, r: Double) {
        let radius = size.width * r
        let rect = CGRect(
            x: size.width * cx - radius / 2, y: size.height * cy - radius / 2,
            width: radius, height: radius
        )
        canvas.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

// MARK: - Glass panel

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(16)
            .glassEffect(.regular, in: shape)
            // Specular top edge + lift shadow: the contrast that makes glass
            // read as a pane instead of a tinted card.
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.05), .clear],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Type voice

extension Text {
    /// Uppercase tracked caption — the label voice of the whole app.
    func eyebrow() -> some View {
        self.font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .kerning(1.4)
            .foregroundStyle(.secondary)
    }
}

struct HeroNumber: ViewModifier {
    let value: String

    func body(content: Content) -> some View {
        content
            .font(.system(size: 46, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
