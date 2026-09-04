// O vocabulário de TELA dos estados que o serviço publica. Mora no núcleo, e não
// na camada de desenho, por um motivo medido: é contrato com o serviço, que
// publica a lista fechada em /v1/device-types — e contrato se testa.
//
// Estado novo no serviço sem entrada aqui aparece como dispositivo bloqueado e
// SEM observação nenhuma na tela. A cerca `everyStateTheServiceCanPublishHasABadge`
// reprova antes disso chegar ao dono.

import Foundation

public enum DeviceStateText {
    /// O tom do selo. Quem desenha traduz para cor; o núcleo não conhece SwiftUI.
    public enum Tom: Sendable { case secondary, blue, orange, red, purple }

    /// `console`: o UDR7 fala em "console"; o host genérico em "máquina".
    public static func badge(state: String?, console: Bool) -> (texto: String, tom: Tom)? {
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
