// O pacote de registros, sem rede e sem disco: nome, linha de comando do ditto
// e o rodapé quando o diário fica de fora.

import Foundation
import Testing
@testable import RiverBridgeCore

@Test func oNomeDoPacoteLevaOInstanteLocal() {
    var calendario = Calendar(identifier: .gregorian)
    calendario.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    let instante = DateComponents(calendar: calendario, year: 2026, month: 9, day: 6, hour: 13, minute: 5).date!
    #expect(ExportacaoDeRegistros.nomeDoPacote(agora: instante, calendario: calendario) == "RiverBridge-registros-2026-09-06-1305")
}

@Test func oDittoComprimeAPastaInteiraNumZipQueOFinderAbre() {
    let pasta = URL(fileURLWithPath: "/tmp/x/RiverBridge-registros-2026-09-06-1305")
    let zip = URL(fileURLWithPath: "/tmp/x/RiverBridge-registros-2026-09-06-1305.zip")
    let argv = ExportacaoDeRegistros.argvDoDitto(pasta: pasta, zip: zip)
    #expect(argv.first == "/usr/bin/ditto")
    #expect(argv.contains("-c") && argv.contains("-k") && argv.contains("--keepParent"))
    #expect(argv.suffix(2) == [pasta.path, zip.path])
}

@Test func semDiarioORodapeDizPorQue() {
    #expect(ExportacaoDeRegistros.rodape(diarioIncluido: true, emPortugues: true) == nil)
    #expect(ExportacaoDeRegistros.rodape(diarioIncluido: false, emPortugues: true)?.contains("sem o diário") == true)
    #expect(ExportacaoDeRegistros.rodape(diarioIncluido: false, emPortugues: false)?.contains("without the service diary") == true)
}

@Test func aFaixaSemRecorteEDesdeOInicioAteAgora() {
    let tudo = ExportacaoDeRegistros.faixa(from: nil, to: nil)
    #expect(tudo.from == 0 && tudo.to == nil)
    let dia = ExportacaoDeRegistros.faixa(from: 100, to: 200)
    #expect(dia.from == 100 && dia.to == 200)
}

/// O argv que o `comprime` de mentira recebeu; classe para o fecho `@Sendable` escrever.
private final class Caixa: @unchecked Sendable { var argv: [String] = [] }

private func pastaTemporaria() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("teste-exportacao-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func comOServicoForaDoArNenhumArquivoNasce() async throws {
    // A aceitação 6 do plano: falha de rede → nada no disco, nunca um zip parcial.
    let temporario = try pastaTemporaria()
    defer { try? FileManager.default.removeItem(at: temporario) }
    struct Fora: Error {}
    await #expect(throws: Fora.self) {
        try await ExportacaoDeRegistros.montarPacote(
            em: temporario, baixa: { _ in throw Fora() }, diario: nil, comprime: { _ in })
    }
    let itens = try FileManager.default.contentsOfDirectory(atPath: temporario.path)
    #expect(itens.isEmpty)
}

@Test func oPacoteLevaOsDoisCSVEODiarioQuandoLegivel() async throws {
    let temporario = try pastaTemporaria()
    defer { try? FileManager.default.removeItem(at: temporario) }
    let diario = temporario.appendingPathComponent("diario-de-mentira.log")
    try Data("linha\n".utf8).write(to: diario)
    let caixa = Caixa()
    let pacote = try await ExportacaoDeRegistros.montarPacote(
        em: temporario,
        baixa: { nome in Data("\u{FEFF}cabecalho-\(nome)\r\n".utf8) },
        diario: diario,
        comprime: { argv in caixa.argv = argv; try Data().write(to: URL(fileURLWithPath: argv.last!)) })
    #expect(pacote.diarioIncluido)
    #expect(pacote.zip.lastPathComponent.hasSuffix(".zip"))
    let argvVisto = caixa.argv
    #expect(argvVisto.first == "/usr/bin/ditto")
    let pasta = URL(fileURLWithPath: argvVisto[argvVisto.count - 2])
    let nomes = try FileManager.default.contentsOfDirectory(atPath: pasta.path).sorted()
    #expect(nomes == ["amostras.csv", "diario.log", "eventos.csv"])
    #expect(String(data: try Data(contentsOf: pasta.appendingPathComponent("eventos.csv")), encoding: .utf8)?.contains("eventos.csv") == true)
}

@Test func semDiarioLegivelOPacoteVaiSemEleEDiz() async throws {
    let temporario = try pastaTemporaria()
    defer { try? FileManager.default.removeItem(at: temporario) }
    let pacote = try await ExportacaoDeRegistros.montarPacote(
        em: temporario, baixa: { _ in Data() },
        diario: temporario.appendingPathComponent("nao-existe.log"), comprime: { _ in })
    #expect(!pacote.diarioIncluido)
    #expect(ExportacaoDeRegistros.rodape(diarioIncluido: pacote.diarioIncluido, emPortugues: true) != nil)
}

@Test func aExportacaoSeguinteApagaAAnterior() async throws {
    let temporario = try pastaTemporaria()
    defer { try? FileManager.default.removeItem(at: temporario) }
    let velha = temporario.appendingPathComponent(ExportacaoDeRegistros.prefixoDaPastaDeTrabalho + "velha", isDirectory: true)
    try FileManager.default.createDirectory(at: velha, withIntermediateDirectories: true)
    let alheia = temporario.appendingPathComponent("outra-coisa", isDirectory: true)
    try FileManager.default.createDirectory(at: alheia, withIntermediateDirectories: true)
    _ = try await ExportacaoDeRegistros.montarPacote(em: temporario, baixa: { _ in Data() }, diario: nil, comprime: { _ in })
    #expect(!FileManager.default.fileExists(atPath: velha.path))
    #expect(FileManager.default.fileExists(atPath: alheia.path))
    let nossas = try FileManager.default.contentsOfDirectory(atPath: temporario.path)
        .filter { $0.hasPrefix(ExportacaoDeRegistros.prefixoDaPastaDeTrabalho) }
    #expect(nossas.count == 1)
}
