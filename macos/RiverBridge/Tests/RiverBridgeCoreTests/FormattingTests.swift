// Honesty fences: absent data renders as "—", never as a made-up value.

import Testing
@testable import RiverBridgeCore

@Test func runtimeFormatting() {
    #expect(TelemetryStore.runtimeText(9240) == "2 h 34 min")
    #expect(TelemetryStore.runtimeText(540) == "9 min")
    #expect(TelemetryStore.runtimeText(42) == "42 s")
    #expect(TelemetryStore.runtimeText(nil) == "—")
    #expect(TelemetryStore.runtimeText(-5) == "—")
}

@Test func numericFormattingWithNils() {
    #expect(TelemetryStore.percentText(87.4) == "87%")
    #expect(TelemetryStore.percentText(nil) == "—")
    #expect(TelemetryStore.wattsText(45.6) == "46 W")
    #expect(TelemetryStore.wattsText(nil) == "—")
    #expect(TelemetryStore.voltageText(229.9) == "230 V")
    #expect(TelemetryStore.voltageText(nil) == "—")
}

@Test func eventTimeTextParsesDaemonTimestamp() {
    // Daemon emits time.strftime("%Y-%m-%dT%H:%M:%S%z") — no colon in tz.
    let event = BridgeEvent(ts: "2026-08-31T15:11:30-0300", event: "POWER_LOSS", state: nil, charge: nil, reason: nil)
    #expect(event.timeText == "15:11:30")
    // Unknown format: raw value, never a fabricated time.
    let odd = BridgeEvent(ts: "ontem", event: "X", state: nil, charge: nil, reason: nil)
    #expect(odd.timeText == "ontem")
    #expect(event.dayTimeText == "31/08 · 15:11:30")
    #expect(odd.dayTimeText == "ontem")
}

@MainActor
@Test func storeAppliesStateAndEvents() {
    let store = TelemetryStore()
    store.apply(SSEMessage(
        event: "state",
        data: #"{"power": {"state": "ON_BATTERY", "states": ["ON_BATTERY"]}, "battery": {"charge_percent": 42}}"#
    ))
    #expect(store.isOnBattery)
    #expect(store.chargeText == "42%")

    store.apply(SSEMessage(
        event: "event",
        data: #"{"ts": "2026-08-31T17:00:00-0300", "event": "POWER_LOSS"}"#
    ))
    #expect(store.events.first?.event == "POWER_LOSS")
}
