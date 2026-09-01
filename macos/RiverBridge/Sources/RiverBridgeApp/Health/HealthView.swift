// Chain health: USB -> NUT -> serviço -> UniFi / HA. Links we cannot see
// yet say so honestly ("não observável", "pendente") — never a green dot
// without evidence. Layout: adaptive glass cards filling the page
// (owner 2026-08-31: distribute the space, hover, responsive).

import RiverBridgeCore
import SwiftUI

struct HealthView: View {
    var store: TelemetryStore

    @State private var chain: HealthChain?
    @State private var scrollOffset: CGFloat = 0

    private struct Link: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let status: String?
        let detail: String?
    }

    private var links: [Link] {
        [
            .init(id: "usb", symbol: "cable.connector", name: L10n.t("USB · RIVER", "USB · RIVER"),
                  status: chain?.usb,
                  detail: L10n.t("Observável a partir da Fase 1, com o RIVER conectado.", "Observable from Phase 1, with the RIVER connected.")),
            .init(id: "nut", symbol: "server.rack", name: "NUT (upsd)",
                  status: chain?.nut, detail: chain?.lastError),
            .init(id: "bridge", symbol: "gearshape.2.fill", name: L10n.t("Serviço river-unifi-bridge", "river-unifi-bridge service"),
                  status: store.phase == .live ? "ok" : "falha",
                  detail: store.phase == .live ? L10n.t("API local respondendo.", "Local API responding.") : L10n.t("A UI não alcança a API local.", "The UI can’t reach the local API.")),
            .init(id: "unifi", symbol: "network", name: "UniFi (UDR7)",
                  status: chain?.unifi, detail: L10n.t("Aguarda a Fase 3 (PoC do protocolo).", "Waits for Phase 3 (protocol PoC).")),
            .init(id: "ha", symbol: "house.fill", name: "Home Assistant",
                  status: chain?.ha, detail: L10n.t("O upsd não expõe clientes de forma confirmada ainda.", "upsd does not confirmably expose clients yet.")),
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // STICKY section header (owner 2026-08-31): the eyebrow pins to
            // the top of the scroll and the cards pass UNDER it — never over.
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                Section {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 330), spacing: 14)],
                        alignment: .leading, spacing: 14
                    ) {
                        ForEach(links) { item in
                            card(item)
                        }
                    }
                } header: {
                    Text(L10n.t("Cadeia de integração", "Integration chain")).eyebrow()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .background {
                            // Transparent at rest; material only while
                            // content actually passes underneath (validated
                            // onScrollGeometryChange pattern).
                            Rectangle().fill(.ultraThinMaterial)
                                .mask {
                                    LinearGradient(colors: [.black, .black, .clear],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                                .opacity(scrollOffset > 4 ? 1 : 0)
                                .animation(.easeInOut(duration: 0.15), value: scrollOffset > 4)
                        }
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            // Inner breathing room so the hover glow fits INSIDE the clip.
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, offset in
            scrollOffset = offset
        }
        .task {
            while !Task.isCancelled {
                if let endpoint = ApiEndpoint.discover() {
                    chain = try? await APIClient(endpoint: endpoint).health()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func card(_ item: Link) -> some View {
        let (label, color) = badge(item.status)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.quaternary.opacity(0.5), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.system(.headline, design: .rounded))
                Text(label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hoverLift(glow: color)
    }

    private func badge(_ status: String?) -> (String, Color) {
        switch status {
        case "ok": ("OK", .green)
        case "falha": (L10n.t("Falha", "Failed"), .red)
        case "sem_dados": (L10n.t("Sem dados", "No data"), .orange)
        case "pendente_fase_3": (L10n.t("Pendente — Fase 3", "Pending — Phase 3"), .secondary)
        case "nao_observavel": (L10n.t("Não observável", "Not observable"), .secondary)
        default: ("—", .secondary)
        }
    }
}
