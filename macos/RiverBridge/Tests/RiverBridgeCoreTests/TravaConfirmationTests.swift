// As três travas como interruptores (0.8.0): o texto de cada uma é contrato.

import Foundation
import Testing
@testable import RiverBridgeCore

@Test func asTresTravasSaoAsTresChavesDoServico() {
    // As chaves são as do serviço, letra por letra: é o que o PUT recebe e o
    // que o GET devolve (em minúsculas).
    #expect(Set(TravaConfirmation.Trava.allCases.map(\.chave))
            == ["UDR7_ARM_ALLOWED", "RIVER_POWEROFF_ALLOWED", "DEVICE_CMD_ALLOWED"])
    #expect(TravaConfirmation.Trava.armarProtecao.atributo == "udr7_arm_allowed")
}

@Test func cadaTravaDizOQueLiberaSemJargao() {
    for trava in TravaConfirmation.Trava.allCases {
        let texto = TravaConfirmation(trava: trava)
        #expect(texto.rotulo.hasPrefix("Permitir") || texto.rotulo.hasPrefix("Allow"))
        #expect(texto.explicacao.count > 30, "explicação curta demais: \(trava)")
        #expect(texto.title.hasSuffix("?"))
        #expect(texto.message.count > 60, "confirmação sem o risco nomeado: \(trava)")
        #expect(texto.confirmLabel.contains("Abrir a trava") || texto.confirmLabel.contains("Open the lock"))
        // Nenhuma frase carrega sigla, chave nem código.
        for frase in [texto.rotulo, texto.explicacao, texto.title, texto.message, texto.confirmLabel] {
            #expect(frase.contains("_") == false, "chave crua na tela: \(frase)")
            #expect(frase.contains("409") == false)
            #expect(frase.contains(".env") == false)
        }
    }
}

@Test func aTravaDeArmamentoDizQueODesligamentoViraReal() {
    let texto = TravaConfirmation(trava: .armarProtecao)
    // Lida UMA vez: a língua viva é estado global que outro teste alterna em
    // paralelo, e ler `message` duas vezes na mesma expressão deu uma leitura
    // em cada língua — falhou assim na suíte inteira em 2026-09-05.
    let mensagem = texto.message
    #expect(mensagem.contains("de verdade") || mensagem.contains("really"))
    #expect(texto.confirmLabel.contains("real"))
}

@Test func abrirParaARedeNomeiaORiscoAntesDeAbrir() {
    // Abrir o servidor à rede expõe as ordens das travas abertas a quem tiver a
    // senha, e a senha viaja sem cifra: a confirmação tem de dizer as duas coisas.
    let texto = RedeConfirmation()
    #expect(texto.title.hasSuffix("?"))
    #expect(texto.message.contains("senha") || texto.message.contains("password"))
    #expect(texto.message.contains("sem cifra") || texto.message.contains("unencrypted"))
    #expect(texto.message.contains("desligar o River") || texto.message.contains("turning the River off"))
    for frase in [texto.title, texto.message, texto.confirmLabel] {
        #expect(frase.contains("_") == false)
        #expect(frase.contains("LISTEN") == false)
    }
}
