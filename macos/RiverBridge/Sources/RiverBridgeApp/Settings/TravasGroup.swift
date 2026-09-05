// O grupo "Travas" dos Ajustes: os três interruptores que liberam os atos que
// mexem na energia de um equipamento.
//
// Ligar pede confirmação (é o molde do armamento da proteção); desligar é
// direto. O serviço grava e aplica a quente, sem reinício — e, com a proteção
// armada, recusa fechar a trava de armamento: quem desarma primeiro é o dono,
// na folha do dispositivo. As frases vivem em RiverBridgeCore/TravaConfirmation.swift,
// onde há teste para cada uma.

import RiverBridgeCore
import SwiftUI

struct TravasGroup: View {
    @State private var abertas: [TravaConfirmation.Trava: Bool] = [:]
    @State private var carregou = false
    @State private var pendente: TravaConfirmation.Trava?
    @State private var emVoo: TravaConfirmation.Trava?
    @State private var recado: String?

    var body: some View {
        SettingsRows.group(L10n.t("Travas", "Locks")) {
            Text(L10n.t("Cada trava libera um ato que mexe na energia de um equipamento. Fechada, o ato não existe: nem nesta tela, nem no Home Assistant.",
                        "Each lock releases an act that touches a device's power. Closed, the act does not exist: neither on this screen nor in Home Assistant."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(TravaConfirmation.Trava.allCases, id: \.self) { trava in
                SettingsRows.divider
                linha(trava)
            }
            if let recado {
                Aviso(tom: .atencao, texto: recado)
            }
            SettingsRows.divider
            Text(L10n.t("O Home Assistant lê as ordens ao carregar a integração: depois de mudar uma trava, recarregue-a lá.",
                        "Home Assistant reads the orders when it loads the integration: after changing a lock, reload it there."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await carregar() }
        .confirmacao(Binding(
            get: {
                pendente.map { trava in
                    let texto = TravaConfirmation(trava: trava)
                    return PedidoDeConfirmacao(
                        titulo: texto.title, detalhe: texto.message,
                        rotuloDaAcao: texto.confirmLabel, destrutivo: true
                    ) { Task { await gravar(trava, aberta: true) } }
                }
            },
            set: { if $0 == nil { pendente = nil } }))
    }

    private func simbolo(_ trava: TravaConfirmation.Trava) -> String {
        switch trava {
        case .armarProtecao: "shield.lefthalf.filled"
        case .desligarRiver: "power"
        case .mandarNosDispositivos: "bolt.horizontal.circle"
        }
    }

    @ViewBuilder
    private func linha(_ trava: TravaConfirmation.Trava) -> some View {
        let texto = TravaConfirmation(trava: trava)
        let aberta = abertas[trava] ?? false
        HStack(alignment: .top, spacing: Espaco.medio) {
            Image(systemName: simbolo(trava))
                .frame(width: 26)
                .foregroundStyle(aberta ? Cor.atencao : Cor.neutro)
            VStack(alignment: .leading, spacing: Espaco.fio) {
                Text(texto.rotulo)
                    .font(.system(.body, design: .rounded))
                Text(texto.explicacao)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Espaco.pequeno)
            Toggle("", isOn: Binding(
                get: { aberta },
                set: { novo in
                    if novo { pendente = trava } else { Task { await gravar(trava, aberta: false) } }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                // Sem os valores do serviço, mexer seria escrever no escuro; e uma
                // gravação em voo não aceita a próxima.
                .disabled(!carregou || emVoo != nil)
        }
    }

    // MARK: - o que a tela faz

    private func carregar() async {
        guard let endpoint = ApiEndpoint.discover(),
              let resposta = try? await APIClient(endpoint: endpoint).config() else {
            carregou = false
            return
        }
        for trava in TravaConfirmation.Trava.allCases {
            abertas[trava] = resposta.config[trava.atributo]?.boolValue ?? false
        }
        carregou = true
    }

    private func gravar(_ trava: TravaConfirmation.Trava, aberta: Bool) async {
        guard let endpoint = ApiEndpoint.discover() else {
            recado = L10n.t("Serviço parado — nada mudou.", "Service down — nothing changed.")
            return
        }
        emVoo = trava
        do {
            _ = try await APIClient(endpoint: endpoint).putConfig([trava.chave: aberta ? "1" : "0"])
            abertas[trava] = aberta
            recado = nil
        } catch let APIError.badStatus(_, body) {
            recado = ProtectionRefusal.text(body)
        } catch {
            recado = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
        emVoo = nil
    }
}
