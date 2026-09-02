// O UDR7 como plugin de TELA: o detalhe honesto do cartão de saúde e os estados
// que só este dispositivo conhece. Sem estado armazenado — nada que chame
// L10n.t na inicialização, que congelaria o idioma.

import RiverBridgeCore
import SwiftUI

struct Udr7Plugin: DevicePluginUI {
    var descriptor: DevicePluginDescriptor { .udr7 }

    func settingsSheet(store: TelemetryStore, hostSize: CGSize,
                       onClose: @escaping () -> Void) -> AnyView {
        AnyView(Udr7SettingsSheet(store: store, hostSize: hostSize, onClose: onClose))
    }

    func healthDetail(chain: HealthChain?) -> String? {
        guard let d = chain?.pluginDetail(id: descriptor.id) else {
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

    /// Os estados que SÓ este dispositivo conhece (protect.py UDR7_STATES).
    /// `nil` para o que não reconhece: o cartão cai no badge genérico, que
    /// continua servindo os outros cinco elos da cadeia.
    func badge(state: String?) -> (String, Color)? {
        switch state {
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
        default: nil
        }
    }
}
