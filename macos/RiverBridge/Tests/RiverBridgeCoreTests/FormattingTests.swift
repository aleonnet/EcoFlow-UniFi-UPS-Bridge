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
    // Unknown format: raw value, never a fabricated time.
    let odd = BridgeEvent(ts: "ontem", event: "X", state: nil, charge: nil, reason: nil)
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
    // Mapped ts must PARSE (dayTimeText falls back to the raw string only on
    // unknown formats — equality here would mean the mapping is broken).
    #expect(event.dayTimeText != event.ts)
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

@Test func bootResolutionSeamWinsOnceAndPersistedOtherwise() {
    // Seam wins at boot only; persisted value rules without it; garbage falls
    // back to defaults. (Class fence for the argument-domain poisoning bugs.)
    #expect(AppPrefs.resolveLanguage(persisted: "enUS", seam: nil) == .enUS)
    #expect(AppPrefs.resolveLanguage(persisted: "enUS", seam: "ptBR") == .ptBR)
    #expect(AppPrefs.resolveLanguage(persisted: nil, seam: nil) == .system)
    #expect(AppPrefs.resolveLanguage(persisted: "lixo", seam: "lixo") == .system)
    #expect(AppPrefs.resolveTheme(persisted: "dark", seam: nil) == .dark)
    #expect(AppPrefs.resolveTheme(persisted: "dark", seam: "light") == .light)
    #expect(AppPrefs.resolveTheme(persisted: nil, seam: nil) == .auto)
    #expect(AppPrefs.resolveTheme(persisted: "lixo", seam: "lixo") == .auto)
}

@MainActor
@Test func derivedTextsAreDashUnlessLive() {
    // Com o serviço fora do ar, a última leitura NÃO é o presente: números
    // congelados na tela já fizeram o dono acreditar que o River estava vivo.
    let store = TelemetryStore()
    store.apply(SSEMessage(
        event: "state",
        data: #"""
        {"power": {"state": "ON_BATTERY", "load_percent": 12, "output_power_w": 80, "output_voltage_v": 120},
         "battery": {"charge_percent": 42, "runtime_seconds": 600}}
        """#
    ))
    #expect(store.chargeText == "42%")
    #expect(store.runtimeText == "10 min")
    #expect(store.loadText == "12%")
    #expect(store.powerText == "80 W")
    #expect(store.outputVoltageText == "120 V")
    #expect(store.chargeFraction != nil)

    store.markServiceDownForTesting("Sem comunicação com o serviço")
    #expect(store.chargeText == "—")
    #expect(store.runtimeText == "—")
    #expect(store.loadText == "—")
    #expect(store.powerText == "—")
    #expect(store.outputVoltageText == "—")
    #expect(store.stateLabel == "—")
    #expect(store.chargeFraction == nil)
}

@MainActor
@Test func applyMarksTheStoreLive() {
    // Um quadro recebido é vida: sem isto os textos nasceriam mudos para quem
    // recebe eventos fora do laço do stream.
    let store = TelemetryStore()
    #expect(store.phase == .connecting)
    store.apply(SSEMessage(event: "state", data: #"{"battery": {"charge_percent": 7}}"#))
    #expect(store.phase == .live)
    #expect(store.chargeText == "7%")
}

@Test func eventSequenceDecodesAndIdentifiesTheRow() throws {
    // Dois eventos do mesmo tipo no mesmo segundo: sem a sequência, um sumia da
    // lista porque os dois disputavam a mesma identidade.
    let decoder = JSONCoding.decoder()
    let a = try decoder.decode(BridgeEvent.self, from: Data(
        #"{"ts": "2026-09-03T10:00:00-0300", "event": "COMM_LOST", "seq": 101}"#.utf8))
    let b = try decoder.decode(BridgeEvent.self, from: Data(
        #"{"ts": "2026-09-03T10:00:00-0300", "event": "COMM_LOST", "seq": 102}"#.utf8))
    #expect(a.seq == 101)
    #expect(a.id != b.id)
    // Serviço antigo (sem sequência): a identidade antiga continua servindo.
    let velho = try decoder.decode(BridgeEvent.self, from: Data(
        #"{"ts": "2026-09-03T10:00:00-0300", "event": "COMM_LOST"}"#.utf8))
    #expect(velho.seq == nil)
    #expect(velho.id == "2026-09-03T10:00:00-0300COMM_LOST")
}
