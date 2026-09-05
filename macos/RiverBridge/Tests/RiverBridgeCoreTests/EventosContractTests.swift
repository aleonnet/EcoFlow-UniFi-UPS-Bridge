// O vocabulário de eventos é o MESMO dos dois lados.
//
// O serviço gera `tests/fixtures/eventos.json` a partir da lista dele; aqui se
// prova que cada nome dessa lista tem uma frase em português. Sem esta cerca, o
// serviço inventava um evento, a tela não o conhecia, e ele aparecia CRU na
// linha do tempo do dono — em maiúsculas com sublinhados. Aconteceu com oito
// dos quinze nomes (medido em 2026-09-05).

import Foundation
import Testing
@testable import RiverBridgeCore

private struct VocabularioDoServico: Decodable {
    let do_servico: [String]
    let de_dispositivo: [String]
    let por_tipo: [String: [String]]
    let todos: [String]
}

private func vocabulario() throws -> VocabularioDoServico {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("tests/fixtures/eventos.json")
    return try JSONDecoder().decode(VocabularioDoServico.self, from: Data(contentsOf: url))
}

@Test func todoEventoDoServicoTemFraseEmPortugues() throws {
    let vocab = try vocabulario()
    var sem: [String] = []
    for nome in vocab.do_servico where DeviceTypeRegistry.qualquerEvento(nome) == nil {
        sem.append(nome)
    }
    #expect(sem.isEmpty, "eventos do serviço sem frase na tela: \(sem)")
}

@Test func todoEventoDeDispositivoTemFraseEmPortugues() throws {
    let vocab = try vocabulario()
    var sem: [String] = []
    for (_, nomes) in vocab.por_tipo {
        for nome in nomes where DeviceTypeRegistry.qualquerEvento(nome) == nil {
            sem.append(nome)
        }
    }
    #expect(sem.isEmpty, "eventos de dispositivo sem frase na tela: \(sem)")
}

@Test func nenhumaFraseEOProprioNomeDoEvento() {
    // Uma "tradução" que devolve `CABO_LARGADO_AUTOMATICO` passaria pela cerca
    // acima e continuaria falando em código com o dono.
    for kind in DeviceEventKind.doServico {
        #expect(kind.long() != kind.type)
        #expect(!kind.long().contains("_"), "frase em código: \(kind.long())")
        #expect(kind.long().count > 6)
    }
}
