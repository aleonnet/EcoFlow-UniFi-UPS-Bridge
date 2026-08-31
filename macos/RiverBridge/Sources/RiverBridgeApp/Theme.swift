// Design tokens (plan: dark-first, semantic system colors + two accents).
// The palette shifts as a whole when power state changes — the signature.

import SwiftUI

enum Theme {
    // Accent when on line power: mint -> cyan ("energia limpa")
    static let onlineGradient = LinearGradient(
        colors: [Color(red: 0.22, green: 0.84, blue: 0.60), Color(red: 0.15, green: 0.65, blue: 0.90)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    // Accent on battery: amber -> deep orange ("reserva em uso")
    static let batteryGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.72, blue: 0.25), Color(red: 1.0, green: 0.45, blue: 0.20)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let lowBatteryGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.35, blue: 0.35), Color(red: 0.85, green: 0.15, blue: 0.25)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func accentGradient(onBattery: Bool, lowBattery: Bool) -> LinearGradient {
        if lowBattery { return lowBatteryGradient }
        return onBattery ? batteryGradient : onlineGradient
    }

    static func accentColor(onBattery: Bool, lowBattery: Bool) -> Color {
        if lowBattery { return Color(red: 1.0, green: 0.35, blue: 0.35) }
        return onBattery
            ? Color(red: 1.0, green: 0.62, blue: 0.22)
            : Color(red: 0.20, green: 0.78, blue: 0.70)
    }
}

extension Text {
    /// Uppercase tracked caption — the label voice of the whole app.
    func eyebrow() -> some View {
        self.font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundStyle(.secondary)
    }
}

/// Hero numbers roll instead of jumping (Reduce Motion respected upstream).
struct HeroNumber: ViewModifier {
    let value: String

    func body(content: Content) -> some View {
        content
            .font(.system(size: 44, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
