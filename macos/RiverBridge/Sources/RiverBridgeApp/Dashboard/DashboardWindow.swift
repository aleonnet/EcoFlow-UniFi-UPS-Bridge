// v5 "Central de Energia": glass side rail (UniFi pattern), the power flow
// as the central hero, full-width dense chart. Glass lives ONLY on the
// control layer; content sits directly on the near-black ground.

import RiverBridgeCore
import SwiftUI

struct DashboardWindow: View {
    var store: TelemetryStore
    @State private var section: Section = DashboardWindow.initialSection()
    @State private var headerWidth: CGFloat = 1000
    @State private var beatPulse = false
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

    // Adaptive tab capsule following the system's own floating tab bar
    // convention (owner 2026-08-31): when narrow, the SELECTED tab keeps
    // icon+label and the others collapse to icon-only with a tooltip.
    private var header: some View {
        let accent = Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
        return HStack {
            HStack(spacing: 9) {
                // The logo BEATS with the data: each applied SSE reading
                // (store.beat) fires one systole/diastole — a live pulse,
                // not a decorative loop (owner 2026-08-31).
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        Theme.accentGradient(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
                    )
                    .scaleEffect(beatPulse ? 1.12 : 1.0)
                    .shadow(color: accent.opacity(beatPulse ? 0.75 : 0.25),
                            radius: beatPulse ? 11 : 4)
                if headerWidth >= 560 {
                    Text("River Bridge")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                }
            }
            .padding(.leading, 72)   // clears the traffic lights

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
        .onChange(of: store.beat) {
            withAnimation(.easeOut(duration: 0.12)) { beatPulse = true }
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: 0.5)) { beatPulse = false }
            }
        }
    }

}

// Energia = hero flow + dense chart + compact events, all on the ground.
struct EnergiaSection: View {
    var store: TelemetryStore
    @State private var scrollOffset: CGFloat = 0
    @State private var headerMinY: CGFloat = 1000
    @State private var eventChips: Set<EventChip> = []
    @State private var eventPeriod: EventPeriod = .tudo
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var customTo = Date.now

    // Validated pattern (onScrollGeometryChange, macOS 15+): the header is
    // TRANSPARENT at rest; material fades in ONLY while it is pinned with
    // content passing underneath — never a visible band on a still page.
    private var headerLit: Bool { scrollOffset > 4 && headerMinY <= 1 }

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
                    EventsTimeline(store: store, chips: eventChips, period: eventPeriod,
                                   customFrom: customFrom, customTo: customTo)
                } header: {
                    EventsFilterBar(chips: $eventChips, period: $eventPeriod,
                                    customFrom: $customFrom, customTo: $customTo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .background {
                            Rectangle().fill(.ultraThinMaterial)
                                .mask {
                                    LinearGradient(colors: [.black, .black, .clear],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                                .opacity(headerLit ? 1 : 0)
                                .animation(.easeInOut(duration: 0.15), value: headerLit)
                        }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .scrollView).minY
                        } action: { minY in
                            headerMinY = minY
                        }
                }
            }
            .padding(.bottom, 8)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, offset in
            scrollOffset = offset
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
