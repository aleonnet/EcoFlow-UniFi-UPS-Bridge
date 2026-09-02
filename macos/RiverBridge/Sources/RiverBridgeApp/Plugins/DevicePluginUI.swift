// A metade de TELA do contrato de plugin. O Core declara o que o dispositivo é
// (id, ícone, chaves, eventos); aqui ele diz como se desenha.
//
// `@MainActor` no protocolo inteiro: tudo aqui devolve View, e View é isolada ao
// main actor no SDK — um requisito nonisolated não compilaria em modo 6.

import RiverBridgeCore
import SwiftUI

@MainActor
protocol DevicePluginUI: Sendable {
    var descriptor: DevicePluginDescriptor { get }

    /// A folha de configuração do dispositivo. `hostWidth` é a largura da
    /// janela-mãe, medida no corpo de SettingsView: a folha é NSWindow própria,
    /// então medir dentro dela seria circular.
    func settingsSheet(store: TelemetryStore, hostWidth: CGFloat,
                       onClose: @escaping () -> Void) -> AnyView

    /// A linha honesta do cartão de saúde deste dispositivo.
    func healthDetail(chain: HealthChain?) -> String?

    /// Rótulo e cor do estado. `nil` quando o plugin não conhece o estado — o
    /// cartão cai no badge genérico, que continua servindo os outros elos.
    func badge(state: String?) -> (String, Color)?
}

@MainActor
enum DevicePluginUIRegistry {
    static let all: [any DevicePluginUI] = [Udr7Plugin()]

    static func plugin(id: String) -> (any DevicePluginUI)? {
        all.first { $0.descriptor.id == id }
    }
}

/// O diálogo de armar, compartilhado entre a LISTA (Ajustes) e a FOLHA. Existe
/// como builder porque a folha é uma NSWindow própria: um confirmationDialog
/// declarado na tela de Ajustes não aparece sobre ela.
struct ArmConfirmation {
    enum Mode {
        /// Na folha: o botão desliga o ensaio do dispositivo já habilitado.
        case turnOffRehearsal
        /// Na lista: ligar a proteção com o ensaio já desligado arma de verdade.
        case enableWithRehearsalOff
    }

    let name: String
    let mode: Mode

    var title: String {
        switch mode {
        case .turnOffRehearsal:
            L10n.t("Desligar o modo ensaio e ARMAR a proteção de \(name)?",
                   "Turn rehearsal off and ARM the protection of \(name)?")
        case .enableWithRehearsalOff:
            L10n.t("Ligar a proteção de \(name) com o ensaio DESLIGADO — arma de verdade?",
                   "Turn on \(name) protection with rehearsal OFF — this arms for real?")
        }
    }

    var confirmLabel: String {
        L10n.t("Armar — pode desligar o \(name) numa queda",
               "Arm — may shut \(name) down in an outage")
    }

    var message: String {
        L10n.t("O serviço só arma com a trava aberta, leitura corrente do River registrado e fonte não sintética. Siga o runbook (docs/UDR7_PROTECAO_SSH_20260901.md).",
               "The service only arms with the lock open, a current reading from the registered River and a non-synthetic source. Follow the runbook (docs/UDR7_PROTECAO_SSH_20260901.md).")
    }
}
