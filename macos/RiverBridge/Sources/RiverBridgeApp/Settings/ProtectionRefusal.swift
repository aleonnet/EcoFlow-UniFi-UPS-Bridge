// A recusa do daemon na voz da interface. Fora de SettingsView porque agora tem
// dois chamadores: a folha do dispositivo e o botão de reiniciar o serviço.

import RiverBridgeCore
import SwiftUI

enum ProtectionRefusal {
    static func text(_ body: String) -> String {
        struct Refusal: Decodable { var erro: String?; var motivo: String? }
        let parsed = try? JSONDecoder().decode(Refusal.self, from: Data(body.utf8))
        switch parsed?.motivo {
        case "armamento_bloqueado":
            return L10n.t("A trava de armamento está fechada. Ligue \"Permitir armar a proteção\" em Ajustes › Travas.",
                          "The arming lock is closed. Turn on \"Allow arming the protection\" under Settings › Locks.")
        case "armado":
            return L10n.t("Esta proteção está armada: ligue o modo ensaio antes de mudar estes campos ou reiniciar.",
                          "This protection is armed: turn rehearsal on before changing these fields or restarting.")
        case "fonte_nao_real":
            return L10n.t("Leitura recusada: ela não vem do River registrado, ou é simulada.",
                          "Reading refused: it does not come from the registered River, or it is simulated.")
        case "sem_snapshot":
            return L10n.t("Sem leitura do River agora — não há como conferir de onde ela vem.",
                          "No reading from the River right now — there is no way to check where it comes from.")
        // Rotas /v1/devices (2026-09-03). `validacao` traz no `erro` o campo e a
        // regra que ele feriu — repassar é o que deixa a pessoa corrigir.
        case "nome_duplicado":
            return L10n.t("Já existe um dispositivo com este nome.", "A device with this name already exists.")
        case "validacao":
            return L10n.t("Campo inválido: ", "Invalid field: ") + (parsed?.erro ?? "")
        case "tipo_desconhecido":
            return L10n.t("O serviço instalado não conhece este tipo de dispositivo — rode o instalador para atualizar.",
                          "The installed service does not know this device type — run the installer to update.")
        case "armar_no_post":
            return L10n.t("Um dispositivo nasce em ensaio; armar é ato separado, depois de criado.",
                          "A device is born in rehearsal; arming is a separate act, after creation.")
        case "dispositivo_ausente":
            return L10n.t("Este dispositivo já não existe no serviço — a lista será recarregada.",
                          "This device no longer exists in the service — the list will reload.")
        // Rotas do River (0.5.0). Cada recusa tem MOTIVO próprio para caber numa
        // frase que diz o que fazer — "armado" das rotas de configuração fala de
        // campos e reinício, que não é o assunto aqui.
        // Acesso ao console (0.6.0)
        case "alcance_nao_verificado":
            return L10n.t("Antes de armar, o serviço precisa provar que alcança este aparelho. Use Conectar ou Testar conexão na folha do dispositivo.",
                          "Before arming, the service must prove it reaches this device. Use Connect or Test connection in the device sheet.")
        case "identidade_divergente":
            return L10n.t("Este aparelho está se apresentando com uma identidade diferente da registrada. Isso acontece quando ele é trocado ou reinstalado — e também quando alguém se coloca no meio do caminho. Confira a impressão digital antes de aceitar.",
                          "This device is presenting a different identity than the one registered. That happens when it is replaced or reinstalled — and also when someone puts themselves in the middle. Check the fingerprint before accepting.")
        case "senha_recusada":
            return L10n.t("O aparelho recusou a senha. Confira a senha do console e tente de novo.",
                          "The device refused the password. Check the console password and try again.")
        case "acesso_falhou":
            return L10n.t("Não consegui preparar o acesso: ", "Could not prepare access: ") + (parsed?.erro ?? "")
        case "cabo_emprestado":
            return L10n.t("O River está com o aplicativo da EcoFlow: sem ler a bateria não dá para armar. Retome o cabo primeiro.",
                          "The River is with the EcoFlow app: without reading the battery there is no arming. Take the cable back first.")
        case "armado_emprestimo":
            return L10n.t("Há proteção armada. Enquanto ela estiver, entregar o River ao aplicativo da EcoFlow deixaria o serviço sem enxergar a queda de energia — ligue o modo ensaio antes.",
                          "A protection is armed. While it is, handing the River to the EcoFlow app would leave the service blind to an outage — turn rehearsal on first.")
        case "armado_desligamento":
            return L10n.t("Há proteção armada. Desligue-a antes, para não haver duas ordens de desligamento ao mesmo tempo.",
                          "A protection is armed. Turn it off first, so there are not two shutdown orders at once.")
        case "desligamento_bloqueado":
            return L10n.t("Desligar o River está travado. Ligue \"Permitir desligar o River\" em Ajustes › Travas para usar este botão.",
                          "Turning the River off is locked. Turn on \"Allow turning the River off\" under Settings › Locks to use this button.")
        case "configuracao_do_dono":
            return L10n.t("A configuração do servidor do no-break é sua (escrita à mão): o interruptor não a toca. Mude a linha LISTEN você mesmo, se quiser.",
                          "The UPS server configuration is yours (written by hand): the switch does not touch it. Change the LISTEN line yourself, if you want.")
        case "sem_conta_do_aparelho":
            return L10n.t("O serviço ainda não tem uma conta para mandar no River. Rode a instalação de novo para criá-la.",
                          "The service does not have an account to command the River yet. Run the installation again to create it.")
        case "sem_servidor":
            return L10n.t("O leitor do River não está no ar — nada foi enviado ao aparelho.",
                          "The River reader is not running — nothing was sent to the device.")
        case "aparelho_recusou":
            return L10n.t("O River recusou: ", "The River refused: ") + (parsed?.erro ?? "")
        case "sem_supervisor":
            return L10n.t("Este serviço não cuida do leitor do River — rode o instalador para atualizar.",
                          "This service does not manage the River reader — run the installer to update.")
        case "sem_loja":
            return L10n.t("O serviço instalado não gerencia dispositivos — rode o instalador para atualizar.",
                          "The installed service does not manage devices — run the installer to update.")
        default:
            // Só o motivo desconhecido chega aqui: o texto do serviço vem
            // prefixado, para a pessoa saber que a frase é dele e não do app.
            return L10n.t("O serviço recusou: ", "The service refused: ") + (parsed?.erro ?? body)
        }
    }

    /// O `motivo` cru, para o feedback parcial nomear a causa.
    static func motivo(_ body: String) -> String {
        struct Refusal: Decodable { var motivo: String? }
        return (try? JSONDecoder().decode(Refusal.self, from: Data(body.utf8)))?.motivo ?? "recusado"
    }
}
