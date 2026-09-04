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
    // Sem sequência, a identidade junta o que distingue duas linhas do histórico:
    // instante, tipo, dono e detalhe (dois dispositivos do mesmo tipo colidiam).
    #expect(velho.id == "2026-09-03T10:00:00-0300-COMM_LOST----")
}

@MainActor
@Test func readingsShownFollowWhatTheDevicePublishes() {
    // O River 3 Plus publica bateria e autonomia pelo cabo, e NÃO publica uso
    // nem tensão de saída (medido no Mac mini em 2026-09-04). A tela mostra o
    // que chega, em vez de fileiras de trações fixos.
    let store = TelemetryStore()
    store.apply(SSEMessage(
        event: "state",
        data: #"{"power": {"state": "ON_BATTERY"}, "battery": {"charge_percent": 97, "voltage_v": 13.0}}"#
    ))
    #expect(store.temUsoESaida == false)
    #expect(store.temTensaoDaBateria)
    #expect(store.batteryVoltageText == "13 V")

    // Um no-break que publica uso volta a mostrar uso e saída.
    let completo = TelemetryStore()
    completo.apply(SSEMessage(
        event: "state",
        data: #"{"power": {"state": "ONLINE", "load_percent": 12, "output_voltage_v": 120}, "battery": {"charge_percent": 80}}"#
    ))
    #expect(completo.temUsoESaida)
    #expect(completo.loadText == "12%")
}

@MainActor
@Test func clearingEventsForgetsThemAndTellsTheScreens() {
    // Limpar apagava o banco e a lista ficava na tela até chegar evento novo
    // (medido com o dono em 2026-09-04). Agora a memória esquece junto e o
    // contador avisa quem lista eventos para recarregar.
    let store = TelemetryStore()
    store.apply(SSEMessage(event: "event",
                           data: #"{"ts": "2026-09-04T00:00:05-0300", "event": "POWER_LOSS"}"#))
    store.apply(SSEMessage(event: "event",
                           data: #"{"ts": "2026-09-04T02:00:00-0300", "event": "COMM_LOST"}"#))
    #expect(store.events.count == 2)
    let geracao = store.eventsGeneration

    // Limpa só o que é anterior à 01:00 daquele dia.
    var partes = DateComponents()
    partes.year = 2026; partes.month = 9; partes.day = 4; partes.hour = 1
    partes.timeZone = TimeZone(secondsFromGMT: -3 * 3600)
    let corte = Calendar(identifier: .gregorian).date(from: partes)!
    store.forgetEvents(upTo: corte)

    #expect(store.events.map(\.event) == ["COMM_LOST"])   // o de depois fica
    #expect(store.eventsGeneration == geracao + 1)        // as telas recarregam
}

@MainActor
@Test func outletsFromTheSerialPortReachTheScreen() {
    // O River publica consumo por tomada pela porta serial do próprio cabo; o
    // serviço junta isso ao estado. A tela mostra o que chegou, e "—" no que não.
    let store = TelemetryStore()
    store.apply(SSEMessage(event: "state", data: #"""
    {"power": {"state": "ONLINE", "output_power_w": 110.6, "input_power_w": 110.6},
     "battery": {"charge_percent": 100},
     "outlets": {"total_w": 110.6, "input_w": 110.6, "ac_w": 110.6, "dc_w": 0,
                 "usb_a_w": 0, "usb_c_w": null, "line_frequency_hz": 60}}
    """#))
    #expect(store.temTomadas)
    #expect(store.powerText == "111 W")
    #expect(store.inputPowerText == "111 W")
    let rotulos = store.tomadas.map(\.valor)
    #expect(rotulos == ["111 W", "0 W", "0 W", "—"])   // o ausente vira traço, não zero

    // Serviço fora do ar: nada de número congelado.
    store.markServiceDownForTesting("sem comunicação")
    #expect(store.temTomadas == false)
    #expect(store.inputPowerText == "—")
    #expect(store.tomadas.isEmpty)
}

@MainActor
@Test func aDeviceWithoutOutletsShowsNoOutletSection() {
    let store = TelemetryStore()
    store.apply(SSEMessage(event: "state",
                           data: #"{"power": {"state": "ONLINE"}, "battery": {"charge_percent": 90}}"#))
    #expect(store.temTomadas == false)
    #expect(store.tomadas.isEmpty)
}

@Test func machineDetailFromTheServiceNeverReachesTheScreenRaw() {
    // O serviço grava o detalhe dos eventos do bridge em forma de máquina
    // (`estado=ON_BATTERY carga=42`). Isso é bom no registro e péssimo na tela:
    // a linha "Detalhe" mostrava o token cru duas linhas abaixo do mesmo estado
    // já escrito em português.
    let linha = EventLogRow(ts: 1788490805, type: "POWER_LOSS",
                            detail: "estado=ON_BATTERY carga=42", device: nil)
    let evento = linha.asBridgeEvent
    #expect(evento.state == "ON_BATTERY")      // vai para a linha "Estado", traduzida
    #expect(evento.charge == 42)               // e para a linha "Bateria"
    #expect(evento.reason == nil)              // nada de token cru em "Detalhe"

    // Detalhe que NÃO é desse formato continua indo inteiro (motivo de falha, host).
    let outra = EventLogRow(ts: 1788490805, type: "UDR7_SHUTDOWN_FAILED",
                            detail: "host_desconhecido", device: "udr7")
    #expect(outra.asBridgeEvent.reason == "host_desconhecido")
    #expect(outra.asBridgeEvent.state == nil)
}

@Test func twoDevicesOfTheSameTypeInTheSameSecondKeepBothRows() {
    // Dois dispositivos do mesmo tipo emitem o MESMO tipo de evento no mesmo
    // segundo. Com a identidade antiga (instante + tipo) as duas linhas
    // colidiam e a lista mostrava uma só.
    let a = EventLogRow(ts: 1788490805, type: "SSH_HOST_SHUTDOWN_DRYRUN",
                        detail: "ensaio", device: "sshhost_1")
    let b = EventLogRow(ts: 1788490805, type: "SSH_HOST_SHUTDOWN_DRYRUN",
                        detail: "ensaio", device: "sshhost_2")
    #expect(a.id != b.id)
    #expect(a.asBridgeEvent.id != b.asBridgeEvent.id)
}
