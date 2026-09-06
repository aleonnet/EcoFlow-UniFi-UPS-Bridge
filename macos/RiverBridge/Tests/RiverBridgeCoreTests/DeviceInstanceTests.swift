// Dispositivos por instância (2026-09-03): tipos × instâncias, nomes únicos,
// chips por instância, dono de evento, métricas da folha — tudo puro.

import Foundation
import Testing
@testable import RiverBridgeCore

/// O nome do tipo host SSH nos dois idiomas. Os testes aceitam qualquer um dos dois: o
/// idioma vivo é estado global (`L10n.cachedIsPT`) que `languagePickerWinsOverDefaultsShadowing`
/// alterna em paralelo — comparar com `L10n.t(...)` lido noutro instante era uma corrida
/// (revisão fria de 2026-09-03). O par de nomes do tipo é provado em `defaultNamesCoverBothLanguages`.
let nomesDoTipoSSH = ["Servidor SSH", "SSH server"]


private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("tests/fixtures/\(name).json")
}

private func device(_ id: String, _ type: String, _ name: String) -> DeviceInstance {
    DeviceInstance(id: id, type: type, name: name)
}

private let tres = [
    device("udr7", "udr7_ssh", "UDR7"),
    device("sshhost_3fa9c1d2", "ssh_host", "NAS da sala"),
    device("sshhost_7b2e4d10", "ssh_host", "Servidor"),
]

// MARK: - Decodificação das fixtures partilhadas com o Python

@Test func decodeDeviceTypesCatalog() throws {
    let data = try Data(contentsOf: fixture("device_types"))
    let types = try JSONCoding.decoder().decode(DeviceTypesResponse.self, from: data).types
    #expect(types.map(\.id) == ["udr7_ssh", "ssh_host"])
    let host = try #require(types.first { $0.id == "ssh_host" })
    #expect(host.labelPt == "Computador ou servidor via SSH")
    let cmd = try #require(host.fields.first { $0.name == "shutdown_command" })
    #expect(cmd.defaultValue?.stringValue == "shutdown -h now")
    #expect(cmd.enumValues?.contains("sudo -n shutdown -h now") == true)
    #expect(host.defaultValue(for: "ssh_port")?.intValue == 22)
}

@Test func decodeDevicesTresFixture() throws {
    let data = try Data(contentsOf: fixture("devices_tres"))
    let devices = try JSONCoding.decoder().decode(DevicesResponse.self, from: data).devices
    #expect(devices.map(\.id) == ["udr7", "sshhost_3fa9c1d2", "sshhost_7b2e4d10"])
    #expect(devices[1].fields["shutdown_command"]?.stringValue == "sudo -n shutdown -h now")
    #expect(devices[2].enabled == true && devices[2].dryRun == true)
}

@Test func decodeHealthDispositivosKeepsAliasAndTypes() throws {
    let data = try Data(contentsOf: fixture("health_dispositivos"))
    let chain = try JSONCoding.decoder().decode(HealthChain.self, from: data)
    let list = try #require(chain.plugins)
    #expect(list.map(\.type) == ["udr7_ssh", "ssh_host", "ssh_host"])
    #expect(chain.udr7 == list[0].state)
    #expect(chain.pluginDetail(id: "sshhost_3fa9c1d2")?.state == "desabilitado")
}

// MARK: - O contrato de campos com o catálogo do daemon

@Test func fieldKeysMatchTheDaemonCatalogPerType() throws {
    let data = try Data(contentsOf: fixture("device_types"))
    let types = try JSONCoding.decoder().decode(DeviceTypesResponse.self, from: data).types
    for descriptor in DeviceTypeRegistry.all {
        let catalog = try #require(types.first { $0.id == descriptor.id }, "tipo \(descriptor.id) fora do catálogo")
        #expect(Set(descriptor.fieldKeys) == Set(catalog.fields.map(\.name)),
                "campos do tipo \(descriptor.id) divergem do catálogo")
        // Série esperada e corte são do núcleo, nunca da instância (D16).
        #expect(!descriptor.fieldKeys.contains("expected_serial") && !descriptor.fieldKeys.contains("cutoff_percent"))
    }
}

