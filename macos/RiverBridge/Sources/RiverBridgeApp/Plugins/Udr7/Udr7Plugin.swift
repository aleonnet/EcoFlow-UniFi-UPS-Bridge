// O Console UniFi (UDR7) como plugin de TELA: a folha da instância, o detalhe
// honesto do cartão de saúde e os estados que o motor SSH conhece. Sem estado
// armazenado — nada que chame L10n.t na inicialização, que congelaria o idioma.

import RiverBridgeCore
import SwiftUI

struct Udr7Plugin: DevicePluginUI {
    var type: DeviceTypeDescriptor { .udr7 }

    func settingsSheet(mode: DeviceSheetMode, store: TelemetryStore, hostSize: CGSize,
                       onBack: (() -> Void)?, onClose: @escaping (_ createdID: String?) -> Void) -> AnyView {
        AnyView(Udr7SettingsSheet(mode: mode, store: store, hostSize: hostSize, onBack: onBack, onClose: onClose))
    }

    func healthDetail(detail: DeviceDetail?, chainPresent: Bool) -> String? {
        SshEngineText.healthDetail(detail: detail, chainPresent: chainPresent)
    }

    func badge(state: String?) -> (String, Color)? {
        SshEngineText.badge(state: state, console: true)
    }
}

/// O vocabulário de tela do motor SSH, partilhado pelos tipos que rodam sobre
/// ele (os estados que `protect.py` publica em `state`): a linha do cartão e o
/// badge de cada estado. O contrato é fixado pelas fixtures de health.
enum SshEngineText {
    static func healthDetail(detail d: DeviceDetail?, chainPresent: Bool) -> String? {
        guard let d else {
            // O serviço respondeu, mas ainda não publicou o estado DESTE
            // dispositivo (acabou de subir, ou é um serviço anterior). Dizer
            // "sem este dispositivo" era acusar sumiço onde só falta a leitura.
            return chainPresent
                ? L10n.t("O serviço ainda não informou o estado deste dispositivo.",
                         "The service has not reported this device's state yet.")
                : nil
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
        if d.missingKey != nil {
            parts.append(L10n.t("falta configurar um campo obrigatório",
                                "a required field is not filled in"))
        }
        if d.dryRun == true { parts.append(L10n.t("modo ensaio", "rehearsal mode")) }
        if let margin = d.marginEstimateS { parts.append(L10n.t("margem ≈ \(margin) s", "margin ≈ \(margin) s")) }
        for w in d.warnings ?? [] {
            switch w {
            case "lock_open": parts.append(L10n.t("trava de armamento aberta no arquivo do serviço (veja o guia)",
                                                   "arming lock open in the service file (see the guide)"))
            case "charge_missing": parts.append(L10n.t("sem leitura de carga", "no charge reading"))
            case "margin_unknown": parts.append(L10n.t("margem desconhecida (taxa não medida)", "margin unknown (rate not measured)"))
            case "margin_short": parts.append(L10n.t("margem curta", "short margin"))
            case "cutoff_diverges": parts.append(L10n.t("o corte que o River informa é diferente do configurado aqui",
                                                         "the cutoff the River reports differs from the one set here"))
            default: parts.append(w)
            }
        }
        if let last = d.lastEvent {
            parts.append(L10n.t("último: ", "last: ") + EventsTimeline.label(for: last))
        }
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
        case "limiar_abaixo_do_corte": return (L10n.t("Bloqueada — o limiar precisa ficar acima do corte do River",
                                                      "Blocked — the threshold must sit above the River cutoff"), .purple)
        case "config_incompleta": return (L10n.t("Bloqueada — configuração incompleta", "Blocked — incomplete config"), .purple)
        case "chave_insegura": return (L10n.t("Bloqueada — chave SSH ausente/insegura", "Blocked — SSH key missing/insecure"), .purple)
        case "host_desconhecido": return (L10n.t("Bloqueada — identidade do \(alvo) não registrada",
                                                 "Blocked — the \(alvo)'s identity is not registered"), .purple)
        case "calibrando": return (L10n.t("Bloqueada — calibrando", "Blocked — calibrating"), .purple)
        case "armamento_ausente": return (L10n.t("Bloqueada — o armamento não foi concluído", "Blocked — arming was not completed"), .purple)
        case "config_trocada": return (L10n.t("Bloqueada — configuração mudou após armar", "Blocked — config changed after arming"), .purple)
        case "aguardando_restauracao": return (L10n.t("Aguardando energia voltar", "Waiting for power to return"), .orange)
        case nil:
            // O serviço ainda não disse nada sobre este dispositivo: a linha
            // mostra espera, nunca um estado inventado.
            return (L10n.t("Aguardando o estado do serviço…", "Waiting for the service's state…"), .secondary)
        default: return nil
        }
    }
}
