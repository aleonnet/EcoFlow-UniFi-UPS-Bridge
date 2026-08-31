// Chain health: USB -> NUT -> serviço -> UniFi / HA. Links we cannot see
// yet say so honestly ("não observável", "pendente") — never a green dot
// without evidence.

import RiverBridgeCore
import SwiftUI

struct HealthView: View {
    var store: TelemetryStore

    @State private var chain: HealthChain?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cadeia de integração").eyebrow()

            link(
                "cable.connector", "USB · RIVER",
                status: chain?.usb, detail: "Observável a partir da Fase 1, com o RIVER conectado."
            )
            link(
                "server.rack", "NUT (upsd)",
                status: chain?.nut, detail: chain?.lastError
            )
            link(
                "gearshape.2.fill", "Serviço river-unifi-bridge",
                status: store.phase == .live ? "ok" : "falha",
                detail: store.phase == .live ? nil : "A UI não alcança a API local."
            )
            link(
                "network", "UniFi (UDR7)",
                status: chain?.unifi, detail: "Aguarda a Fase 3 (PoC do protocolo)."
            )
            link(
                "house.fill", "Home Assistant",
                status: chain?.ha, detail: "O upsd não expõe clientes de forma confirmada ainda."
            )
            Spacer()
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
        .task {
            while !Task.isCancelled {
                if let endpoint = ApiEndpoint.discover() {
                    chain = try? await APIClient(endpoint: endpoint).health()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func link(_ symbol: String, _ name: String, status: String?, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.5), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name).font(.headline)
                    statusBadge(status)
                }
                if let detail, !detail.isEmpty {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String?) -> some View {
        let (label, color): (String, Color) = switch status {
        case "ok": ("OK", .green)
        case "falha": ("Falha", .red)
        case "sem_dados": ("Sem dados", .orange)
        case "pendente_fase_3": ("Pendente — Fase 3", .secondary)
        case "nao_observavel": ("Não observável", .secondary)
        default: ("—", .secondary)
        }
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
