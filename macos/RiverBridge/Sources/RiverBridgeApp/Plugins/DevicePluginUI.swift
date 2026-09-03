// A metade de TELA do contrato de dispositivo. O Core declara o que um TIPO é
// (id, ícone, rótulos, campos, eventos); aqui ele diz como se desenha — a folha
// de uma INSTÂNCIA (nova ou existente), a linha do cartão de saúde e o badge.
//
// `@MainActor` no protocolo inteiro: tudo aqui devolve View, e View é isolada ao
// main actor no SDK — um requisito nonisolated não compilaria em modo 6.

import RiverBridgeCore
import SwiftUI

/// O que a folha está fazendo: criando uma instância de um tipo, ou editando
/// uma que já existe. `Identifiable` para o `.sheet(item:)` de Ajustes.
enum DeviceSheetMode: Identifiable, Equatable {
    case new(DeviceTypeDescriptor)
    case edit(DeviceInstance)

    var id: String {
        switch self {
        case .new(let type): "novo:\(type.id)"
        case .edit(let instance): instance.id
        }
    }

    var type: DeviceTypeDescriptor? {
        switch self {
        case .new(let type): type
        case .edit(let instance): DeviceTypeRegistry.type(id: instance.type)
        }
    }

    var instance: DeviceInstance? {
        if case .edit(let instance) = self { return instance }
        return nil
    }

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
}

@MainActor
protocol DevicePluginUI: Sendable {
    var type: DeviceTypeDescriptor { get }

    /// A folha de configuração de UMA instância (ou de uma nova). `hostSize` é
    /// o tamanho da janela-mãe, medido no corpo de SettingsView: a folha é
    /// NSWindow própria, então medir dentro dela seria circular. `onBack` só
    /// existe na etapa 2 de "Adicionar" (volta à lista de tipos); `onClose`
    /// devolve o id criado quando a folha fecha por um POST 201, para a lista
    /// acender a linha nova.
    func settingsSheet(mode: DeviceSheetMode, store: TelemetryStore, hostSize: CGSize,
                       onBack: (() -> Void)?, onClose: @escaping (_ createdID: String?) -> Void) -> AnyView

    /// A linha honesta do cartão de saúde desta instância. `chainPresent` diz
    /// se o health chegou (sem health não há o que dizer; com health e sem
    /// detalhe, o serviço é anterior ao tipo).
    func healthDetail(detail: DeviceDetail?, chainPresent: Bool) -> String?

    /// Rótulo e cor do estado. `nil` quando o tipo não conhece o estado — o
    /// cartão cai no badge genérico, que continua servindo os outros elos.
    func badge(state: String?) -> (String, Color)?
}

@MainActor
enum DevicePluginUIRegistry {
    static let all: [any DevicePluginUI] = [Udr7Plugin(), SshHostPlugin()]

    static func plugin(typeID: String) -> (any DevicePluginUI)? {
        all.first { $0.type.id == typeID }
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
        L10n.t("Armar — pode desligar \(name) numa queda",
               "Arm — may shut \(name) down in an outage")
    }

    var message: String {
        L10n.t("O serviço só arma com a trava aberta, leitura corrente do River registrado e fonte não sintética. Siga o runbook (docs/guides/2026-09-03-1710-runbook-protecao-udr7-por-instancia.md).",
               "The service only arms with the lock open, a current reading from the registered River and a non-synthetic source. Follow the runbook (docs/guides/2026-09-03-1710-runbook-protecao-udr7-por-instancia.md).")
    }
}
