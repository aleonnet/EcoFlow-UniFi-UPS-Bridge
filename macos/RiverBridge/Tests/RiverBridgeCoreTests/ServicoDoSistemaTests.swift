// A tela do serviço: o que ela diz, e quando cada botão pode ser tocado.
//
// Estes testes existem por uma razão só: `register()` NÃO termina o trabalho.
// A Apple é literal — "the system won't bootstrap the LaunchDaemon until an
// admin approves the LaunchDaemon in System Preferences". Uma tela que dissesse
// "instalado" nesse ponto estaria mentindo, e o dono descobriria isso na
// próxima queda de energia.

import Foundation
import Testing
@testable import RiverBridgeCore

@Test func aTelaNuncaDizInstaladoAntesDaAprovacao() {
    let esperando = EstadoDoServico.esperandoAprovacao
    #expect(esperando.titulo.contains("aprovar"))
    #expect(esperando.explicacao.contains("Ajustes do Sistema"))
    #expect(esperando.explicacao.contains("não está sendo vigiada"))
    #expect(esperando.mostraAjustesDoSistema)
}

@Test func instalarSoEOferecidoQuandoFazSentido() {
    #expect(EstadoDoServico.naoInstalado.podeInstalar)
    #expect(EstadoDoServico.desligadoPeloSistema.podeInstalar)
    // Já registrado: instalar de novo é o erro que a documentação chama de
    // "attempted to reregister after it was already registered".
    #expect(!EstadoDoServico.esperandoAprovacao.podeInstalar)
    #expect(!EstadoDoServico.noAr.podeInstalar)
}

@Test func comOServicoInstaladoPorForaATelaRecusaEExplica() {
    // Dois serviços vigiando o mesmo River disputam o cabo e a porta, e o que
    // perder fica mudo sem ninguém perceber.
    let cruzado = EstadoDoServico.instaladoPelaLinhaDeComando
    #expect(!cruzado.podeInstalar)
    #expect(!cruzado.podeRemover)
    #expect(cruzado.explicacao.contains("mesmo cabo"))
    #expect(cruzado.explicacao.contains("scripts"))
}

@Test func removerSoAparecePraQuemTemOQueRemover() {
    #expect(!EstadoDoServico.naoInstalado.podeRemover)
    #expect(EstadoDoServico.noAr.podeRemover)
    #expect(EstadoDoServico.esperandoAprovacao.podeRemover)
}

@Test func aConfirmacaoNomeiaTudoQueSai() {
    let completa = RemocaoCompleta(estadoExiste: true, configuracaoDoNutExiste: true)
    #expect(completa.itens.count == 5)
    #expect(completa.aviso.contains("chave"))
    #expect(completa.aviso.contains("senhas"))
    #expect(completa.aviso.contains("histórico"))
    #expect(completa.aviso.contains("sem volta"))
    // O programa em si NÃO sai por aqui: quem o tira é o Lixo, e a tela diz isso
    // para o dono não ficar procurando.
    #expect(completa.aviso.contains("Aplicativos"))
}

@Test func semEstadoNoDiscoAConfirmacaoNaoPrometeApagarOQueNaoExiste() {
    let magra = RemocaoCompleta(estadoExiste: false, configuracaoDoNutExiste: false)
    #expect(magra.itens == ["o registro do serviço no sistema (ele para de subir no boot)"])
    #expect(!magra.aviso.contains("chave"))
}

@Test func todoEstadoTemTituloEExplicacaoEmPortugues() {
    for estado in EstadoDoServico.allCases {
        #expect(!estado.titulo.isEmpty)
        #expect(estado.explicacao.count > 40, "estado sem explicação de verdade: \(estado)")
    }
}

@Test func aInstalacaoPorForaEProcuradaOndeOInstaladorAEscreve() {
    #expect(InstalacaoPelaLinhaDeComando.plistDoSistema
        == "/Library/LaunchDaemons/com.river.unifi-bridge.plist")
    #expect(!InstalacaoPelaLinhaDeComando.existe(caminho: "/nao/existe/x.plist"))
}
