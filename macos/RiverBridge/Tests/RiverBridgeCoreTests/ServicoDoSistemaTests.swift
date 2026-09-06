// A tela do serviço: o que ela diz, nas duas línguas, e qual ato cada estado pede.
//
// Estes testes existem por duas razões. A primeira: `register()` NÃO termina o
// trabalho. A Apple é literal — "the system won't bootstrap the LaunchDaemon
// until an admin approves the LaunchDaemon in System Preferences". Uma tela que
// dissesse "instalado" nesse ponto estaria mentindo, e o dono descobriria isso
// na próxima queda de energia.
//
// A segunda: a autorização é pedida na ABERTURA do programa, não num botão
// escondido em Ajustes — "check the authorization status at launch. If helper
// executables don't have authorization, alert the user, and call
// openSystemSettingsLoginItems()". E toda frase sai inteira numa língua só: no
// Mac mini (em inglês) a tela misturava as duas no mesmo cartão (2026-09-05).
//
// Os textos são pedidos com a língua EXPLÍCITA (`emPortugues:`): a língua viva
// é estado global que outro teste alterna em paralelo (ver DeviceInstanceTests).

import Foundation
import Testing
@testable import RiverBridgeCore

@Test func aTelaNuncaDizInstaladoAntesDaAutorizacao() {
    let esperando = EstadoDoServico.esperandoAprovacao
    #expect(esperando.titulo(emPortugues: true).contains("Autorize"))
    #expect(esperando.explicacao(emPortugues: true).contains("Ajustes do Sistema"))
    #expect(esperando.explicacao(emPortugues: true).contains("senha de administrador"))
    #expect(esperando.acaoNaAbertura == .abrirAjustesDoSistema)
}

@Test func aAberturaRegistraSozinhaEDepoisLevaAosAjustesDoSistema() {
    // Sem registro: o ato é registrar (a abertura faz isso sozinha; o botão só
    // aparece se ela falhou). Registrado: o ato é o interruptor do macOS.
    #expect(EstadoDoServico.naoInstalado.acaoNaAbertura == .registrar)
    #expect(EstadoDoServico.esperandoAprovacao.acaoNaAbertura == .abrirAjustesDoSistema)
    // O sistema "não encontra" o serviço (Apple: .notFound é ERRO; revogar o
    // consentimento devolve .requiresApproval): o ato é registrar de novo.
    #expect(EstadoDoServico.naoEncontradoPeloSistema.acaoNaAbertura == .registrar)
    // No ar, ou instalado por fora: a abertura não pede nada.
    #expect(EstadoDoServico.noAr.acaoNaAbertura == nil)
    #expect(!EstadoDoServico.noAr.avisaNaAbertura)
    #expect(EstadoDoServico.instaladoPelaLinhaDeComando.acaoNaAbertura == nil)
    // Fora de Aplicativos (aberto do disco de instalação): avisa, sem botão e
    // sem registrar — a frase diz o ato.
    let fora = EstadoDoServico.foraDeAplicativos
    #expect(fora.avisaNaAbertura)
    #expect(fora.acaoNaAbertura == nil)
    #expect(!fora.precisaRegistrar)
    #expect(!fora.podeRemover)
    #expect(fora.titulo(emPortugues: true).contains("Aplicativos"))
    #expect(fora.titulo(emPortugues: false).contains("Applications"))
    #expect(AcaoDoServico.abrirAjustesDoSistema.rotulo(emPortugues: true) == "Abrir Ajustes do Sistema")
    #expect(AcaoDoServico.abrirAjustesDoSistema.rotulo(emPortugues: false) == "Open System Settings")
    // "Registrar de novo" não tem acento: o teste de acento não o pegaria em
    // inglês (revisão fria da 0.8.1) — por isso os dois rótulos, explícitos.
    #expect(AcaoDoServico.registrar.rotulo(emPortugues: true) == "Registrar de novo")
    #expect(AcaoDoServico.registrar.rotulo(emPortugues: false) == "Register again")
}

