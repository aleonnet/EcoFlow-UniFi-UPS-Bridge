// O texto das três travas — o rótulo do interruptor, a explicação e a
// confirmação ao ligar. Mora no núcleo pelo mesmo motivo de `RiverConfirmation`:
// é contrato com o dono, e contrato se testa. A tela só o apresenta.
//
// Até a 0.7.0 as travas eram "somente arquivo": abrir uma exigia editar o
// arquivo do serviço e reiniciar. O dono vetou o caminho ("o App tem que ser
// user friendly e não para nerds") e decidiu, em 2026-09-05, que as três viram
// interruptores com confirmação. As outras cercas continuam: alcance provado,
// fonte real, nenhuma proteção armada, e a confirmação de cada ato.

import Foundation

/// A confirmação de abrir o servidor do no-break para a rede — o mesmo molde
/// das travas, porque expõe o mesmo tipo de risco: o protocolo do NUT viaja em
/// texto claro, e quem tiver a senha do Home Assistant na rede local manda as
/// ordens que as travas abertas permitirem (revisão fria da 0.8.0).
public struct RedeConfirmation: Sendable {
    public init() {}

    public var title: String {
        L10n.t("Abrir o River para a rede local?", "Open the River to the local network?")
    }

    public var message: String {
        L10n.t("Qualquer aparelho da sua rede passa a ler o River. Quem tiver a senha do Home Assistant pode usar as ordens que as travas liberam. A senha viaja sem cifra.",
               "Any device on your network can read the River. Anyone with the Home Assistant password can use the orders the locks allow. The password travels unencrypted.")
    }

    public var confirmLabel: String {
        L10n.t("Abrir", "Open")
    }
}

public struct TravaConfirmation {
    public enum Trava: String, CaseIterable, Sendable {
        /// Permite armar a proteção: o desligamento numa queda passa a ser real.
        case armarProtecao = "UDR7_ARM_ALLOWED"
        /// Permite desligar o próprio River, pela tela e pelo Home Assistant.
        case desligarRiver = "RIVER_POWEROFF_ALLOWED"
        /// Permite mandar num dispositivo protegido à mão (desligar, reiniciar).
        case mandarNosDispositivos = "DEVICE_CMD_ALLOWED"

        /// A chave do serviço, como o `PUT /v1/config` a recebe.
        public var chave: String { rawValue }
        /// A mesma chave como o `GET /v1/config` a devolve.
        public var atributo: String { rawValue.lowercased() }
    }

    public let trava: Trava

    public init(trava: Trava) { self.trava = trava }

    /// O rótulo do interruptor.
    public var rotulo: String {
        switch trava {
        case .armarProtecao:
            L10n.t("Permitir armar a proteção", "Allow arming the protection")
        case .desligarRiver:
            L10n.t("Permitir desligar o River", "Allow turning the River off")
        case .mandarNosDispositivos:
            L10n.t("Permitir mandar nos dispositivos", "Allow commanding the devices")
        }
    }

    /// A linha cinza sob o rótulo: o que a trava fechada impede.
    public var explicacao: String {
        switch trava {
        case .armarProtecao:
            L10n.t("Fechada, todo dispositivo fica em ensaio: nada é desligado numa queda de energia.",
                   "Closed, every device stays in rehearsal: nothing is shut down in an outage.")
        case .desligarRiver:
            L10n.t("Pela tela e pelo Home Assistant. Fechada, a ordem nem aparece.",
                   "From this screen and from Home Assistant. Closed, the order does not even show up.")
        case .mandarNosDispositivos:
            L10n.t("Desligar ou reiniciar um dispositivo protegido agora, pela tela e pelo Home Assistant.",
                   "Shut down or reboot a protected device right now, from this screen and from Home Assistant.")
        }
    }

    public var title: String {
        switch trava {
        case .armarProtecao:
            L10n.t("Permitir armar a proteção?", "Allow arming the protection?")
        case .desligarRiver:
            L10n.t("Permitir desligar o River?", "Allow turning the River off?")
        case .mandarNosDispositivos:
            L10n.t("Permitir mandar nos dispositivos?", "Allow commanding the devices?")
        }
    }

    public var message: String {
        switch trava {
        case .armarProtecao:
            L10n.t("Um dispositivo armado passa a ser desligado de verdade numa queda de energia, sem confirmação na hora. Armar continua pedindo a sua confirmação.",
                   "An armed device is really shut down in a power outage, with no confirmation at the time. Arming still asks for your confirmation.")
        case .desligarRiver:
            L10n.t("A ordem de desligar o River passa a existir nesta tela e no Home Assistant. Desligar corta a energia de tudo o que está ligado nele; cada uso pede confirmação.",
                   "The order to turn the River off starts to exist on this screen and in Home Assistant. Turning it off cuts power to everything plugged into it; each use asks for confirmation.")
        case .mandarNosDispositivos:
            L10n.t("Desligar ou reiniciar um dispositivo protegido passa a ser possível agora, pela tela e pelo Home Assistant. Só para dispositivos com conexão provada nos últimos 30 dias.",
                   "Shutting down or rebooting a protected device becomes possible right now, from this screen and from Home Assistant. Only for devices with a connection proven in the last 30 days.")
        }
    }

    public var confirmLabel: String {
        switch trava {
        case .armarProtecao:
            L10n.t("Permitir", "Allow")
        case .desligarRiver:
            L10n.t("Permitir", "Allow")
        case .mandarNosDispositivos:
            L10n.t("Permitir", "Allow")
        }
    }
}
