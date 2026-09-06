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
