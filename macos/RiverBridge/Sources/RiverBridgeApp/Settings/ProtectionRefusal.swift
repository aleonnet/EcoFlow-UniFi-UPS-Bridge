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
            return L10n.t("Trava fechada: UDR7_ARM_ALLOWED=1 no arquivo do serviço e reinicie.",
                          "Lock closed: set UDR7_ARM_ALLOWED=1 in the service file and restart.")
        case "armado":
            return L10n.t("Armada: ligue o modo ensaio antes de mudar estas chaves ou reiniciar.",
                          "Armed: turn rehearsal on before changing these keys or restarting.")
        case "fonte_nao_real":
            return L10n.t("Fonte recusada: a leitura corrente não é do River registrado (serial) ou é sintética.",
                          "Source refused: the current reading is not the registered River (serial) or is synthetic.")
        case "sem_snapshot":
            return L10n.t("Sem leitura corrente do NUT — não há como verificar a fonte.",
                          "No current NUT reading — the source cannot be verified.")
        case "chave_somente_arquivo":
            return L10n.t("Essa chave só muda no arquivo do serviço.", "That key only changes in the service file.")
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
        case "sem_loja":
            return L10n.t("O serviço instalado não gerencia dispositivos — rode o instalador para atualizar.",
                          "The installed service does not manage devices — run the installer to update.")
        default:
            return L10n.t("Recusado: ", "Refused: ") + (parsed?.erro ?? body)
        }
    }

    /// O `motivo` cru, para o feedback parcial nomear a causa.
    static func motivo(_ body: String) -> String {
        struct Refusal: Decodable { var motivo: String? }
        return (try? JSONDecoder().decode(Refusal.self, from: Data(body.utf8)))?.motivo ?? "recusado"
    }
}
