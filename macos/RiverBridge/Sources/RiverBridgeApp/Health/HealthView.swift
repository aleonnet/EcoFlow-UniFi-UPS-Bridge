// Chain health: USB -> NUT -> serviço -> UniFi / HA. Links we cannot see
// yet say so honestly ("não observável", "pendente") — never a green dot
// without evidence. Layout: adaptive glass cards filling the page
// (owner 2026-08-31: distribute the space, hover, responsive).

import RiverBridgeCore
import SwiftUI

struct HealthView: View {
    var store: TelemetryStore

    @State private var scrollOffset: CGFloat = 0

    /// Vem do store: fonte ÚNICA do health. Antes esta tela tinha o próprio poll
    /// de 5 s, então o nome do dispositivo e o estado podiam divergir do resto do
    /// app. Mudança declarada: o poll passa a viver com o app, não com a tela.
    private var chain: HealthChain? { store.health }

    private struct Link: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let status: String?
        let detail: String?
        /// O TIPO do dispositivo quando o elo é uma instância protegida; nil nos
        /// cinco elos da cadeia. É o que escolhe o badge específico.
        var typeID: String? = nil
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
            .init(id: "unifi", symbol: "network", name: L10n.t("UniFi · visibilidade", "UniFi · visibility"),
                  status: chain?.unifi,
                  detail: L10n.t("Nenhum caminho nativo documentado para o console consumir um UPS de terceiros (pesquisa 2026-08-31).",
                                 "No documented native path for the console to consume a third-party UPS (research 2026-08-31).")),
            .init(id: "ha", symbol: "house.fill", name: "Home Assistant",
                  status: chain?.ha, detail: L10n.t("O upsd não expõe clientes de forma confirmada ainda.", "upsd does not confirmably expose clients yet.")),
        ] + pluginLinks
    }

    /// Um cartão por INSTÂNCIA protegida, com o nome que o usuário deu. Sai da
    /// lista de instâncias, não de uma linha escrita à mão: um dispositivo novo
    /// aparece aqui sem tocar nesta tela. Só a instância migrada `udr7` tem o
    /// alias `udr7`/`udr7_detail` como reforço.
    private var pluginLinks: [Link] {
        let labels = DeviceNames.uniqueLabels(instances: store.devices)
        return store.devices.map { instance in
            let type = DeviceTypeRegistry.type(id: instance.type)
            let detail = chain?.pluginDetail(id: instance.id)
            return .init(id: instance.id, symbol: type?.symbol ?? "shield.lefthalf.filled",
                         name: (labels[instance.id] ?? instance.name) + L10n.t(" · proteção", " · protection"),
                         status: detail?.state ?? instance.state,
                         detail: DevicePluginUIRegistry.plugin(typeID: instance.type)?
                             .healthDetail(detail: detail, chainPresent: chain != nil),
                         typeID: instance.type)
        }
    }

    /// Honest one-liner for the protection card: source first, then warnings,
    /// then the ssh binary when it is not the system one (test seam visible).
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
            // Full-bleed scroll + padded content (gradient-seam class fix);
            // 24 also keeps the hover glow inside the clip.
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, offset in
            scrollOffset = offset
        }
        .task {
            await store.refreshDevices()
            await store.refreshHealth()
        }
    }

    private func card(_ item: Link) -> some View {
        // O tipo do elo existe quando o elo É um dispositivo: assim o badge
        // específico entra e o genérico continua servindo os outros cinco.
        let (label, color) = badge(item.status, typeID: item.typeID)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hoverLift(glow: color)
    }

    /// Badge GENÉRICO dos elos da cadeia. Os estados que só um dispositivo
    /// conhece vêm do plugin — este switch não os enumera mais.
    private func badge(_ status: String?, typeID: String? = nil) -> (String, Color) {
        if let typeID, let doPlugin = DevicePluginUIRegistry.plugin(typeID: typeID)?.badge(state: status) {
            return doPlugin
        }
        switch status {
        case "ok": return ("OK", .green)
        case "falha": return (L10n.t("Falha", "Failed"), .red)
        case "sem_dados": return (L10n.t("Sem dados", "No data"), .orange)
        case "nao_observavel": return (L10n.t("Não observável", "Not observable"), .secondary)
        case "sem_caminho_nativo_documentado":
            return (L10n.t("Sem caminho nativo documentado", "No documented native path"), .secondary)
        default: return ("—", .secondary)
        }
    }
}
