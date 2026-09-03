// The device-type contract, tested without a window: everything in
// DevicePlugins.swift is pure. (Since 2026-09-03 the registry is of TYPES and
// the names are by INSTANCE; the instance-side tests live in DeviceInstanceTests.)

import Foundation
import Testing
@testable import RiverBridgeCore

private func decode(_ json: String) throws -> HealthChain {
    try JSONCoding.decoder().decode(HealthChain.self, from: Data(json.utf8))
}

// MARK: - Health decoding

@Test func decodeHealthWithPluginsList() throws {
    // Inline on purpose: this is what sustains "no Swift-only fixture" — the
    // fixture only gains `plugins` in P6, and this test has to hold before that.
    let chain = try decode("""
    {"nut": "ok", "plugins": [
        {"id": "udr7", "name": "Meu UDR", "state": "fonte_nao_real",
         "detail": {"dry_run": true, "enabled": true, "name": "Meu UDR"}}
    ]}
    """)
    let list = try #require(chain.plugins)
    #expect(list.count == 1)
    #expect(list[0].id == "udr7")
    #expect(list[0].name == "Meu UDR")
    #expect(list[0].state == "fonte_nao_real")
    #expect(list[0].detail?.dryRun == true)
}

@Test func decodeLegacyHealthYieldsNoNameAndNoState() throws {
    let chain = try decode(#"{"nut": "ok"}"#)
    #expect(chain.plugins == nil)
    #expect(chain.pluginName(id: "udr7") == nil)
    #expect(chain.pluginDetail(id: "udr7") == nil)
}

// MARK: - Name resolution

@Test func nameResolvesFromPluginsListBeforeAliasDetail() throws {
    let chain = try decode("""
    {"plugins": [{"id": "udr7", "name": "Da lista"}],
     "udr7_detail": {"name": "Do alias"}}
    """)
    #expect(chain.pluginName(id: "udr7") == "Da lista")
}

@Test func nameResolvesFromAliasDetailWhenPluginsAbsent() throws {
    let chain = try decode(#"{"udr7_detail": {"name": "Do alias"}}"#)
    #expect(chain.pluginName(id: "udr7") == "Do alias")
    // The alias only ever mirrors the migrated instance.
    #expect(chain.pluginName(id: "sshhost_3fa9c1d2") == nil)
    #expect(chain.pluginDetail(id: "sshhost_3fa9c1d2") == nil)
}

@Test func blankNameFallsBackToTheTypeDefault() throws {
    let chain = try decode(#"{"plugins": [{"id": "udr7", "name": "   "}]}"#)
    #expect(chain.pluginName(id: "udr7") == nil)
    let names = DeviceNames.resolve(devices: [], health: chain)
    #expect(names.name(forDevice: "udr7", type: .udr7) == "UDR7")
}

@Test func seamOverridesHealthName() throws {
    let chain = try decode(#"{"plugins": [{"id": "udr7", "name": "Do daemon"}]}"#)
    let names = DeviceNames.resolve(devices: [], health: chain, seams: ["udr7": "Do seam"])
    #expect(names.name(forDevice: "udr7", type: .udr7) == "Do seam")
}

@Test func resolveWithoutHealthUsesDefaults() {
    let names = DeviceNames.resolve(devices: [], health: nil)
    #expect(names.name(forDevice: "udr7", type: .udr7) == "UDR7")
    #expect(names.name(forDevice: "sshhost_x", type: .sshHost) == "Servidor SSH")
}

@Test func parseSeamsReadsRepeatedPairs() {
    let seams = DeviceNames.parseSeams([
        "app", "--seam-nome-plugin", "udr7=Meu UDR", "--seam-tema", "dark",
        "--seam-nome-plugin", "outro=Outro Nome",
    ])
    #expect(seams == ["udr7": "Meu UDR", "outro": "Outro Nome"])
    #expect(DeviceNames.parseSeams(["--seam-nome-plugin"]).isEmpty)
    #expect(DeviceNames.parseSeams(["--seam-nome-plugin", "semigual"]).isEmpty)
    #expect(DeviceNames.parseSeams(["--seam-nome-plugin", "=Vazio"]).isEmpty)
}

// MARK: - The type registry

@Test func registryMapsEveryUdr7EventTypeToTheType() {
    for kind in DeviceTypeDescriptor.udr7.events {
        #expect(DeviceTypeRegistry.type(forEventType: kind.type)?.id == "udr7_ssh")
        #expect(DeviceTypeRegistry.eventKind(kind.type)?.type == kind.type)
    }
    #expect(DeviceTypeDescriptor.udr7.events.count == 10)
    #expect(DeviceEventKind.sshEngine.count == 10)
}

@Test func registryNeverAttributesCoreEventsToADevice() {
    for type in ["POWER_LOSS", "POWER_RESTORED", "LOW_BATTERY", "COMM_LOST", "COMM_RESTORED"] {
        #expect(DeviceTypeRegistry.type(forEventType: type) == nil)
        #expect(DeviceTypeRegistry.eventKind(type) == nil)
    }
}

@Test func typeIDsAndEventTypesAreUnique() {
    let ids = DeviceTypeRegistry.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    let types = DeviceTypeRegistry.allEventTypes
    #expect(Set(types).count == types.count)
}

// MARK: - Labels

@Test func shortLabelsStayUniquePerTypeForAdversarialNames() {
    // The chart's colour scale keys off the label string: two types sharing a
    // label would collapse into one colour. The base labels of the core events
    // are in the same domain, so a device name must not collide with them either.
    let base = ["Queda", "Restaurada", "Bateria baixa", "Comm down", "Comm up"]
    for name in ["", "UDR7", "Queda", "Bateria baixa", "Comm", "Meu UDR"] {
        let resolved = DeviceNames(byPluginID: ["udr7": name]).name(forDevice: "udr7", type: .udr7)
        let labels = DeviceTypeDescriptor.udr7.events.map { $0.short(name: resolved) }
        #expect(Set(labels).count == labels.count, "colidiu entre si com o nome \(name)")
        #expect(Set(labels).isDisjoint(with: Set(base)), "colidiu com um rótulo base com o nome \(name)")
    }
}

@Test func longLabelUsesNameAndDash() {
    let kind = try! #require(DeviceTypeRegistry.eventKind("UDR7_SHUTDOWN_SENT"))
    let long = kind.long(name: "Meu UDR")
    #expect(long.hasPrefix("Meu UDR — "))
    #expect(long != "Meu UDR — ")
}

@Test func toggleNeedsConfirmationOnlyWhenArmingForReal() {
    #expect(DeviceTypeRegistry.toggleNeedsConfirmation(on: true, dryRun: false))
    #expect(DeviceTypeRegistry.toggleNeedsConfirmation(on: true, dryRun: nil))
    #expect(!DeviceTypeRegistry.toggleNeedsConfirmation(on: true, dryRun: true))
    #expect(!DeviceTypeRegistry.toggleNeedsConfirmation(on: false, dryRun: false))
    #expect(!DeviceTypeRegistry.toggleNeedsConfirmation(on: false, dryRun: nil))
    #expect(!DeviceTypeRegistry.toggleNeedsConfirmation(on: false, dryRun: true))
}

// MARK: - Saving

@Test func splitSendsNameAloneAndSkipsEmptyPuts() {
    let both = ProtectionSave.split(
        changes: ["name": "Meu UDR", "ssh_host": "192.0.2.1"], nameKey: "name")
    #expect(both.name == "Meu UDR")
    #expect(both.rest == ["ssh_host": "192.0.2.1"])

    let onlyName = ProtectionSave.split(changes: ["name": "Só o nome"], nameKey: "name")
    #expect(onlyName.name == "Só o nome")
    #expect(onlyName.rest.isEmpty)          // o 2º PUT é pulado

    let onlyRest = ProtectionSave.split(changes: ["ssh_port": "22"], nameKey: "name")
    #expect(onlyRest.name == nil)           // o 1º PUT é pulado
    #expect(onlyRest.rest == ["ssh_port": "22"])
}

@Test func partialFeedbackNamesTheRefusedKeys() {
    let text = ProtectionSave.partialFeedback(
        refused: ["ssh_port", "ssh_host"], motivo: "armado")
    #expect(text.contains("ssh_host, ssh_port"))   // ordenadas
    #expect(text.contains("armado"))
}

// MARK: - The store as the single source of the health

@MainActor
@Test func storeStartsWithDefaultNamesAndSeam() {
    // Sem health nenhum: o padrão do tipo.
    #expect(TelemetryStore().deviceNames.name(forDevice: "udr7", type: .udr7) == "UDR7")
    // Com seam de linha de comando: vence, e já vale antes de qualquer GET.
    let seamed = TelemetryStore(arguments: ["app", "--seam-nome-plugin", "udr7=Meu UDR"])
    #expect(seamed.deviceNames.name(forDevice: "udr7", type: .udr7) == "Meu UDR")
    #expect(seamed.health == nil)
}

@MainActor
@Test func refreshHealthWithoutEndpointLeavesStateUntouched() async {
    // Ambiente injetado e vazio: não há serviço a descobrir. Sem essa injeção o
    // teste encontraria o daemon real da máquina de quem roda e passaria ou
    // falharia conforme o computador — foi o que aconteceu ao escrevê-lo.
    let store = TelemetryStore(
        arguments: ["app", "--seam-nome-plugin", "udr7=Meu UDR"],
        environment: ["RUB_STATE_DIR": "/nao/existe/em/lugar/nenhum"]
    )
    await store.refreshHealth()
    #expect(store.health == nil)
    #expect(store.deviceNames.name(forDevice: "udr7", type: .udr7) == "Meu UDR")
}

// MARK: - A folha cabe na janela

/// A folha é apresentada DENTRO da janela-mãe, que pode encolher até 414×480
/// (RiverBridgeApp.swift). Ela precisa caber nesse mínimo, nos DOIS eixos.
///
/// Esta cerca existe porque a primeira versão não cabia: `minWidth` era 380
/// contra 374 pt de espaço útil, e a ALTURA não era limitada de forma nenhuma —
/// a folha vazava para fora da janela. Os números vivem no Core
/// (DeviceSheetMetrics) como aritmética pura, sem SwiftUI, e a folha os LÊ.
@Test func sheetFitsInsideTheSmallestHostWindow() {
    let hostMin = CGSize(width: 414, height: 480)      // RiverBridgeApp: .frame(minWidth:minHeight:)
    let folga = DeviceSheetMetrics.margin               // 20 pt de cada lado

    #expect(DeviceSheetMetrics.minWidth <= hostMin.width - folga,
            "a folha não cabe na largura mínima da janela")
    #expect(DeviceSheetMetrics.minHeight <= hostMin.height - folga,
            "a folha não cabe na altura mínima da janela")

    // E o tamanho EFETIVO, com a fórmula que a folha usa, nunca passa do espaço útil.
    for host in [hostMin, CGSize(width: 1000, height: 880), CGSize(width: 500, height: 600)] {
        let size = DeviceSheetMetrics.size(host: host)
        #expect(size.width <= max(DeviceSheetMetrics.minWidth, host.width - folga))
        #expect(size.height <= max(DeviceSheetMetrics.minHeight, host.height - folga))
    }
}
