// Honesty fences: absent data renders as "—", never as a made-up value.

import Foundation
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
    #expect(store.beat == 1)   // one applied reading = one heartbeat

    store.apply(SSEMessage(
        event: "event",
        data: #"{"ts": "2026-08-31T17:00:00-0300", "event": "POWER_LOSS"}"#
    ))
    #expect(store.events.first?.event == "POWER_LOSS")
}

@Test func eventLogRowDecodesAndMapsToBridgeEvent() throws {
    let json = #"{"rows": [{"ts": 1756677090, "type": "POWER_LOSS", "detail": null}]}"#
    let resp = try JSONCoding.decoder().decode(EventsLogResponse.self, from: Data(json.utf8))
    #expect(resp.rows.first?.type == "POWER_LOSS")
    let event = resp.rows.first!.asBridgeEvent
    #expect(event.event == "POWER_LOSS")
    // Mapped ts must PARSE (timeText falls back to the raw string only on
    // unknown formats — equality here would mean the mapping is broken).
    #expect(event.timeText != event.ts)
    #expect(event.reason == nil)
}

@Test @MainActor func languagePickerWinsOverDefaultsShadowing() {
    // The refuting injection for the owner's bug: even if UserDefaults reads
    // are shadowed (argument domain), the live picker choice must apply.
    let before = AppPrefs.shared.language
    AppPrefs.shared.language = .enUS
    #expect(L10n.t("Eventos", "Events") == "Events")
    AppPrefs.shared.language = .ptBR
    #expect(L10n.t("Eventos", "Events") == "Eventos")
    AppPrefs.shared.language = before
}
