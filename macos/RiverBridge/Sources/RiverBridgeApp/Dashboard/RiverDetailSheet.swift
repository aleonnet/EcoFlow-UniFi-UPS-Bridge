// A folha de detalhe do River (0.9.0): abre ao clicar no anel e mostra, em
// quatro grupos, tudo o que o aparelho publica — o conteúdo vem pronto do Core
// (`FolhaDoRiver`), esta tela só desenha a lista.
//
// É uma folha de LEITURA: não tem Salvar nem Remover, só Fechar. Por isso não
// usa a moldura das folhas de dispositivo (que é de edição); usa as mesmas
// métricas (`DeviceSheetMetrics`) para caber na janela mínima de 414×480 e a
// mesma regra da variante estreita medida na largura REAL desenhada.

import RiverBridgeCore
import SwiftUI

struct RiverDetailSheet: View {
    var store: TelemetryStore
    let hostSize: CGSize
    let onClose: () -> Void

    @State private var larguraMedida: CGFloat?

    private var size: CGSize { DeviceSheetMetrics.size(host: hostSize) }
    private var estreito: Bool { DeviceSheetMetrics.isNarrow(width: larguraMedida ?? size.width) }
    private var accent: Color { Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery) }
    private var folha: FolhaDoRiver { store.folhaDoRiver }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.nenhum) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Espaco.secao) {
                    ForEach(folha.grupos, id: \.titulo) { grupo in
                        grupoView(grupo)
                    }
                }
                .padding(Espaco.janela)
            }
            .defaultScrollAnchor(.top)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { larguraMedida = $0 }
            Divider()
            footer
        }
        .frame(width: size.width, height: size.height)
        .accessibilityIdentifier("folha-do-river")
    }

    private var header: some View {
        HStack(spacing: Espaco.confortavel) {
            Image(systemName: "minus.plus.batteryblock.fill")
                .font(.title2)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: Espaco.fio) {
                Text(folha.titulo)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text(L10n.t("Série ", "Serial ") + folha.serie)
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, Espaco.janela)
        .padding(.vertical, Espaco.cartao)
    }

    private func grupoView(_ grupo: FolhaDoRiver.Grupo) -> some View {
        VStack(alignment: .leading, spacing: Espaco.pequeno) {
            Text(grupo.titulo).eyebrow()
            VStack(alignment: .leading, spacing: Espaco.nenhum) {
                ForEach(Array(grupo.linhas.enumerated()), id: \.offset) { indice, linha in
                    linhaView(linha)
                    if indice < grupo.linhas.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, Espaco.cartao)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Raio.cartao, style: .continuous))
        }
    }

    /// Rótulo à esquerda, valor à direita; estreito, o valor desce para a
    /// linha de baixo, à esquerda — nada quebra no meio de uma palavra.
    @ViewBuilder
    private func linhaView(_ linha: FolhaDoRiver.Linha) -> some View {
        VStack(alignment: .leading, spacing: Espaco.fio) {
            if estreito {
                Text(linha.rotulo).font(.callout).foregroundStyle(.secondary)
                valor(linha)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Espaco.medio) {
                    Text(linha.rotulo).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: Espaco.pequeno)
                    valor(linha)
                }
            }
            if let nota = linha.nota {
                Text(nota).font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Espaco.pequeno)
    }

    private func valor(_ linha: FolhaDoRiver.Linha) -> some View {
        Text(linha.valor)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .monospacedDigit()
            .contentTransition(.numericText())
            .fixedSize()
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L10n.t("Fechar", "Close")) { onClose() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Espaco.janela)
        .padding(.vertical, Espaco.cartao)
    }
}
