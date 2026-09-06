// A folha do River, testada sem janela: os quatro grupos, o traço onde não há
// leitura, e o tempo para carga completa que é ausência quando não carrega.

import Foundation
import Testing
@testable import RiverBridgeCore

private func estado(_ json: String) throws -> UpsState {
    try JSONCoding.decoder().decode(UpsState.self, from: Data(json.utf8))
}

private let vivo = """
{"identity": {"name": "river-office", "manufacturer": "EcoFlow", "model": "EF-UPS-RIVER 3 Plus", "serial": "R631ZBBAWH270046"},
 "power": {"state": "ONLINE", "states": ["ONLINE"], "input_power_w": 110.6, "line_frequency_hz": 60.0},
 "battery": {"charge_percent": 100.0, "runtime_seconds": 9240.0, "temperature_c": 34.0},
 "outlets": {"total_w": 110.6, "input_w": 110.6, "input_ac_w": 110.6, "input_solar_dc_w": 0.0,
             "ac_w": 110.6, "dc_w": 0.0, "usb_a_w": 0.0, "usb_c_w": 0.0, "line_frequency_hz": 60.0,
             "design_capacity_mah": 12800, "time_to_full_minutes": null,
             "battery_temperature_c": 34.0, "system_temperature_c": 25.0, "temperatures_c": [25.0, 34.0, 25.0, 25.0]}}
"""

private func linha(_ folha: FolhaDoRiver, _ rotulo: String) -> FolhaDoRiver.Linha? {
    folha.grupos.flatMap(\.linhas).first { $0.rotulo == rotulo }
}

@Test func aFolhaTemOsQuatroGruposComOQueORiverPublica() throws {
    let folha = FolhaDoRiver(estado: try estado(vivo), viva: true, emPortugues: true)
    #expect(folha.grupos.map(\.titulo) == ["Aparelho", "Potência", "Bateria", "Rede"])
    #expect(folha.titulo == "EF-UPS-RIVER 3 Plus" && folha.serie == "R631ZBBAWH270046")
    #expect(linha(folha, "Capacidade de projeto")?.valor == "12.800 mAh")
    #expect(linha(folha, "Entrada da rede")?.valor == "111 W")
    #expect(linha(folha, "Entrada solar/DC")?.valor == "0 W")
    #expect(linha(folha, "Temperatura da bateria")?.valor == "34 °C")
    #expect(linha(folha, "Temperatura do sistema")?.valor == "25 °C")
    #expect(linha(folha, "Frequência")?.valor == "60 Hz")
    #expect(linha(folha, "Situação")?.valor == "Na tomada")
    #expect(linha(folha, "Autonomia")?.valor == "2 h 34 min")
}

@Test func tempoParaCargaSemLeituraETraco() throws {
    // Aparelho cheio na tomada: o serviço publica null, e a folha diz por quê.
    let folha = FolhaDoRiver(estado: try estado(vivo), viva: true, emPortugues: true)
    let tempo = try #require(linha(folha, "Tempo para carga completa"))
    #expect(tempo.valor == "—")
    #expect(tempo.nota == "só aparece enquanto carrega")
    #expect(FolhaDoRiver.minutesText(nil) == "—")
    #expect(FolhaDoRiver.minutesText(90) == "1 h 30 min")
    #expect(FolhaDoRiver.minutesText(45) == "45 min")
}

@Test func semLeituraVivaTudoETraco() throws {
    // O serviço parado (ou o aparelho mudo) não mostra a última leitura como presente.
    let folha = FolhaDoRiver(estado: try estado(vivo), viva: false, emPortugues: true)
    #expect(folha.titulo == "River" && folha.serie == "—")
    for grupo in folha.grupos { for l in grupo.linhas { #expect(l.valor == "—", "\(l.rotulo)") } }
    #expect(linha(folha, "Tempo para carga completa")?.nota == nil)
}

@Test func osFormatadoresNosDoisIdiomas() {
    #expect(FolhaDoRiver.mahText(12800, emPortugues: true) == "12.800 mAh")
    #expect(FolhaDoRiver.mahText(12800, emPortugues: false) == "12,800 mAh")
    #expect(FolhaDoRiver.mahText(900, emPortugues: true) == "900 mAh")
    #expect(FolhaDoRiver.mahText(nil, emPortugues: true) == "—")
    #expect(FolhaDoRiver.celsiusText(33.6) == "34 °C" && FolhaDoRiver.celsiusText(nil) == "—")
    #expect(FolhaDoRiver.hertzText(60.0) == "60 Hz")
    #expect(FolhaDoRiver.situacaoText("ON_BATTERY", emPortugues: false) == "On battery")
    let en = FolhaDoRiver(estado: nil, viva: true, emPortugues: false)
    #expect(en.grupos.map(\.titulo) == ["Device", "Power", "Battery", "Grid"])
}

@Test func semSerialONaoCarregarNaoEAfirmado() throws {
    // Serviço vivo, porta serial muda (`outlets` nulo): traço sem a nota — a
    // nota afirmaria "não está carregando" sem leitura nenhuma.
    let semSerial = try estado("""
    {"power": {"state": "ONLINE", "states": ["ONLINE"]}, "battery": {"charge_percent": 100.0}, "outlets": null}
    """)
    let folha = FolhaDoRiver(estado: semSerial, viva: true, emPortugues: true)
    let tempo = try #require(linha(folha, "Tempo para carga completa"))
    #expect(tempo.valor == "—" && tempo.nota == nil)
}
