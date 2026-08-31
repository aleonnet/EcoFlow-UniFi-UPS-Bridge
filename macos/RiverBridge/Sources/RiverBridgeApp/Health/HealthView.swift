// Chain health: USB -> NUT -> serviço -> UniFi / HA. Links we cannot see
// yet say so honestly ("não observável", "pendente") — never a green dot
// without evidence. Layout: adaptive glass cards filling the page
// (owner 2026-08-31: distribute the space, hover, responsive).

import RiverBridgeCore
import SwiftUI

struct HealthView: View {
    var store: TelemetryStore

    @State private var chain: HealthChain?

    private struct Link: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let status: String?
        let detail: String?
    }

    private var links: [Link] {
        [
            .init(id: "usb", symbol: "cable.connector", name: "USB · RIVER",
                  status: chain?.usb,
                  detail: "Observável a partir da Fase 1, com o RIVER conectado."),
            .init(id: "nut", symbol: "server.rack", name: "NUT (upsd)",
                  status: chain?.nut, detail: chain?.lastError),
            .init(id: "bridge", symbol: "gearshape.2.fill", name: "Serviço river-unifi-bridge",
                  status: store.phase == .live ? "ok" : "falha",
                  detail: store.phase == .live ? "API local respondendo." : "A UI não alcança a API local."),
            .init(id: "unifi", symbol: "network", name: "UniFi (UDR7)",
                  status: chain?.unifi, detail: "Aguarda a Fase 3 (PoC do protocolo)."),
            .init(id: "ha", symbol: "house.fill", name: "Home Assistant",
                  status: chain?.ha, detail: "O upsd não expõe clientes de forma confirmada ainda."),
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
                    Text("Cadeia de integração").eyebrow()
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
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            // Inner breathing room so the hover glow fits INSIDE the clip.
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
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
        case "falha": ("Falha", .red)
        case "sem_dados": ("Sem dados", .orange)
        case "pendente_fase_3": ("Pendente — Fase 3", .secondary)
        case "nao_observavel": ("Não observável", .secondary)
        default: ("—", .secondary)
        }
    }
}
