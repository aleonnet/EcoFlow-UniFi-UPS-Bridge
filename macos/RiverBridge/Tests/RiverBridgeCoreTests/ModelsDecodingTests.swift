// Contract tests: decode the SAME fixtures the Python side generates and
// asserts against (tests/fixtures/*.json at the repo root).

import Foundation
import Testing
@testable import RiverBridgeCore

private func fixtureURL(_ name: String) -> URL {
    // .../macos/RiverBridge/Tests/RiverBridgeCoreTests/ -> repo root
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // file
        .deletingLastPathComponent()  // RiverBridgeCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // RiverBridge
        .deletingLastPathComponent()  // macos
        .appendingPathComponent("tests/fixtures/\(name).json")
}

@Test func decodeOnlineFixture() throws {
    let data = try Data(contentsOf: fixtureURL("state_online"))
    let state = try JSONCoding.decoder().decode(UpsState.self, from: data)
    #expect(state.power?.state == "ONLINE")
    #expect(state.power?.states == ["ONLINE", "CHARGING"])
    #expect(state.battery?.chargePercent == 87.0)
    #expect(state.battery?.runtimeSeconds == 3600.0)
    #expect(state.power?.outputPowerW == 45.0)
    #expect(state.identity?.model == "RIVER 3 Plus")
    #expect(state.health?.communicationOk == true)
}

@Test func decodeNullsFixtureStaysNil() throws {
    let data = try Data(contentsOf: fixtureURL("state_nulls"))
    let state = try JSONCoding.decoder().decode(UpsState.self, from: data)
    #expect(state.power?.state == "UNKNOWN")
    #expect(state.battery?.chargePercent == nil)
    #expect(state.power?.inputVoltageV == nil)
    #expect(state.identity?.serial == nil)
    #expect(state.health?.communicationOk == false)
    #expect(state.timestamp == nil)
}


@Test func decodeTheSerialDetailsInOutlets() throws {
    // 0.9.0: os campos novos do bloco `outlets` (o contrato em docs/reference/api-local.md).
    let json = """
    {"outlets": {"total_w": 110.6, "input_solar_dc_w": 0.0, "design_capacity_mah": 12800,
                 "time_to_full_minutes": null, "battery_temperature_c": 34.0,
                 "system_temperature_c": 25.0, "temperatures_c": [25.0, 34.0, 25.0, 25.0]}}
    """
    let state = try JSONCoding.decoder().decode(UpsState.self, from: Data(json.utf8))
    #expect(state.outlets?.designCapacityMah == 12800)
    #expect(state.outlets?.timeToFullMinutes == nil)
    #expect(state.outlets?.systemTemperatureC == 25.0)
    #expect(state.outlets?.temperaturesC == [25.0, 34.0, 25.0, 25.0])
}

@Test func decodeHealthArmado() throws {
    // 0.9.0: a instância armada, com alcance provado — o fixture da captura do cartão.
    let data = try Data(contentsOf: fixtureURL("health_armado"))
    let chain = try JSONCoding.decoder().decode(HealthChain.self, from: data)
    let detail = try #require(chain.pluginDetail(id: "udr7"))
    #expect(detail.state == "armado_nao_verificado")
    #expect(detail.enabled == true && detail.dryRun == false)
    #expect(detail.alcanceVerificado == true)
    #expect(detail.warnings == ["lock_open", "margin_unknown"])
}

@Test func decodeHealthWithUdr7Detail() throws {
    let data = try Data(contentsOf: fixtureURL("health_udr7"))
    let chain = try JSONCoding.decoder().decode(HealthChain.self, from: data)
    #expect(chain.unifi == "sem_caminho_nativo_documentado")
    #expect(chain.udr7 == "fonte_nao_real")
    let d = try #require(chain.udr7Detail)
    #expect(d.dryRun == true)
    #expect(d.source == "sintetica")
    #expect(d.sourceDetail == "telemetria_sintetica")
    #expect(d.warnings == ["lock_open"])
    #expect(d.sshBinary == "/usr/bin/ssh")
    #expect(d.marginEstimateS == nil)
    #expect(d.lastEvent == "UDR7_SHUTDOWN_DRYRUN")
    // O nome do dispositivo (P1): a fixture traz o padrão do daemon.
    #expect(d.name == "UDR7")
}

@Test func decodeLegacyHealthWithoutUdr7StaysNil() throws {
    // Daemons before the phase: no udr7 keys at all -> nil, never a fabricated state.
    let data = try Data(contentsOf: fixtureURL("health_legacy"))
    let chain = try JSONCoding.decoder().decode(HealthChain.self, from: data)
    #expect(chain.udr7 == nil)
    #expect(chain.udr7Detail == nil)
    #expect(chain.unifi == "pendente_fase_3")
}

@Test func configValueAccessors() {
    #expect(ConfigValue.int(22).stringValue == "22")
    #expect(ConfigValue.bool(true).stringValue == "1")
    #expect(ConfigValue.string("192.0.2.1").stringValue == "192.0.2.1")
    #expect(ConfigValue.bool(false).boolValue == false)
    #expect(ConfigValue.int(1).boolValue == true)
    #expect(ConfigValue.string("0").boolValue == false)
    #expect(ConfigValue.string("talvez").boolValue == nil)
}

    @Test("o alcance provado chega do serviço para a tela")
    func reachStateDecodes() throws {
        let json = """
        {"state":"dry_run","alcance_verificado":true,"alcance_modelo":"UniFi Dream Router 7"}
        """
        let d = try JSONCoding.decoder().decode(DeviceDetail.self, from: Data(json.utf8))
        #expect(d.alcanceVerificado == true)
        #expect(d.alcanceModelo == "UniFi Dream Router 7")
    }

    @Test("o resultado do teste de conexão decodifica, com e sem alcance")
    func reachTestDecodes() throws {
        let ok = """
        {"alcance":true,"resposta":{"probe":"/sbin/ubnt-systool","model":"UDR7","firmware":"5.1.31"}}
        """
        let t = try JSONCoding.decoder().decode(AcessoTestado.self, from: Data(ok.utf8))
        #expect(t.alcance && t.resposta?.model == "UDR7")
        let nao = #"{"alcance":false,"resposta":{},"motivo":"o console não respondeu"}"#
        let n = try JSONCoding.decoder().decode(AcessoTestado.self, from: Data(nao.utf8))
        #expect(!n.alcance && n.motivo?.isEmpty == false)
    }