/// A regra que impede o registro fora de Aplicativos, refutada nos casos que
/// existem de verdade: o disco de instalação montado, Downloads, a cópia de
/// ensaio das capturas, o caminho de translocação do Gatekeeper, e a armadilha
/// do prefixo sem barra ("/ApplicationsX").
@Test func soUmaPastaAplicativosAceitaORegistro() {
    let pastas = [URL(fileURLWithPath: "/Applications"),
                  URL(fileURLWithPath: "/Users/dono/Applications")]
    func dentro(_ caminho: String) -> Bool {
        PastaDeAplicativos.contem(URL(fileURLWithPath: caminho), pastas: pastas)
    }
    #expect(dentro("/Applications/River Bridge.app"))
    #expect(dentro("/Users/dono/Applications/River Bridge.app"))
    #expect(dentro("/Applications/Utilitários/River Bridge.app"))
    #expect(!dentro("/Volumes/River Bridge/River Bridge.app"))
    #expect(!dentro("/Users/dono/Downloads/River Bridge.app"))
    #expect(!dentro("/private/tmp/River Bridge Ensaio.app"))
    #expect(!dentro("/private/var/folders/x/AppTranslocation/1234/d/River Bridge.app"))
    #expect(!dentro("/ApplicationsX/River Bridge.app"))
    #expect(!dentro("/Applications"))
}

@Test func registrarSoEPrecisoQuandoOSistemaNaoConheceOServico() {
    #expect(EstadoDoServico.naoInstalado.precisaRegistrar)
    #expect(EstadoDoServico.naoEncontradoPeloSistema.precisaRegistrar)
    // Já registrado: registrar de novo é o erro que a documentação chama de
    // "attempted to reregister after it was already registered".
    #expect(!EstadoDoServico.esperandoAprovacao.precisaRegistrar)
    #expect(!EstadoDoServico.noAr.precisaRegistrar)
}

@Test func comOServicoInstaladoPorForaATelaRecusaEExplica() {
    // Dois serviços vigiando o mesmo River disputam o cabo e a porta, e o que
    // perder fica mudo sem ninguém perceber.
    let cruzado = EstadoDoServico.instaladoPelaLinhaDeComando
    #expect(!cruzado.precisaRegistrar)
    #expect(!cruzado.podeRemover)
    #expect(cruzado.explicacao(emPortugues: true).contains("mesmo cabo"))
    #expect(cruzado.explicacao(emPortugues: true).contains("scripts"))
    #expect(cruzado.explicacao(emPortugues: false).contains("same cable"))
    #expect(cruzado.explicacao(emPortugues: false).contains("scripts"))
}

@Test func removerSoAparecePraQuemTemOQueRemover() {
    #expect(!EstadoDoServico.naoInstalado.podeRemover)
    #expect(EstadoDoServico.noAr.podeRemover)
    #expect(EstadoDoServico.esperandoAprovacao.podeRemover)
}

@Test func aConfirmacaoDaRemocaoEcurtaEDizOQueSai() {
    // HIG (Alerts): título que descreve a situação, mensagem curta em frases
    // completas, botão de uma palavra. Nada de "sem volta": registrar de novo
    // existe (o dono chamou o texto antigo de mentira, 2026-09-06).
    let completa = RemocaoCompleta(servicoResponde: true)
    #expect(completa.pergunta.hasSuffix("?"))
    let aviso = completa.aviso
    #expect(aviso.contains("chave") || aviso.contains("key"))
    #expect(aviso.contains("senhas") || aviso.contains("passwords"))
    #expect(aviso.contains("Início de Sessão") || aviso.contains("Login Items"))
    #expect(aviso.contains("Aplicativos") || aviso.contains("Applications"))
    #expect(!aviso.contains("sem volta") && !aviso.contains("for good"))
    #expect(aviso.count <= 220, "mensagem longa demais: \(aviso.count)")
    #expect(completa.rotuloDoBotao == "Remover" || completa.rotuloDoBotao == "Remove")
}

@Test func semOServicoRespondendoAConfirmacaoDizOQueFica() {
    // O programa não apaga arquivos do sistema; sem o serviço, a chave e as
    // senhas ficam — e a confirmação diz onde, em vez de um erro cru em inglês
    // depois ("Could not connect to the server", visto pelo dono em 2026-09-06).
    let semServico = RemocaoCompleta(servicoResponde: false)
    #expect(semServico.aviso.contains("ficam") || semServico.aviso.contains("stay"))
    #expect(semServico.aviso.contains("/Library/Application Support/river-unifi-bridge"))
}

