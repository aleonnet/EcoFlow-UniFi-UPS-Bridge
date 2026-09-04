// O texto das confirmações dos atos que mexem na energia. Mora no núcleo, e não
// na camada de desenho, pelo mesmo motivo do vocabulário de estados: é contrato
// com o dono, e contrato se testa. A tela só o apresenta.

import Foundation

public struct RiverConfirmation {
    public enum Ato: Sendable {
        /// Larga o cabo para o aplicativo do fabricante.
        case liberarCabo
        /// Desliga o próprio River. Corta a energia de tudo o que está nele.
        case desligarRiver
    }

    public let ato: Ato

    public init(ato: Ato) { self.ato = ato }

    public var title: String {
        switch ato {
        case .liberarCabo:
            L10n.t("Entregar o River ao aplicativo da EcoFlow?",
                   "Hand the River over to the EcoFlow app?")
        case .desligarRiver:
            L10n.t("DESLIGAR o River agora?", "Turn the River OFF now?")
        }
    }

    public var confirmLabel: String {
        switch ato {
        case .liberarCabo:
            L10n.t("Entregar — paramos de ler o no-break",
                   "Hand over — we stop reading the UPS")
        case .desligarRiver:
            L10n.t("Desligar — corta a energia dos equipamentos",
                   "Turn off — cuts power to the equipment")
        }
    }

    public var message: String {
        switch ato {
        case .liberarCabo:
            L10n.t("O aparelho aceita um leitor por vez. Enquanto ele estiver com o aplicativo da EcoFlow, este app não recebe bateria nem autonomia — o consumo por tomada continua, porque vem por outro caminho.",
                   "The device accepts one reader at a time. While the EcoFlow app has it, this app gets no battery or runtime — draw per outlet keeps coming, because it arrives another way.")
        case .desligarRiver:
            L10n.t("Isto desliga a saída do River: tudo o que estiver ligado nele perde energia na hora, inclusive este Mac se ele estiver na tomada do aparelho.",
                   "This switches the River's output off: everything plugged into it loses power at once, including this Mac if it is plugged into the device.")
        }
    }
}
