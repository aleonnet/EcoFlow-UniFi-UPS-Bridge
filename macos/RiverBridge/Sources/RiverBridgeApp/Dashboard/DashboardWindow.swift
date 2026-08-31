// Main window: aurora atmosphere behind, glass panels above. Navigation is
// a glass capsule (Energia / Saúde / Ajustes) instead of stock tabs — the
// window IS the product's mood, not chrome around it.

import RiverBridgeCore
import SwiftUI

struct DashboardWindow: View {
    var store: TelemetryStore
    @State private var section: Section = .energia
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            VStack(spacing: 14) {
                header

                Group {
                    switch section {
                    case .energia: DashboardView(store: store)
                    case .saude: HealthView(store: store)
                    case .ajustes: SettingsView(store: store)
                    }
                }
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.top, 40)   // clears the hidden title bar traffic lights
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .animation(.snappy(duration: 0.3), value: section)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "bolt.shield.fill")
                    .font(.title3)
                    .foregroundStyle(
                        Theme.accentGradient(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
                    )
                Text("River Bridge")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
            }
            Spacer()
            GlassEffectContainer {
                HStack(spacing: 2) {
                    ForEach(Section.allCases) { item in
                        Button {
                            section = item
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .labelStyle(.titleAndIcon)
                                .font(.callout.weight(section == item ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background {
                            if section == item {
                                Capsule().fill(.primary.opacity(0.12))
                            }
                        }
                    }
                }
                .padding(3)
                .glassEffect(.regular, in: Capsule())
            }
        }
    }
}

struct DashboardView: View {
    var store: TelemetryStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 18) {
                EnergyRing(store: store)
                    .frame(width: 250, height: 250)
                    .padding(.vertical, 10)
                PowerFlowView(store: store)
            }
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 26)
            .frame(width: 330)

            VStack(alignment: .leading, spacing: 14) {
                if case .serviceDown(let reason) = store.phase {
                    ConnectionBanner(reason: reason)
                }
                StatsGrid(store: store)
                ChartsView(store: store)
                    .glassCard()
                EventsTimeline(store: store)
                    .glassCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .glassCard(cornerRadius: 14)
        .tint(.orange)
    }
}

struct StatsGrid: View {
    var store: TelemetryStore

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(label: "Carga", value: store.powerText, symbol: "bolt.fill")
                StatTile(label: "Uso", value: store.loadText, symbol: "gauge.with.needle")
                StatTile(label: "Saída", value: store.outputVoltageText, symbol: "powerplug.fill")
            }
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label).eyebrow()
            }
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