// MARK: - Registro de tipos e eventos

@Test func registryMapsEventsOfBothTypes() {
    #expect(DeviceTypeRegistry.type(forEventType: "UDR7_SHUTDOWN_SENT")?.id == "udr7_ssh")
    #expect(DeviceTypeRegistry.type(forEventType: "SSH_HOST_SHUTDOWN_SENT")?.id == "ssh_host")
    #expect(DeviceTypeRegistry.type(forEventType: "POWER_LOSS") == nil)
    #expect(DeviceTypeRegistry.eventKind("SSH_HOST_ARMED")?.tone == .toggle)
    #expect(DeviceTypeDescriptor.sshHost.events.count == 11)          // sem WoL
    #expect(DeviceTypeDescriptor.udr7.events.count == 13)
    let types = DeviceTypeRegistry.allEventTypes
    #expect(Set(types).count == types.count)
}

// MARK: - Nomes

@Test func uniqueLabelsGiveEveryColliderAnOrdinal() {
    let dup = [device("a", "ssh_host", "Servidor"), device("b", "ssh_host", "Servidor"),
               device("c", "udr7_ssh", "UDR7"), device("d", "ssh_host", " Servidor ")]
    let labels = DeviceNames.uniqueLabels(instances: dup)
    #expect(labels == ["a": "Servidor 1", "b": "Servidor 2", "c": "UDR7", "d": "Servidor 3"])
    #expect(DeviceNames.uniqueLabels(instances: tres).values.sorted() == ["NAS da sala", "Servidor", "UDR7"])
}

@Test func defaultNamesCoverBothLanguages() {
    // O nome padrão do tipo existe nos dois idiomas e o vivo é um deles (o idioma vivo é
    // estado global alternado por outro teste; a escolha em si é `L10n.t`, testada em
    // `languagePickerWinsOverDefaultsShadowing`).
    #expect(DeviceTypeDescriptor.sshHost.defaultNamePT == "Servidor SSH")
    #expect(DeviceTypeDescriptor.sshHost.defaultNameEN == "SSH server")
    #expect(nomesDoTipoSSH.contains(DeviceTypeDescriptor.sshHost.defaultName))
    #expect(DeviceTypeDescriptor.udr7.defaultNamePT == "UDR7" && DeviceTypeDescriptor.udr7.defaultNameEN == "UDR7")
}

@Test func suggestedNameIsUniqueAmongExisting() {
    // O nome sugerido é o do tipo (no idioma do app) e ganha ordinal até ficar único,
    // comparando sem distinguir maiúsculas. A cadeia de ordinais é provada com o UDR7,
    // cujo nome não depende do idioma.
    #expect(nomesDoTipoSSH.contains(DeviceNames.suggestedName(type: .sshHost, existing: tres)))
    #expect(DeviceNames.suggestedName(type: .udr7, existing: tres) == "UDR7 2")
    let more = tres + [device("x", "udr7_ssh", "udr7 2"), device("y", "udr7_ssh", "UDR7 3")]
    #expect(DeviceNames.suggestedName(type: .udr7, existing: more) == "UDR7 4")
}

@Test func nameForEventPrefersTheInstanceThenTheOnlyOneOfItsType() {
    let names = DeviceNames.resolve(devices: tres, health: nil)
    #expect(names.name(forEvent: "SSH_HOST_SHUTDOWN_SENT", device: "sshhost_7b2e4d10", devices: tres) == "Servidor")
    #expect(names.name(forEvent: "UDR7_SHUTDOWN_DRYRUN", device: nil, devices: tres) == "UDR7")
    // dois hosts e nenhum dono: o nome do TIPO, nunca um chute entre os dois
    #expect(nomesDoTipoSSH.contains(names.name(forEvent: "SSH_HOST_SHUTDOWN_SENT", device: nil, devices: tres)))
    #expect(names.name(forEvent: "POWER_LOSS", device: nil, devices: tres) == "")
    // Dono que já não existe (instância removida) com UMA instância do tipo restante:
    // o nome do TIPO, nunca o da que sobrou. (Com duas restantes o caminho antigo já
    // caía no tipo — o caso discriminante é este, revisão fria de 2026-09-03.)
    let soUm = [tres[0], tres[2]]
    #expect(nomesDoTipoSSH.contains(names.name(forEvent: "SSH_HOST_SHUTDOWN_SENT", device: "sshhost_apagado", devices: soUm)))
    #expect(names.name(forEvent: "SSH_HOST_SHUTDOWN_SENT", device: nil, devices: soUm) == "Servidor")
}

