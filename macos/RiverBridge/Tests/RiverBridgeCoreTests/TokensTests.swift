// A escala e a paleta são as que estavam no app antes de irem para o Core (0.10.0):
// mover não pode mudar um valor. Cada um fixado à mão.

import Foundation
import Testing
@testable import RiverBridgeCore

@Test func aEscalaDeEspacoEAMesma() {
    #expect([Espaco.nenhum, Espaco.fio, Espaco.micro, Espaco.mini, Espaco.pequeno, Espaco.medio,
             Espaco.confortavel, Espaco.cartao, Espaco.largo, Espaco.secao, Espaco.janela, Espaco.respiro]
            == [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24])
}

@Test func aEscalaDeRaioEAMesma() {
    #expect([Raio.fio, Raio.mini, Raio.selo, Raio.cartao, Raio.largo, Raio.painel, Raio.janela]
            == [1, 6, 8, 12, 14, 16, 18])
}

@Test func aPaletaEAMesmaDoTema() {
    #expect(Paleta.tomada == [Paleta.RGB(0.20, 0.85, 0.62), Paleta.RGB(0.10, 0.60, 0.95)])
    #expect(Paleta.bateria == [Paleta.RGB(1.00, 0.72, 0.25), Paleta.RGB(1.00, 0.42, 0.22)])
    #expect(Paleta.baixa == [Paleta.RGB(1.00, 0.36, 0.36), Paleta.RGB(0.80, 0.12, 0.30)])
    #expect(Paleta.doEstado(naBateria: true, baixa: true) == Paleta.baixa)
    #expect(Paleta.doEstado(naBateria: true, baixa: false) == Paleta.bateria)
    #expect(Paleta.doEstado(naBateria: false, baixa: false) == Paleta.tomada)
}
