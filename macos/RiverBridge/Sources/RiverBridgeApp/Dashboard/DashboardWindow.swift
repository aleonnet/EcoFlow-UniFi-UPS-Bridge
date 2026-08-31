// v5 "Central de Energia": glass side rail (UniFi pattern), the power flow
// as the central hero, full-width dense chart. Glass lives ONLY on the
// control layer; content sits directly on the near-black ground.

import RiverBridgeCore
import SwiftUI

struct DashboardWindow: View {
    var store: TelemetryStore
    @State private var section: Section = .energia
    @Namespace private var railNS

    enum Section: String, CaseIterable, Identifiable {
        case energia = "Energia"
        case saude = "Saúde"
        case ajustes = "Ajustes"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .energia: "bolt.fill"
            case .saude: "waveform.path.ecg"
            case .ajustes: "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground(store: store)

            VStack(spacing: 10) {
                // Nav lives in the hidden-title-bar dead strip: zero useful
                // height spent (owner's call 2026-08-31 — top over side rail,
                // and the same capsule becomes a bottom tab bar on iPhone).
                header

                Group {
                    switch section {
                    case .energia: EnergiaSection(store: store)
                    case .saude: HealthView(store: store)
                    case .ajustes: SettingsView(store: store)
                    }
                }
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .animation(.snappy(duration: 0.3), value: section)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        Theme.accentGradient(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
                    )
                Text("River Bridge")
                    .font(.system(.headline, design: .rounded))
            }
            .padding(.leading, 86)   // clears the traffic lights

            Spacer()

            HStack(spacing: 2) {
                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.system(.callout, design: .rounded)
                                .weight(section == item ? .semibold : .regular))
                            .foregroundStyle(section == item ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if section == item {
                            Capsule()
                                .fill(.primary.opacity(0.14))
                                .matchedGeometryEffect(id: "rail-sel", in: railNS)
                        }
                    }
                    .accessibilityLabel(item.rawValue)
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.trailing, 18)
        }
        .padding(.top, 10)
    }

}

// Energia = hero flow + dense chart + compact events, all on the ground.
struct EnergiaSection: View {
    var store: TelemetryStore

    var body: some View {
        // Scroll instead of clip: at the minimum window size every element
        // stays reachable — nothing is ever cut off.
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if case .serviceDown(let reason) = store.phase {
                    ConnectionBanner(reason: reason)
                }
                FlowScene(store: store)
                ChartsView(store: store)
                EventsTimeline(store: store)
            }
            .padding(.bottom, 8)
        }
    }
}

struct ConnectionBanner: View {
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Serviço parado").font(.headline)
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