@Test func resolveTakesDevicesOverHealthAndSeamsOverBoth() throws {
    let chain = try JSONCoding.decoder().decode(HealthChain.self, from: Data(
        #"{"plugins": [{"id": "udr7", "name": "Do health"}, {"id": "so_health", "name": "Só no health"}]}"#.utf8))
    let names = DeviceNames.resolve(devices: tres, health: chain, seams: ["sshhost_3fa9c1d2": "Do seam"])
    #expect(names.name(forDevice: "udr7") == "UDR7")               // a instância vence o health
    #expect(names.name(forDevice: "so_health") == "Só no health")   // o health reforça o que a lista não tem
    #expect(names.name(forDevice: "sshhost_3fa9c1d2") == "Do seam")
    #expect(nomesDoTipoSSH.contains(names.name(forDevice: "nao_existe", type: .sshHost)))
}

// MARK: - Chips

@Test func chipsFollowInstances() {
    let chips = EventChipSpec.all(devices: tres)
    #expect(chips.count == 4 + 3)
    #expect(Set(chips.map(\.id)).count == chips.count)
    let nas = try! #require(chips.first { $0.deviceID == "sshhost_3fa9c1d2" })
    #expect(nas.name == "NAS da sala" && nas.symbol == "desktopcomputer")
    #expect(Set(nas.types) == Set(DeviceTypeDescriptor.sshHost.events.map(\.type)))
    #expect(EventChipSpec.all(devices: []).count == 4)
}

// MARK: - Suporte do serviço

@Test func supportVerdictOnlyOn404() {
    #expect(DeviceAPISupport.verdict(for: APIError.badStatus(404, ""), version: "0.2.0")
            == .unsupported(L10n.t("serviço 0.2.0", "service 0.2.0")))
    #expect(DeviceAPISupport.verdict(for: APIError.badStatus(500, ""), version: nil) == .unknown)
    #expect(DeviceAPISupport.verdict(for: APIError.notConnected, version: nil) == .unknown)
}

// MARK: - A folha cabe na janela (lê o Core, não copia números)

@Test func sheetMetricsFitTheSmallestHostWindow() {
    let host = CGSize(width: 414, height: 480)
    let size = DeviceSheetMetrics.size(host: host)
    #expect(size.width <= host.width - DeviceSheetMetrics.margin)
    #expect(size.height <= host.height - DeviceSheetMetrics.margin)
    #expect(DeviceSheetMetrics.minWidth <= host.width - DeviceSheetMetrics.margin)
    #expect(DeviceSheetMetrics.minHeight <= host.height - DeviceSheetMetrics.margin)
    #expect(DeviceSheetMetrics.isNarrow(width: size.width))
    let big = DeviceSheetMetrics.size(host: CGSize(width: 1000, height: 880))
    #expect(big == CGSize(width: DeviceSheetMetrics.maxWidth, height: DeviceSheetMetrics.maxHeight))
}

@MainActor
@Test func storeSeededFromFixturesIsSupportedAndNamed() {
    let store = TelemetryStore(arguments: [
        "app", "--seam-dispositivos", fixture("devices_tres").path,
        "--seam-health", fixture("health_dispositivos").path,
    ], environment: ["RUB_STATE_DIR": "/nao/existe"])
    #expect(store.devices.map(\.id) == ["udr7", "sshhost_3fa9c1d2", "sshhost_7b2e4d10"])
    #expect(store.deviceSupport == .supported)
    #expect(store.health?.plugins?.count == 3)
    #expect(store.deviceNames.name(forDevice: "sshhost_7b2e4d10") == "Servidor")
}

// MARK: - Um chip por instância filtra pelo DONO do evento

/// O serviço filtra o histórico por TIPO; o dono (instância) é filtrado no app.
/// Um evento gravado antes de existirem instâncias não carrega dono: ele cai na
/// ÚNICA instância do seu tipo, e em nenhuma quando há duas — a mesma regra de
/// `DeviceNames.name(forEvent:)`. Refutação: trocar o `return device == mine`
/// por `return true` faz o chip do NAS reclamar o evento do Servidor.
@Test func chipMatchesEventsByOwnerAndFallsBackToTheOnlyOneOfItsType() {
    let chips = EventChipSpec.all(devices: tres)
    let udr7 = chips.first { $0.deviceID == "udr7" }!
    let nas = chips.first { $0.deviceID == "sshhost_3fa9c1d2" }!
    let servidor = chips.first { $0.deviceID == "sshhost_7b2e4d10" }!
    let queda = chips.first { $0.deviceID == nil }!

    // Com dono: só o chip do dono.
    #expect(servidor.matches(eventType: "SSH_HOST_SHUTDOWN_SENT", device: "sshhost_7b2e4d10", devices: tres))
    #expect(!nas.matches(eventType: "SSH_HOST_SHUTDOWN_SENT", device: "sshhost_7b2e4d10", devices: tres))
    // Sem dono, tipo com UMA instância: ela.
    #expect(udr7.matches(eventType: "UDR7_SHUTDOWN_DRYRUN", device: nil, devices: tres))
    // Sem dono, tipo com DUAS instâncias: nenhuma reclama.
    #expect(!nas.matches(eventType: "SSH_HOST_SHUTDOWN_SENT", device: nil, devices: tres))
    #expect(!servidor.matches(eventType: "SSH_HOST_SHUTDOWN_SENT", device: nil, devices: tres))
    // Vocabulário de OUTRO tipo nunca entra, mesmo com o dono certo.
    #expect(!udr7.matches(eventType: "SSH_HOST_SHUTDOWN_SENT", device: "udr7", devices: tres))
    // Chips do bridge ignoram o dono.
    #expect(queda.matches(eventType: "POWER_LOSS", device: nil, devices: tres))
    #expect(!queda.matches(eventType: "UDR7_SHUTDOWN_SENT", device: nil, devices: tres))
}

/// "Armada" e só (0.9.0). O estado `armado_nao_verificado` é o de toda instância
/// armada sem desligamento em curso; traduzi-lo como "alcance não verificado" era
/// falso — o alcance é provado pelo "Testar conexão" (dono, 2026-09-06).
@Test func oEstadoArmadoNaoAcusaAlcance() throws {
    let badge = try #require(DeviceStateText.badge(state: "armado_nao_verificado", console: true))
    #expect(["Armada", "Armed"].contains(badge.texto))
    #expect(!badge.texto.lowercased().contains("alcance") && !badge.texto.lowercased().contains("reach"))
    #expect(badge.tom == .perigo)
}

@Test func everyStateTheServiceCanPublishHasABadge() throws {
    // O serviço publica o vocabulário fechado de estados em /v1/device-types.
    // Se ele ganhar um estado e o app não ganhar o selo, o dispositivo aparece
    // bloqueado e MUDO na tela. Esta cerca reprova antes disso chegar ao dono.
    let dados = try Data(contentsOf: fixture("device_types"))
    let catalogo = try JSONCoding.decoder().decode(DeviceTypesResponse.self, from: dados)
    #expect(catalogo.types.isEmpty == false)
    for tipo in catalogo.types {
        let estados = try #require(tipo.states, "o serviço parou de publicar os estados")
        #expect(estados.count == 16)
        for estado in estados {
            #expect(DeviceStateText.badge(state: estado, console: true) != nil,
                    "estado sem selo no app: \(estado)")
        }
    }
}
