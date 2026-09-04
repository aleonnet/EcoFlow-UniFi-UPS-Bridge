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
        if let detail = d.sourceDetail, detail != "telemetria_sintetica" {
            parts.append(SshEngineText.motivoDaFonte(detail))
        }
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
            default: break        // aviso que este app ainda não conhece: melhor calar que exibir código
            }
        }
        if let last = d.lastEvent {
            parts.append(L10n.t("último: ", "last: ") + EventsTimeline.label(for: last))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Por que a fonte não foi aceita, em português. Motivo desconhecido vira
    /// uma frase honesta, nunca o código cru.
    static func motivoDaFonte(_ motivo: String) -> String {
        switch motivo {
        case "serial_nao_registrado":
            return L10n.t("o número de série do River ainda não foi informado",
                          "the River's serial number has not been entered yet")
        case "serial_divergente":
            return L10n.t("a leitura vem de outro aparelho, não do River registrado",
                          "the reading comes from another device, not the registered River")
        case "sem_leitura":
            return L10n.t("sem leitura do River agora", "no reading from the River right now")
        default:
            return L10n.t("a leitura não foi aceita", "the reading was not accepted")
        }
    }

    /// `console`: o UDR7 fala em "console"; o host genérico em "máquina".
    /// O vocabulário mora no núcleo (`DeviceStateText`), que é onde o contrato com
    /// o serviço é testado; aqui fica só a cor.
    static func badge(state: String?, console: Bool) -> (String, Color)? {
        guard let selo = DeviceStateText.badge(state: state, console: console) else { return nil }
        return (selo.texto, cor(selo.tom))
    }

    private static func cor(_ tom: DeviceStateText.Tom) -> Color {
        switch tom {
        case .secondary: .secondary
        case .blue: .blue
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        }
    }
}
