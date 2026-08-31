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
