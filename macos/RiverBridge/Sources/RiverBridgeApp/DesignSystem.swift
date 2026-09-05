// A forma canônica dos elementos que toda tela repete: espaço, raio, tom, aviso
// e confirmação.
//
// Por que existe: medido em 2026-09-05, a árvore tinha 6 diálogos escritos à mão
// em 4 arquivos, nenhum componente de aviso (cada tela desenhava o seu com um
// `Text` laranja) e 68 usos de cor nomeada solta. Elemento comum reescrito em
// cada lugar diverge sozinho: um diálogo destrutivo ganha confirmação e outro
// não, um aviso é laranja aqui e amarelo ali, e ninguém percebe porque não há
// com o que comparar.
//
// O que é token e o que NÃO é: os valores abaixo são os que se repetem e
// significam alguma coisa (respiro entre grupos, raio de cartão, tom de estado).
// Geometria de UM lugar só — a largura de uma folha, a altura de um gráfico —
// continua onde está, porque transformá-la em token esconderia a decisão em vez
// de nomeá-la.
//
// A cerca que mantém isto de pé é a cena S53 do portão: diálogo e aviso escritos
// fora daqui reprovam.

import RiverBridgeCore
import SwiftUI

// MARK: - Tokens

/// Respiro. Os cinco degraus que a tela usa, com nome em vez de número.
enum Espaco {
    /// Entre um ícone e o texto dele.
    static let micro: CGFloat = 4
    /// Entre linhas irmãs.
    static let pequeno: CGFloat = 8
    /// O padrão de uma linha de ajuste.
    static let medio: CGFloat = 10
    /// Dentro de um cartão.
    static let cartao: CGFloat = 14
    /// Entre grupos de uma tela.
    static let secao: CGFloat = 18
}

/// Raio de canto. Três degraus: selo, cartão, painel.
enum Raio {
    static let selo: CGFloat = 8
    static let cartao: CGFloat = 12
    static let painel: CGFloat = 18
}

/// O tom de uma mensagem — o que ela SIGNIFICA, não a cor que ela tem.
///
/// Reaproveita `DeviceEventTone`, que já era o vocabulário de tom dos eventos:
/// duas escalas de cor no mesmo programa dariam um verde para o evento e outro
/// para o aviso do mesmo assunto.
enum TomDaMensagem {
    case bom, atencao, perigo, neutro

    var cor: Color {
        switch self {
        case .bom: return DeviceEventTone.family.color
        case .atencao: return DeviceEventTone.warning.color
        case .perigo: return DeviceEventTone.danger.color
        case .neutro: return .secondary
        }
    }

    var simbolo: String {
        switch self {
        case .bom: return "checkmark.circle.fill"
        case .atencao: return "exclamationmark.triangle.fill"
        case .perigo: return "exclamationmark.octagon.fill"
        case .neutro: return "info.circle.fill"
        }
    }
}

// MARK: - Aviso

/// A forma canônica de dizer alguma coisa ao dono no meio da tela.
///
/// Um aviso tem tom, uma frase curta e — quando há o que fazer — um botão. Não
/// tem variação: quem precisar de outra coisa acrescenta um caso AQUI, e todas
/// as telas ganham junto.
struct Aviso: View {
    var tom: TomDaMensagem
    var texto: String
    var detalhe: String?
    var simbolo: String?
    var rotuloDaAcao: String?
    var acao: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Espaco.medio) {
            Image(systemName: simbolo ?? tom.simbolo)
                .foregroundStyle(tom.cor)
                .font(.system(size: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Espaco.micro) {
                Text(texto)
                    .font(.system(.callout, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                if let detalhe {
                    Text(detalhe)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Espaco.pequeno)
            if let rotuloDaAcao, let acao {
                Button(rotuloDaAcao, action: acao)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(Espaco.cartao)
        .background(tom.cor.opacity(0.10), in: RoundedRectangle(cornerRadius: Raio.cartao))
        .overlay(
            RoundedRectangle(cornerRadius: Raio.cartao)
                .strokeBorder(tom.cor.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Confirmação

/// Um pedido de confirmação, com tudo o que ele precisa ter.
///
/// O `titulo` é a PERGUNTA, e o `detalhe` diz o que acontece — nomeando o que
/// muda, não "esta ação não pode ser desfeita" em abstrato. `destrutivo` marca o
/// botão em vermelho e nada mais: a decisão de ser destrutivo é de quem constrói
/// o pedido, e fica escrita nele.
struct PedidoDeConfirmacao: Identifiable {
    let id = UUID()
    var titulo: String
    var detalhe: String
    var rotuloDaAcao: String
    var destrutivo: Bool = false
    var acao: () -> Void
}

extension View {
    /// A forma canônica de pedir confirmação. Um `nil` fecha o diálogo.
    ///
    /// Existe para não haver duas: antes disto, cada tela chamava
    /// `.confirmationDialog` com os seus próprios rótulos, e o botão de cancelar
    /// aparecia num lugar e faltava noutro.
    func confirmacao(_ pedido: Binding<PedidoDeConfirmacao?>) -> some View {
        confirmationDialog(
            pedido.wrappedValue?.titulo ?? "",
            isPresented: Binding(get: { pedido.wrappedValue != nil },
                                 set: { if !$0 { pedido.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pedido.wrappedValue
        ) { atual in
            Button(atual.rotuloDaAcao, role: atual.destrutivo ? .destructive : nil) {
                atual.acao()
                pedido.wrappedValue = nil
            }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {
                pedido.wrappedValue = nil
            }
        } message: { atual in
            Text(atual.detalhe)
        }
    }
}

/// Uma escolha entre várias saídas — não é uma confirmação com outro nome.
///
/// "Apagar eventos" pergunta QUANTO apagar, e cada resposta é um ato diferente.
/// Forçá-la no molde de confirmar-ou-cancelar daria quatro diálogos encadeados.
struct EscolhaDeConfirmacao: Identifiable {
    struct Saida: Identifiable {
        let id = UUID()
        var rotulo: String
        var destrutivo: Bool = false
        var acao: () -> Void
    }

    let id = UUID()
    var titulo: String
    var detalhe: String
    var saidas: [Saida]
}

extension View {
    /// A forma canônica de oferecer várias saídas. Um `nil` fecha o diálogo.
    func escolha(_ pedido: Binding<EscolhaDeConfirmacao?>) -> some View {
        confirmationDialog(
            pedido.wrappedValue?.titulo ?? "",
            isPresented: Binding(get: { pedido.wrappedValue != nil },
                                 set: { if !$0 { pedido.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pedido.wrappedValue
        ) { atual in
            ForEach(atual.saidas) { saida in
                Button(saida.rotulo, role: saida.destrutivo ? .destructive : nil) {
                    saida.acao()
                    pedido.wrappedValue = nil
                }
            }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {
                pedido.wrappedValue = nil
            }
        } message: { atual in
            Text(atual.detalhe)
        }
    }
}
