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
            L10n.t("Com esta trava aberta, um dispositivo armado é desligado de verdade numa queda de energia, sem ninguém confirmar na hora. Armar continua exigindo o River registrado, a conexão provada e a sua confirmação.",
                   "With this lock open, an armed device is really shut down in a power outage, with nobody confirming at the time. Arming still requires the registered River, a proven connection and your confirmation.")
        case .desligarRiver:
            L10n.t("Desligar o River corta a energia de tudo o que está ligado nele. Com a trava aberta, a ordem aparece no Home Assistant e o botão desta tela passa a funcionar. Cada uso ainda pede confirmação.",
                   "Turning the River off cuts power to everything plugged into it. With the lock open, the order shows up in Home Assistant and the button on this screen starts working. Each use still asks for confirmation.")
        case .mandarNosDispositivos:
            L10n.t("Uma ordem à mão desliga ou reinicia um aparelho de produção agora, sem esperar queda de energia. Só vale para dispositivos com conexão provada nos últimos 30 dias.",
                   "A manual order shuts down or reboots a production device right now, without waiting for an outage. It only applies to devices with a connection proven in the last 30 days.")
        }
    }

    public var confirmLabel: String {
        switch trava {
        case .armarProtecao:
            L10n.t("Abrir a trava — o desligamento passa a ser real",
                   "Open the lock — the shutdown becomes real")
        case .desligarRiver:
            L10n.t("Abrir a trava — a ordem passa a existir",
                   "Open the lock — the order starts to exist")
        case .mandarNosDispositivos:
            L10n.t("Abrir a trava — as ordens passam a existir",
                   "Open the lock — the orders start to exist")
        }
    }
}
