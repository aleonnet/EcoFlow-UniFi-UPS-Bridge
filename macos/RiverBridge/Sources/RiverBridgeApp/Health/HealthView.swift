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

    /// Um cartão por DISPOSITIVO protegido, com o nome que o usuário deu. Sai do
    /// registro, não de uma linha escrita à mão: o segundo plugin aparece aqui
    /// sem tocar nesta tela.
    private var pluginLinks: [Link] {
        DevicePluginRegistry.all.map { plugin in
            .init(id: plugin.id, symbol: plugin.symbol,
                  name: store.deviceNames.name(for: plugin) + L10n.t(" · proteção", " · protection"),
                  status: chain?.pluginDetail(id: plugin.id)?.state ?? chain?.udr7,
                  detail: udr7Detail)
        }
    }

    /// Honest one-liner for the protection card: source first, then warnings,
    /// then the ssh binary when it is not the system one (test seam visible).
    private var udr7Detail: String? {
        guard let d = chain?.udr7Detail else {
            return chain == nil ? nil : L10n.t("Serviço anterior à Fase 3'-EXP.", "Daemon predates Phase 3'-EXP.")
        }
        var parts: [String] = []
        if let source = d.source {
            let text: String = switch source {
            case "sintetica": L10n.t("fonte: telemetria sintética", "source: synthetic telemetry")
            case "nao_verificada": L10n.t("fonte: não verificada", "source: unverified")
            case "ok": L10n.t("fonte: River registrado", "source: registered River")
            default: "fonte: \(source)"
            }
            parts.append(text)
        }
        if let detail = d.sourceDetail, detail != "telemetria_sintetica" { parts.append(detail) }
        if let key = d.missingKey { parts.append(L10n.t("falta ", "missing ") + key) }
        if d.dryRun == true { parts.append(L10n.t("modo ensaio", "rehearsal mode")) }
        if let margin = d.marginEstimateS { parts.append(L10n.t("margem ≈ \(margin) s", "margin ≈ \(margin) s")) }
        for w in d.warnings ?? [] {
            switch w {
            case "lock_open": parts.append(L10n.t("trava aberta (UDR7_ARM_ALLOWED=1)", "lock open (UDR7_ARM_ALLOWED=1)"))
            case "charge_missing": parts.append(L10n.t("sem leitura de carga", "no charge reading"))
            case "margin_unknown": parts.append(L10n.t("margem desconhecida (taxa não medida)", "margin unknown (rate not measured)"))
            case "margin_short": parts.append(L10n.t("margem curta", "short margin"))
            case "cutoff_diverges": parts.append(L10n.t("charge.low do driver ≠ corte configurado", "driver charge.low ≠ configured cutoff"))
            case "read_only_no_effect": parts.append(L10n.t("READ_ONLY sem efeito", "READ_ONLY has no effect"))
            default: parts.append(w)
            }
        }
        if let bin = d.sshBinary, bin != "/usr/bin/ssh" { parts.append("ssh: " + bin) }
        if let last = d.lastEvent { parts.append(L10n.t("último: ", "last: ") + last) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
        .task { await store.refreshHealth() }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hoverLift(glow: color)
    }

    private func badge(_ status: String?) -> (String, Color) {
        switch status {
        case "ok": ("OK", .green)
        case "falha": (L10n.t("Falha", "Failed"), .red)
        case "sem_dados": (L10n.t("Sem dados", "No data"), .orange)
        case "nao_observavel": (L10n.t("Não observável", "Not observable"), .secondary)
        case "sem_caminho_nativo_documentado": (L10n.t("Sem caminho nativo documentado", "No documented native path"), .secondary)
        // Fase 3'-EXP — the closed enum of the `udr7` link (protect.py UDR7_STATES).
        case "desabilitado": (L10n.t("Desligada", "Off"), .secondary)
        case "dry_run": (L10n.t("Modo ensaio", "Rehearsal"), .blue)
        case "armado_nao_verificado": (L10n.t("Armada — alcance não verificado", "Armed — reach unverified"), .orange)
        case "enviado": (L10n.t("Desligamento enviado", "Shutdown sent"), .red)
        case "fonte_nao_real": (L10n.t("Bloqueada — fonte não aceita", "Blocked — source not accepted"), .purple)
        case "fonte_nao_local": (L10n.t("Bloqueada — NUT não é local", "Blocked — NUT not local"), .purple)
        case "corte_nao_configurado": (L10n.t("Bloqueada — corte não configurado", "Blocked — cutoff not set"), .purple)
        case "limiar_nao_configurado": (L10n.t("Bloqueada — limiar não configurado", "Blocked — threshold not set"), .purple)
        case "limiar_abaixo_do_corte": (L10n.t("Bloqueada — limiar ≤ corte+1", "Blocked — threshold ≤ cutoff+1"), .purple)
        case "config_incompleta": (L10n.t("Bloqueada — configuração incompleta", "Blocked — incomplete config"), .purple)
        case "chave_insegura": (L10n.t("Bloqueada — chave SSH ausente/insegura", "Blocked — SSH key missing/insecure"), .purple)
        case "host_desconhecido": (L10n.t("Bloqueada — host fora do known_hosts", "Blocked — host not in known_hosts"), .purple)
        case "calibrando": (L10n.t("Bloqueada — calibrando", "Blocked — calibrating"), .purple)
        case "armamento_ausente": (L10n.t("Bloqueada — armamento ausente", "Blocked — arming file missing"), .purple)
        case "config_trocada": (L10n.t("Bloqueada — configuração mudou após armar", "Blocked — config changed after arming"), .purple)
        case "aguardando_restauracao": (L10n.t("Aguardando energia voltar", "Waiting for power to return"), .orange)
        default: ("—", .secondary)
        }
    }
}
