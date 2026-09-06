// A legenda do histograma de eventos, testada sem janela. A cerca que importa:
// toda barra tem a sua cor no domínio — o Swift Charts derruba o processo
// quando não tem (medido em 2026-09-06; ver LegendaDeEventos.swift).

import Foundation
import Testing
@testable import RiverBridgeCore

private let dispositivos = [
    DeviceInstance(id: "udr7", type: "udr7_ssh", name: "Roteador"),
]
private let nomes = DeviceNames(byPluginID: ["udr7": "Roteador"])

/// O recorte que derrubou o aplicativo no Mac mini (diário de 7 dias, medido
/// em 2026-09-06): eventos do bridge, do dispositivo e do CABO — mais dois que
/// nenhuma lista conhece: um tipo novo e um evento de instância já removida.
private let eventosDoRecorte: [(tipo: String, dispositivo: String?)] = [
    ("COMM_RESTORED", nil), ("COMM_LOST", nil),
    ("CABO_LARGADO_AUTOMATICO", nil), ("CABO_RETOMADO_AUTOMATICO", nil),
    ("UDR7_ARMED", "udr7"), ("UDR7_DISARMED", "udr7"),
    ("UDR7_ARMED", "udr7-antigo-removido"),
    // Host SSH removido: o único caso em que o nome padrão do tipo muda com o
    // idioma ("Servidor SSH" / "SSH server") — é por aqui que o idioma global
    // ainda vazava (revisão fria da 0.8.7).
    ("SSH_HOST_ARMED", "nas-removido"),
    ("TIPO_QUE_A_TELA_NAO_CONHECE", nil),
]

@Test func todaBarraTemASuaCorNoDominio() {
    // Idioma explícito nos dois lados: é estado global que outro teste alterna em
    // paralelo, e a cerca é sobre o domínio, não sobre o idioma.
    for emPortugues in [true, false] {
        let chaves = LegendaDeEventos.chaves(eventos: eventosDoRecorte, nomes: nomes,
                                             dispositivos: dispositivos, emPortugues: emPortugues)
        let dominio = chaves.map(\.rotulo)
        let unicos = DeviceNames.uniqueLabels(instances: dispositivos)
        for evento in eventosDoRecorte {
            let rotulo = LegendaDeEventos.rotulo(tipo: evento.tipo, dispositivo: evento.dispositivo,
                                                 rotulosUnicos: unicos, nomes: nomes, dispositivos: dispositivos,
                                                 emPortugues: emPortugues)
            #expect(dominio.contains(rotulo), "barra sem cor no domínio: \(evento.tipo) (\(rotulo))")
        }
        // O Charts também exige domínio sem repetição.
        #expect(Set(dominio).count == dominio.count)
        // E o idioma pedido é o idioma entregue, também no nome padrão do tipo.
        #expect(dominio.contains(emPortugues ? "Servidor SSH armado" : "SSH server armed"))
    }
}

@Test func aOrdemEBridgeDepoisDispositivosDepoisServico() {
    let chaves = LegendaDeEventos.chaves(eventos: eventosDoRecorte, nomes: nomes,
                                         dispositivos: dispositivos, emPortugues: true)
    let tipos = chaves.map(\.tipo)
    let comm = try! #require(tipos.firstIndex(of: "COMM_LOST"))
    let udr7 = try! #require(tipos.firstIndex(of: "UDR7_ARMED"))
    let cabo = try! #require(tipos.firstIndex(of: "CABO_LARGADO_AUTOMATICO"))
    let novo = try! #require(tipos.firstIndex(of: "TIPO_QUE_A_TELA_NAO_CONHECE"))
    #expect(comm < udr7 && udr7 < cabo && cabo < novo)
    // A cor do "Outro" sai do tipo que o produziu, não de um tipo vazio.
    #expect(chaves.last?.tipo == "TIPO_QUE_A_TELA_NAO_CONHECE")
}

@Test func semEventoNenhumALegendaEVazia() {
    #expect(LegendaDeEventos.chaves(eventos: [], nomes: nomes, dispositivos: dispositivos).isEmpty)
}
