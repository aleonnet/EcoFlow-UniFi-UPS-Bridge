// v5 "Central de Energia": glass side rail (UniFi pattern), the power flow
// as the central hero, full-width dense chart. Glass lives ONLY on the
// control layer; content sits directly on the near-black ground.

import RiverBridgeCore
import SwiftUI

struct DashboardWindow: View {
    var store: TelemetryStore
    @State private var section: Section = DashboardWindow.initialSection()
    @State private var headerWidth: CGFloat = 1000
    @Namespace private var railNS

    /// Dev seam: `--secao saude|ajustes` opens on that tab (screenshot
    /// validation); normal launches always start on Energia.
    static func initialSection() -> Section {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--secao"), index + 1 < args.count {
            switch args[index + 1] {
            case "saude": return .saude
            case "ajustes": return .ajustes
            default: break
            }
        }
        return .energia
    }

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
                // STICKY: a blurred band pinned to the top edge — scrolled
                // content passes under glass, never over the logo/tabs.
                header
                    .padding(.bottom, 6)
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .mask {
                                LinearGradient(
                                    colors: [.black, .black, .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                            }
                            .ignoresSafeArea(edges: .top)
                    }

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

    // Adaptive tab capsule following the system's own floating tab bar
    // convention (owner 2026-08-31): when narrow, the SELECTED tab keeps
    // icon+label and the others collapse to icon-only with a tooltip.
    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        Theme.accentGradient(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
                    )
                if headerWidth >= 560 {
                    Text("River Bridge")
                        .font(.system(.headline, design: .rounded))
                }
            }
            .padding(.leading, 86)   // clears the traffic lights

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                ForEach(Section.allCases) { item in
                    let isSelected = section == item
                    let showsLabel = headerWidth >= 700 || isSelected
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol)
                            if showsLabel {
                                Text(item.rawValue)
                                    .fixedSize()
                            }
                        }
                        .font(.system(.callout, design: .rounded)
                            .weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, showsLabel ? 14 : 11)
                        .padding(.vertical, 7)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.primary.opacity(0.14))
                                .matchedGeometryEffect(id: "rail-sel", in: railNS)
                        }
                    }
                    .help(item.rawValue)
                    .accessibilityLabel(item.rawValue)
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.trailing, 18)
        }
        .padding(.top, 10)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            headerWidth = width
        }
        .animation(.snappy(duration: 0.25), value: headerWidth >= 700)
    }

}

// Energia = hero flow + dense chart + compact events, all on the ground.
struct EnergiaSection: View {
    var store: TelemetryStore

    var body: some View {
        // Single scroll, no nested scrolling (UX smell): the EVENTOS eyebrow
        // pins at the top while rows pass under — same pattern as Saúde.
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                Section {
                    if case .serviceDown(let reason) = store.phase {
                        ConnectionBanner(reason: reason)
                    }
                    FlowScene(store: store)
                    ChartsView(store: store)
                }
                Section {
                    EventsTimeline(store: store)
                } header: {
                    Text("Eventos").eyebrow()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .background {
                            Rectangle().fill(.ultraThinMaterial)
                                .mask {
                                    LinearGradient(colors: [.black, .black, .clear],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                        }
                }
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