@Test func oRelogioSoAndaComORegistroHabilitadoESemResposta() {
    // Antes da autorização o relógio NÃO anda: senão a tolerância já estaria
    // gasta quando o dono autorizasse e a tela diria "não responde" com o
    // serviço ainda subindo (bloqueador da revisão fria da 0.8.3).
    var relogio = EstadoDoServico.RelogioDoRegistro()
    let t0 = Date(timeIntervalSince1970: 1_000)
    #expect(relogio.haQuantoTempo(registro: .esperandoAprovacao, respondendo: false, agora: t0) == 0)
    #expect(relogio.haQuantoTempo(registro: .esperandoAprovacao, respondendo: false, agora: t0 + 60) == 0)
    // Autorizou: começa a contar AGORA, não desde a abertura.
    #expect(relogio.haQuantoTempo(registro: .noAr, respondendo: false, agora: t0 + 60) == 0)
    #expect(relogio.haQuantoTempo(registro: .noAr, respondendo: false, agora: t0 + 70) == 10)
    // Respondeu: zera.
    #expect(relogio.haQuantoTempo(registro: .noAr, respondendo: true, agora: t0 + 80) == 0)
    #expect(relogio.haQuantoTempo(registro: .noAr, respondendo: false, agora: t0 + 81) == 0)
    // O registro deixou de estar habilitado: zera também.
    relogio = EstadoDoServico.RelogioDoRegistro()
    _ = relogio.haQuantoTempo(registro: .noAr, respondendo: false, agora: t0)
    #expect(relogio.haQuantoTempo(registro: .naoInstalado, respondendo: false, agora: t0 + 100) == 0)
    #expect(relogio.haQuantoTempo(registro: .noAr, respondendo: false, agora: t0 + 100) == 0)
}

@Test func registradoMasParadoCombinaAsDuasFontes() {
    // `.enabled` é "eligible to run", não "rodando": com o registro habilitado e
    // o serviço mudo por mais tempo do que leva para subir, a tela diz "não
    // responde" e oferece refazer o registro — nunca "no ar" ao lado de "sem
    // resposta" (dono, Mac mini, 2026-09-06).
    #expect(EstadoDoServico.combinado(registro: .noAr, respondendo: true, haQuantoTempoHabilitado: 999) == .noAr)
    #expect(EstadoDoServico.combinado(registro: .noAr, respondendo: false, haQuantoTempoHabilitado: 2) == .noAr)
    #expect(EstadoDoServico.combinado(registro: .noAr, respondendo: false,
                                      haQuantoTempoHabilitado: EstadoDoServico.tolerancia) == .registradoMasParado)
    // As outras fontes do sistema não mudam com a resposta.
    #expect(EstadoDoServico.combinado(registro: .esperandoAprovacao, respondendo: false, haQuantoTempoHabilitado: 999) == .esperandoAprovacao)
    #expect(EstadoDoServico.combinado(registro: .foraDeAplicativos, respondendo: true, haQuantoTempoHabilitado: 0) == .foraDeAplicativos)
    let parado = EstadoDoServico.registradoMasParado
    #expect(parado.avisaNaAbertura && parado.acaoNaAbertura == .refazerRegistro && parado.podeRemover)
    #expect(AcaoDoServico.refazerRegistro.rotulo(emPortugues: false) == "Redo the registration")
}

@Test func todoEstadoTemTituloEExplicacaoNasDuasLinguas() {
    for estado in EstadoDoServico.allCases {
        for pt in [true, false] {
            #expect(!estado.titulo(emPortugues: pt).isEmpty)
            #expect(estado.explicacao(emPortugues: pt).count > 40,
                    "estado sem explicação de verdade: \(estado) pt=\(pt)")
        }
    }
}

/// A cerca da língua misturada: em inglês, NENHUMA frase do serviço carrega
/// letra acentuada do português — o sintoma exato que o dono viu no Mac mini.
@Test func emInglesNenhumaFraseDoServicoSaiEmPortugues() {
    let acentos = CharacterSet(charactersIn: "ãõçáéíóúâêô")
    for estado in EstadoDoServico.allCases {
        let en = estado.titulo(emPortugues: false) + estado.explicacao(emPortugues: false)
        #expect(en.rangeOfCharacter(from: acentos) == nil, "português vazou em inglês: \(estado)")
    }
    for acao in [AcaoDoServico.registrar, .abrirAjustesDoSistema] {
        #expect(acao.rotulo(emPortugues: false).rangeOfCharacter(from: acentos) == nil)
    }
}

@Test func aInstalacaoPorForaEProcuradaOndeOInstaladorAEscreve() {
    #expect(InstalacaoPelaLinhaDeComando.plistDoSistema
        == "/Library/LaunchDaemons/com.river.unifi-bridge.plist")
    #expect(!InstalacaoPelaLinhaDeComando.existe(caminho: "/nao/existe/x.plist"))
}
