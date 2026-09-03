// O Console UniFi (UDR7) como plugin de TELA: a folha da instância, o detalhe
// honesto do cartão de saúde e os estados que o motor SSH conhece. Sem estado
// armazenado — nada que chame L10n.t na inicialização, que congelaria o idioma.

import RiverBridgeCore
import SwiftUI

struct Udr7Plugin: DevicePluginUI {
    var type: DeviceTypeDescriptor { .udr7 }

    func settingsSheet(mode: DeviceSheetMode, store: TelemetryStore, hostSize: CGSize,
                       onClose: @escaping () -> Void) -> AnyView {
        AnyView(Udr7SettingsSheet(mode: mode, store: store, hostSize: hostSize, onClose: onClose))
    }

    func healthDetail(detail: DeviceDetail?, chainPresent: Bool) -> String? {
        SshEngineText.healthDetail(detail: detail, chainPresent: chainPresent)
    }

    func badge(state: String?) -> (String, Color)? {
        SshEngineText.badge(state: state, console: true)
    }
}

/// O vocabulário de tela do motor SSH, partilhado pelos tipos que rodam sobre
/// ele (protect.py UDR7_STATES): a linha do cartão e o badge de cada estado.
enum SshEngineText {
    static func healthDetail(detail d: DeviceDetail?, chainPresent: Bool) -> String? {
        guard let d else {
            return chainPresent ? L10n.t("Serviço sem este dispositivo.", "Daemon has no such device.") : nil
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

    /// `console`: o UDR7 fala em "console"; o host genérico em "máquina".
    static func badge(state: String?, console: Bool) -> (String, Color)? {
        let alvo = console ? L10n.t("console", "console") : L10n.t("máquina", "machine")
        switch state {
        case "desabilitado": return (L10n.t("Desligada", "Off"), .secondary)
        case "dry_run": return (L10n.t("Modo ensaio", "Rehearsal"), .blue)
        case "armado_nao_verificado": return (L10n.t("Armada — alcance não verificado", "Armed — reach unverified"), .orange)
        case "enviado": return (L10n.t("Desligamento enviado", "Shutdown sent"), .red)
        case "fonte_nao_real": return (L10n.t("Bloqueada — fonte não aceita", "Blocked — source not accepted"), .purple)
        case "fonte_nao_local": return (L10n.t("Bloqueada — NUT não é local", "Blocked — NUT not local"), .purple)
        case "corte_nao_configurado": return (L10n.t("Bloqueada — corte do River não configurado", "Blocked — River cutoff not set"), .purple)
        case "limiar_nao_configurado": return (L10n.t("Bloqueada — limiar não configurado", "Blocked — threshold not set"), .purple)
        case "limiar_abaixo_do_corte": return (L10n.t("Bloqueada — limiar ≤ corte+1", "Blocked — threshold ≤ cutoff+1"), .purple)
        case "config_incompleta": return (L10n.t("Bloqueada — configuração incompleta", "Blocked — incomplete config"), .purple)
        case "chave_insegura": return (L10n.t("Bloqueada — chave SSH ausente/insegura", "Blocked — SSH key missing/insecure"), .purple)
        case "host_desconhecido": return (L10n.t("Bloqueada — \(alvo) fora do known_hosts", "Blocked — \(alvo) not in known_hosts"), .purple)
        case "calibrando": return (L10n.t("Bloqueada — calibrando", "Blocked — calibrating"), .purple)
        case "armamento_ausente": return (L10n.t("Bloqueada — armamento ausente", "Blocked — arming file missing"), .purple)
        case "config_trocada": return (L10n.t("Bloqueada — configuração mudou após armar", "Blocked — config changed after arming"), .purple)
        case "aguardando_restauracao": return (L10n.t("Aguardando energia voltar", "Waiting for power to return"), .orange)
        default: return nil
        }
    }
}
