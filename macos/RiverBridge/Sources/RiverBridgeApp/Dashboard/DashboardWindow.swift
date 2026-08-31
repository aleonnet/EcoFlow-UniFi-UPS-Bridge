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

            HStack(spacing: 0) {
                rail
                    .padding(.leading, 14)
                    .padding(.trailing, 6)

                Group {
                    switch section {
                    case .energia: EnergiaSection(store: store)
                    case .saude: HealthView(store: store)
                    case .ajustes: SettingsView(store: store)
                    }
                }
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.top, 42)
                .padding(.bottom, 16)
            }
        }
        .animation(.snappy(duration: 0.3), value: section)
    }

    // Glass rail — the control layer (UniFi-style icon column). The capsule
    // hugs its icons (fixed intrinsic height, pinned to the top): a growing
    // Spacer INSIDE the glass made it stretch and dance with the window.
    private var rail: some View {
        VStack {
            VStack(spacing: 6) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        Theme.accentGradient(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
                    )
                    .padding(.bottom, 14)

                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(section == item ? .primary : .secondary)
                            .frame(width: 38, height: 38)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if section == item {
                            Circle()
                                .fill(.primary.opacity(0.14))
                                .matchedGeometryEffect(id: "rail-sel", in: railNS)
                        }
                    }
                    .help(item.rawValue)
                    .accessibilityLabel(item.rawValue)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .fixedSize()
            .glassEffect(.regular.interactive(), in: Capsule())

            Spacer(minLength: 0)
        }
        .padding(.top, 44)
        .frame(width: 64)
    }
}

// Energia = hero flow + dense chart + compact events, all on the ground.
struct EnergiaSection: View {
    var store: TelemetryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .serviceDown(let reason) = store.phase {
                ConnectionBanner(reason: reason)
            }
            FlowScene(store: store)
            ChartsView(store: store)
            EventsTimeline(store: store)
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
