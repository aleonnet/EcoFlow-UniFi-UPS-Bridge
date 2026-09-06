// O retrato do widget (0.10.0): nasce do estado sem inventar, pede recarga só em
// mudança de significado, envelhece em três faixas, e o store só grava quando muda.

import Foundation
import Testing
@testable import RiverBridgeCore

private func estado(_ json: String) throws -> UpsState {
    try JSONCoding.decoder().decode(UpsState.self, from: Data(json.utf8))
}

private let naTomada = """
{"power": {"state": "ONLINE", "states": ["ONLINE", "CHARGING"], "input_power_w": 69.7, "output_power_w": 64.8},
 "battery": {"charge_percent": 100.0, "runtime_seconds": 151740.0}, "health": {"low_battery": false}}
"""
private let naBateria = """
{"power": {"state": "ON_BATTERY", "states": ["ON_BATTERY", "DISCHARGING"], "output_power_w": 64.8},
 "battery": {"charge_percent": 42.0, "runtime_seconds": 5400.0}, "health": {"low_battery": false}}
"""
private let t0 = Date(timeIntervalSince1970: 1_788_700_000)

private func retrato(_ json: String, carga: Double? = nil, agora: Date = t0) throws -> RetratoDoWidget {
    var r = RetratoDoWidget.de(estado: try estado(json), viva: true, emPortugues: true, agora: agora)
    if let carga { r.cargaPct = carga }
    return r
}

@Test func oRetratoNasceDoEstadoSemInventar() throws {
    let r = try retrato(naTomada)
    #expect(r.cargaPct == 100 && r.autonomiaS == 151740 && r.estado == "ONLINE" && r.carregando)
    #expect(r.entradaW == 69.7 && r.consumoW == 64.8 && !r.bateriaBaixa && r.servicoNoAr && r.emPortugues)
    // Serviço parado: nada de número, e "no ar" falso — a última leitura não é o presente.
    let morto = RetratoDoWidget.de(estado: try estado(naTomada), viva: false, emPortugues: false, agora: t0)
    #expect(morto.cargaPct == nil && morto.autonomiaS == nil && morto.estado == nil && !morto.servicoNoAr && !morto.emPortugues)
}

@Test func naoRecarregaSemMudanca() throws {
    let a = try retrato(naTomada)
    var b = try retrato(naTomada, agora: t0.addingTimeInterval(2))
    #expect(!RetratoDoWidget.deveRecarregar(anterior: a, novo: b))
    // Ruído de 1 ponto dentro do mesmo degrau de 10: não é mudança de significado.
    b.cargaPct = 99
    let c = try retrato(naTomada, carga: 91)
    #expect(!RetratoDoWidget.deveRecarregar(anterior: c, novo: b))
    // Mas o arquivo é outro conteúdo (a carga mudou) — a hora, sozinha, não é.
    #expect(!a.mesmoConteudo(que: b))
    #expect(a.mesmoConteudo(que: try retrato(naTomada, agora: t0.addingTimeInterval(60))))
}

@Test func recarregaNosQuatroGatilhos() throws {
    let base = try retrato(naTomada, carga: 95)
    #expect(RetratoDoWidget.deveRecarregar(anterior: nil, novo: base))                       // o primeiro
    #expect(RetratoDoWidget.deveRecarregar(anterior: base, novo: try retrato(naBateria, carga: 95)))   // fonte
    var baixa = base; baixa.bateriaBaixa = true
    #expect(RetratoDoWidget.deveRecarregar(anterior: base, novo: baixa))                     // bateria baixa
    var morto = base; morto.servicoNoAr = false
    #expect(RetratoDoWidget.deveRecarregar(anterior: base, novo: morto))                     // serviço
    #expect(RetratoDoWidget.deveRecarregar(anterior: base, novo: try retrato(naTomada, carga: 89)))    // degrau 90 → 80
}

@Test func idadeDoRetratoNasTresFaixas() throws {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    let lido = DateComponents(calendar: cal, year: 2026, month: 9, day: 6, hour: 14, minute: 20).date!
    let r = try retrato(naTomada, agora: lido)
    #expect(IdadeDoRetrato.para(retrato: r, agora: lido.addingTimeInterval(60), calendario: cal) == .valores)
    #expect(IdadeDoRetrato.para(retrato: r, agora: lido.addingTimeInterval(10 * 60), calendario: cal) == .valoresComHora("14:20"))
    #expect(IdadeDoRetrato.para(retrato: nil, agora: lido, calendario: cal) == .traco)
}

@Test func depoisDeMeiaHoraETraco() throws {
    let r = try retrato(naTomada)
    #expect(IdadeDoRetrato.para(retrato: r, agora: t0.addingTimeInterval(31 * 60)) == .traco)
    #expect(IdadeDoRetrato.para(retrato: r, agora: t0.addingTimeInterval(29 * 60)) != .traco)
}

@Test func gravaELeNoTemporario() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("retrato-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(RetratoDoWidget.nomeDoArquivo)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let r = try retrato(naBateria)
    try r.gravar(em: url)
    let texto = try String(contentsOf: url, encoding: .utf8)
    #expect(texto.contains("\"carga_pct\":42") && texto.contains("\"estado\":\"ON_BATTERY\""))   // snake_case, como a API
    #expect(RetratoDoWidget.ler(de: url) == r)
}

@Test @MainActor func oStoreComRetratoNilNaoGravaEComURLSoGravaQuandoMuda() throws {
    let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("retrato-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: pasta) }
    let url = pasta.appendingPathComponent(RetratoDoWidget.nomeDoArquivo)
    let mudo = TelemetryStore(arguments: [], environment: [:])
    mudo.apply(SSEMessage(event: "state", data: naTomada))
    #expect(!FileManager.default.fileExists(atPath: url.path))

    var recargas = 0
    let store = TelemetryStore(arguments: [], environment: [:], retrato: url, aoRecarregarWidget: { recargas += 1 })
    store.apply(SSEMessage(event: "state", data: naTomada))
    let primeiro = try #require(RetratoDoWidget.ler(de: url))
    // Duas mudanças de significado no primeiro quadro: o serviço "subiu" (fase
    // .connecting → .live, retrato sem números) e depois a carga apareceu.
    #expect(primeiro.cargaPct == 100 && recargas == 2)
    // O mesmo estado, segundos depois: o arquivo NÃO é regravado (a hora fica a do primeiro).
    store.apply(SSEMessage(event: "state", data: naTomada))
    #expect(RetratoDoWidget.ler(de: url)?.quando == primeiro.quando && recargas == 2)
    // Na bateria: conteúdo novo E significado novo.
    store.apply(SSEMessage(event: "state", data: naBateria))
    #expect(RetratoDoWidget.ler(de: url)?.estado == "ON_BATTERY" && recargas == 3)
}
