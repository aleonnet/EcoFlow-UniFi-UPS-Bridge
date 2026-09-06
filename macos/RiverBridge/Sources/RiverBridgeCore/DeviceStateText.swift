// O vocabulário de TELA dos estados que o serviço publica. Mora no núcleo, e não
// na camada de desenho, por um motivo medido: é contrato com o serviço, que
// publica a lista fechada em /v1/device-types — e contrato se testa.
//
// Estado novo no serviço sem entrada aqui aparece como dispositivo bloqueado e
// SEM observação nenhuma na tela. A cerca `everyStateTheServiceCanPublishHasABadge`
// reprova antes disso chegar ao dono.

import Foundation

public enum DeviceStateText {
    /// O tom do selo, pelo PAPEL — não pela cor.
    ///
    /// Antes os casos se chamavam pelos nomes das tintas: um vocabulário
    /// semântico batizado de "azul" e "roxo". Quem lesse um estado com tom roxo
    /// não sabia o que aquilo significava, e trocar a paleta obrigaria a mexer
    /// no contrato. O papel é estável; a tinta é escolha da camada de tela
    /// (a paleta única vive em Theme.swift).
    public enum Tom: Sendable {
        /// Nada a dizer: a proteção está desligada.
        case neutro
        /// Ligada, mas em ensaio — ela avisa e não age.
        case ensaio
        /// Vai agir, e falta uma condição do dono.
        case atencao
        /// O desfecho que importa: desligou, falhou, está armada de verdade.
        case perigo
        /// Barrada por uma cerca: a configuração não deixa agir.
        case bloqueio
    }

    /// `console`: o UDR7 fala em "console"; o host genérico em "máquina".
    public static func badge(state: String?, console: Bool) -> (texto: String, tom: Tom)? {
        let alvo = console ? L10n.t("console", "console") : L10n.t("máquina", "machine")
        switch state {
        case "desabilitado": return (L10n.t("Desligada", "Off"), .neutro)
        case "dry_run": return (L10n.t("Modo ensaio", "Rehearsal"), .ensaio)
        // "Armada" e só: o serviço publica este estado para TODA instância armada
        // sem desligamento em curso (protect.py `_state_for`; volta a ele depois de
        // uma queda real). O nome do estado não codifica alcance nem histórico —
        // o alcance é provado pelo "Testar conexão", o histórico é a linha
        // "último: …" do cartão. "alcance não verificado" era tradução ao pé da
        // letra, e falsa (dono, 2026-09-06: "que porra é alcance não verificado?").
        case "armado_nao_verificado": return (L10n.t("Armada", "Armed"), .perigo)
        case "enviado": return (L10n.t("Desligamento enviado", "Shutdown sent"), .perigo)
        case "fonte_nao_real": return (L10n.t("Bloqueada — fonte não aceita", "Blocked — source not accepted"), .bloqueio)
        case "fonte_nao_local": return (L10n.t("Bloqueada — NUT não é local", "Blocked — NUT not local"), .bloqueio)
        case "corte_nao_configurado": return (L10n.t("Bloqueada — defina o corte do River em Ajustes › River", "Blocked — set the River cutoff in Settings › River"), .bloqueio)
        case "limiar_nao_configurado": return (L10n.t("Bloqueada — limiar não configurado", "Blocked — threshold not set"), .bloqueio)
        case "limiar_abaixo_do_corte": return (L10n.t("Bloqueada — o limiar precisa ficar acima do corte do River",
                                                      "Blocked — the threshold must sit above the River cutoff"), .bloqueio)
        case "config_incompleta": return (L10n.t("Bloqueada — configuração incompleta", "Blocked — incomplete config"), .bloqueio)
        case "chave_insegura": return (L10n.t("Bloqueada — chave SSH ausente/insegura", "Blocked — SSH key missing/insecure"), .bloqueio)
        case "host_desconhecido": return (L10n.t("Bloqueada — identidade do \(alvo) não registrada",
                                                 "Blocked — the \(alvo)'s identity is not registered"), .bloqueio)
        case "calibrando": return (L10n.t("Bloqueada — calibrando", "Blocked — calibrating"), .bloqueio)
        case "armamento_ausente": return (L10n.t("Bloqueada — o armamento não foi concluído", "Blocked — arming was not completed"), .bloqueio)
        case "config_trocada": return (L10n.t("Bloqueada — configuração mudou após armar", "Blocked — config changed after arming"), .bloqueio)
        case "aguardando_restauracao": return (L10n.t("Aguardando energia voltar", "Waiting for power to return"), .atencao)
        case nil:
            // O serviço ainda não disse nada sobre este dispositivo: a linha
            // mostra espera, nunca um estado inventado.
            return (L10n.t("Aguardando o estado do serviço…", "Waiting for the service's state…"), .neutro)
        default: return nil
        }
    }
}
