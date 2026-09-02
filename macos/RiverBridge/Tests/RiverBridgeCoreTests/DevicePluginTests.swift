// The device-plugin contract, tested without a window: everything in
// DevicePlugins.swift is pure.

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
}

@Test func blankNameFallsBackToDefault() throws {
    let chain = try decode(#"{"plugins": [{"id": "udr7", "name": "   "}]}"#)
    #expect(chain.pluginName(id: "udr7") == nil)
    let names = DeviceNames.resolve(health: chain)
    #expect(names.name(for: .udr7) == "UDR7")
}

@Test func seamOverridesHealthName() throws {
    let chain = try decode(#"{"plugins": [{"id": "udr7", "name": "Do daemon"}]}"#)
    let names = DeviceNames.resolve(health: chain, seams: ["udr7": "Do seam"])
    #expect(names.name(for: .udr7) == "Do seam")
}

@Test func resolveWithoutHealthUsesDefaults() {
    let names = DeviceNames.resolve(health: nil)
    #expect(names.name(for: .udr7) == "UDR7")
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

// MARK: - The registry

@Test func registryMapsEveryUdr7EventTypeToThePlugin() {
    for kind in DevicePluginDescriptor.udr7.events {
        #expect(DevicePluginRegistry.plugin(forEventType: kind.type)?.id == "udr7")
        #expect(DevicePluginRegistry.eventKind(kind.type)?.type == kind.type)
    }
    #expect(DevicePluginRegistry.allEventTypes.count == 10)
}

@Test func registryNeverAttributesCoreEventsToADevice() {
    for type in ["POWER_LOSS", "POWER_RESTORED", "LOW_BATTERY", "COMM_LOST", "COMM_RESTORED"] {
        #expect(DevicePluginRegistry.plugin(forEventType: type) == nil)
        #expect(DevicePluginRegistry.eventKind(type) == nil)
    }
}

@Test func pluginIDsAndEventTypesAreUnique() {
    let ids = DevicePluginRegistry.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    let types = DevicePluginRegistry.allEventTypes
    #expect(Set(types).count == types.count)
}

// MARK: - Labels

@Test func shortLabelsStayUniquePerTypeForAdversarialNames() {
    // The chart's colour scale keys off the label string: two types sharing a
    // label would collapse into one colour. The base labels of the core events
    // are in the same domain, so a device name must not collide with them either.
    let base = ["Queda", "Restaurada", "Bateria baixa", "Comm down", "Comm up"]
    for name in ["", "UDR7", "Queda", "Bateria baixa", "Comm", "Meu UDR"] {
        let resolved = DeviceNames(byPluginID: ["udr7": name]).name(for: .udr7)
        let labels = DevicePluginDescriptor.udr7.events.map { $0.short(name: resolved) }
        #expect(Set(labels).count == labels.count, "colidiu entre si com o nome \(name)")
        #expect(Set(labels).isDisjoint(with: Set(base)), "colidiu com um rótulo base com o nome \(name)")
    }
}

@Test func longLabelUsesNameAndDash() {
    let kind = try! #require(DevicePluginRegistry.eventKind("UDR7_SHUTDOWN_SENT"))
    let long = kind.long(name: "Meu UDR")
    #expect(long.hasPrefix("Meu UDR — "))
    #expect(long != "Meu UDR — ")
}

// MARK: - The contract with the daemon

@Test func udr7ConfigKeysMatchTheApiContract() {
    // The 17 keys the daemon's adapter owns (config.py, prefix PROTECT_/UDR7_).
    let daemon: Set<String> = [
        "PROTECT_UDR7", "PROTECT_DRY_RUN", "UDR7_ARM_ALLOWED", "UDR7_SSH_HOST",
        "UDR7_SSH_PORT", "UDR7_SSH_USER", "UDR7_SSH_KEY", "UDR7_EXPECTED_SERIAL",
        "UDR7_CUTOFF_PERCENT", "UDR7_SHUTDOWN_PERCENT", "UDR7_DISCHARGE_SECONDS_PER_PCT",
        "UDR7_RUNTIME_MINUTES", "UDR7_MIN_OUTAGE_SECONDS", "UDR7_CONFIRM_SECONDS",
        "UDR7_RETRY_MAX", "UDR7_WOL_MAC", "UDR7_NAME",
    ]
    let plugin = DevicePluginDescriptor.udr7
    let fromApp = Set(plugin.sheetKeys)
        .union([plugin.enableKey, plugin.nameKey, "PROTECT_DRY_RUN"])
    #expect(fromApp.isSubset(of: daemon))
    // What the sheet deliberately does NOT edit: the file-only lock and the retry
    // budget. If either shows up in the sheet, this fence says so.
    #expect(daemon.subtracting(fromApp) == ["UDR7_ARM_ALLOWED", "UDR7_RETRY_MAX"])
}

@Test func toggleNeedsConfirmationOnlyWhenArmingForReal() {
    #expect(DevicePluginRegistry.toggleNeedsConfirmation(on: true, dryRun: false))
    #expect(DevicePluginRegistry.toggleNeedsConfirmation(on: true, dryRun: nil))
    #expect(!DevicePluginRegistry.toggleNeedsConfirmation(on: true, dryRun: true))
    #expect(!DevicePluginRegistry.toggleNeedsConfirmation(on: false, dryRun: false))
    #expect(!DevicePluginRegistry.toggleNeedsConfirmation(on: false, dryRun: nil))
    #expect(!DevicePluginRegistry.toggleNeedsConfirmation(on: false, dryRun: true))
}

// MARK: - Saving

@Test func splitSendsNameAloneAndSkipsEmptyPuts() {
    let both = ProtectionSave.split(
        changes: ["UDR7_NAME": "Meu UDR", "UDR7_SSH_HOST": "192.0.2.1"], nameKey: "UDR7_NAME")
    #expect(both.name == "Meu UDR")
    #expect(both.rest == ["UDR7_SSH_HOST": "192.0.2.1"])

    let onlyName = ProtectionSave.split(changes: ["UDR7_NAME": "Só o nome"], nameKey: "UDR7_NAME")
    #expect(onlyName.name == "Só o nome")
    #expect(onlyName.rest.isEmpty)          // o 2º PUT é pulado

    let onlyRest = ProtectionSave.split(changes: ["UDR7_SSH_PORT": "22"], nameKey: "UDR7_NAME")
    #expect(onlyRest.name == nil)           // o 1º PUT é pulado
    #expect(onlyRest.rest == ["UDR7_SSH_PORT": "22"])
}

@Test func partialFeedbackNamesTheRefusedKeys() {
    let text = ProtectionSave.partialFeedback(
        refused: ["UDR7_SSH_PORT", "UDR7_SSH_HOST"], motivo: "armado")
    #expect(text.contains("UDR7_SSH_HOST, UDR7_SSH_PORT"))   // ordenadas
    #expect(text.contains("armado"))
}

// MARK: - The store as the single source of the health

@MainActor
@Test func storeStartsWithDefaultNamesAndSeam() {
    // Sem health nenhum: o padrão do descritor.
    #expect(TelemetryStore().deviceNames.name(for: .udr7) == "UDR7")
    // Com seam de linha de comando: vence, e já vale antes de qualquer GET.
    let seamed = TelemetryStore(arguments: ["app", "--seam-nome-plugin", "udr7=Meu UDR"])
    #expect(seamed.deviceNames.name(for: .udr7) == "Meu UDR")
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
    #expect(store.deviceNames.name(for: .udr7) == "Meu UDR")
}

// MARK: - A folha cabe na janela

/// A folha é apresentada DENTRO da janela-mãe, que pode encolher até 414×480
/// (RiverBridgeApp.swift). Ela precisa caber nesse mínimo, nos DOIS eixos.
///
/// Esta cerca existe porque a primeira versão não cabia: `minWidth` era 380
/// contra 374 pt de espaço útil, e a ALTURA não era limitada de forma nenhuma —
/// a folha vazava para fora da janela. Os números vivem aqui como aritmética
/// pura, sem SwiftUI, para a cerca rodar no `swift test` do Core.
@Test func sheetFitsInsideTheSmallestHostWindow() {
    let hostMin = CGSize(width: 414, height: 480)      // RiverBridgeApp: .frame(minWidth:minHeight:)
    let folga: CGFloat = 40                            // 20 pt de cada lado

    // Os pisos declarados na folha (Udr7SettingsSheet.minLargura/minAltura).
    let minLargura: CGFloat = 340
    let minAltura: CGFloat = 380

    #expect(minLargura <= hostMin.width - folga,
            "a folha não cabe na largura mínima da janela")
    #expect(minAltura <= hostMin.height - folga,
            "a folha não cabe na altura mínima da janela")

    // E o tamanho EFETIVO, com a mesma fórmula da folha, nunca passa do espaço útil.
    func largura(_ host: CGSize) -> CGFloat { max(minLargura, min(600, host.width - folga)) }
    func altura(_ host: CGSize) -> CGFloat { max(minAltura, min(640, host.height - folga)) }
    for host in [hostMin, CGSize(width: 1000, height: 880), CGSize(width: 500, height: 600)] {
        #expect(largura(host) <= max(minLargura, host.width - folga))
        #expect(altura(host) <= max(minAltura, host.height - folga))
    }
}
