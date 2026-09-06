// O texto das confirmações dos atos que mexem na energia. Mora no núcleo, e não
// na camada de desenho, pelo mesmo motivo do vocabulário de estados: é contrato
// com o dono, e contrato se testa. A tela só o apresenta.
//
// Até a 0.7.0 havia um segundo ato aqui — entregar o cabo ao aplicativo da
// EcoFlow. Saiu porque o cabo passou a ir e voltar sozinho (ordem do dono: "não
// precisa de botão na UI"); um ato que ninguém mais dispara não precisa de texto.

import Foundation

public struct RiverConfirmation {
    public enum Ato: Sendable {
        /// Desliga o próprio River. Corta a energia de tudo o que está nele.
        case desligarRiver
    }

    public let ato: Ato

    public init(ato: Ato) { self.ato = ato }

    public var title: String {
        switch ato {
        case .desligarRiver:
            L10n.t("Desligar o River agora?", "Turn the River off now?")
        }
    }

    public var confirmLabel: String {
        switch ato {
        case .desligarRiver:
            L10n.t("Desligar", "Turn Off")
        }
    }

    public var message: String {
        switch ato {
        case .desligarRiver:
            L10n.t("Tudo o que está ligado no River perde energia na hora, inclusive este Mac se estiver numa tomada dele.",
                   "Everything plugged into the River loses power at once, including this Mac if it is on one of its outlets.")
        }
    }
}
