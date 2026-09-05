// O grupo "Serviço" dos Ajustes: instalar, aprovar e remover por completo.
//
// Arrastar o programa para Aplicativos põe o programa lá, e mais nada. O serviço
// que vigia a energia vai junto dentro do pacote, mas alguém precisa registrá-lo
// — e é aqui.
//
// A regra que este arquivo respeita, e que veio da documentação da Apple (as
// citações estão em RiverBridgeCore/ServicoDoSistema.swift): `register()` NÃO
// termina o trabalho. Ele começa, e o estado fica esperando aprovação até o dono
// ir aos Ajustes do Sistema. A tela diz isso com todas as letras — dizer
// "instalado" ali seria mentir, e o dono descobriria na próxima queda de energia.

import RiverBridgeCore
import ServiceManagement
import SwiftUI

struct ServicoGroup: View {
    /// O nome do arquivo do serviço dentro do pacote. Tem de bater com o que o
    /// empacotador escreve em `Contents/Library/LaunchDaemons/`.
    static let plistDoServico = "com.river.unifi-bridge.plist"

    @State private var estado: EstadoDoServico = .naoInstalado
    @State private var recado: String?
    @State private var perguntandoSeRemove = false
    @State private var trabalhando = false
    var aoMudar: () -> Void = {}

    var body: some View {
        SettingsRows.group(L10n.t("Serviço", "Service")) {
            HStack(alignment: .top, spacing: Espaco.medio) {
                Image(systemName: icone)
                    .frame(width: 26)
                    .foregroundStyle(cor)
                VStack(alignment: .leading, spacing: Espaco.micro) {
                    Text(estado.titulo)
                        .font(.system(.body, design: .rounded))
                    Text(estado.explicacao)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            if let recado {
                Aviso(tom: .atencao, texto: recado)
            }
            if estado.podeRemover {
                Aviso(tom: .neutro, texto: RemocaoCompleta.avisoDoLixo, simbolo: "trash.slash")
            }
            SettingsRows.divider
            HStack(spacing: Espaco.medio) {
                if estado.podeInstalar {
                    Button(L10n.t("Instalar o serviço", "Install the service"), action: instalar)
                        .buttonStyle(.borderedProminent)
                        .disabled(trabalhando)
                }
                if estado.mostraAjustesDoSistema {
                    Button(L10n.t("Abrir Ajustes do Sistema", "Open System Settings")) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
                Spacer()
                if estado.podeRemover {
                    Button(L10n.t("Remover completamente", "Remove completely"), role: .destructive) {
                        perguntandoSeRemove = true
                    }
                    .disabled(trabalhando)
                }
            }
        }
        .task {
            // Perguntar UMA vez era o defeito que o dono viu no Mac mini em
            // 2026-09-05: ele ligou a chave nos Ajustes do Sistema, voltou, e a
            // tela continuava dizendo "falta aprovar". O macOS não avisa quando
            // isso muda — quem tem de perguntar de novo somos nós.
            while !Task.isCancelled {
                conferir()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .confirmacao(Binding(
            get: {
                guard perguntandoSeRemove else { return nil }
                return PedidoDeConfirmacao(
                    titulo: remocao.pergunta, detalhe: remocao.aviso,
                    rotuloDaAcao: L10n.t("Remover completamente", "Remove completely"),
                    destrutivo: true, acao: remover)
            },
            set: { if $0 == nil { perguntandoSeRemove = false } }))
    }

    private var remocao: RemocaoCompleta {
        RemocaoCompleta(estadoExiste: ApiEndpoint.readToken() != nil,
                        configuracaoDoNutExiste: true)
    }

    private var icone: String {
        switch estado {
        case .noAr: return "checkmark.seal.fill"
        case .esperandoAprovacao: return "exclamationmark.triangle.fill"
        case .instaladoPelaLinhaDeComando: return "questionmark.circle.fill"
        default: return "power"
        }
    }

    private var cor: Color {
        switch estado {
        case .noAr: return Cor.bom
        case .esperandoAprovacao, .instaladoPelaLinhaDeComando: return Cor.atencao
        default: return Cor.neutro
        }
    }

    // MARK: - o que a tela faz

    private func conferir() {
        estado = Self.estadoAgora()
    }

    /// Em que pé o serviço está, AGORA, perguntando ao sistema.
    ///
    /// É função de módulo porque o painel principal também precisa dela: até
    /// aqui ele decidia pela presença do arquivo de ficha, e uma ficha órfã de
    /// uma instalação removida o fazia dizer "sem comunicação com o serviço"
    /// quando a verdade era "o serviço não está instalado" (visto pelo dono no
    /// Mac mini, 2026-09-05). Duas fontes para a mesma pergunta, e a errada
    /// falava primeiro.
    static func estadoAgora() -> EstadoDoServico {
        // A recusa cruzada vem PRIMEIRO: com o serviço instalado pela linha de
        // comando, registrar outro daria dois vigias disputando o mesmo cabo e a
        // mesma porta, e o que perdesse ficaria mudo sem ninguém perceber.
        if InstalacaoPelaLinhaDeComando.existe() { return .instaladoPelaLinhaDeComando }
        switch SMAppService.daemon(plistName: plistDoServico).status {
        case .enabled: return .noAr
        case .requiresApproval: return .esperandoAprovacao
        case .notRegistered: return .naoInstalado
        case .notFound: return .desligadoPeloSistema
        @unknown default: return .naoInstalado
        }
    }

    private func instalar() {
        trabalhando = true
        recado = nil
        var queixa: String?
        do {
            try SMAppService.daemon(plistName: Self.plistDoServico).register()
        } catch {
            queixa = L10n.t("O macOS respondeu: ", "macOS said: ") + error.localizedDescription
        }
        trabalhando = false
        conferir()
        // Erro que NÃO impediu o registro não é queixa: o dono via, na mesma
        // tela, "falta aprovar" e "a operação não pôde ser concluída", e as duas
        // não podiam ser verdade ao mesmo tempo (Mac mini, 2026-09-05). Se o
        // sistema já conhece o serviço, o registro valeu — o que falta é o ato
        // dele nos Ajustes, que a linha de cima já explica.
        recado = (estado == .esperandoAprovacao || estado == .noAr) ? nil : queixa
        aoMudar()
    }

    private func remover() {
        trabalhando = true
        recado = nil
        Task {
            // A ordem importa. O ESTADO sai primeiro, pelo próprio serviço: ele é
            // dono dos arquivos (roda como serviço de sistema) e o programa, que
            // roda como o dono, não conseguiria apagá-los. Desregistrar antes
            // mataria o serviço e deixaria a chave do console e as senhas no disco.
            if let endpoint = ApiEndpoint.discover() {
                let cliente = APIClient(endpoint: endpoint)
                do {
                    try await cliente.apagarEstadoDoServico()
                } catch {
                    recado = L10n.t("Não consegui apagar o estado: ",
                                    "Could not erase the state: ") + error.localizedDescription
                }
            }
            do {
                try await SMAppService.daemon(plistName: Self.plistDoServico).unregister()
            } catch {
                recado = (recado.map { $0 + "\n" } ?? "")
                    + L10n.t("Não consegui desregistrar o serviço: ",
                             "Could not unregister the service: ") + error.localizedDescription
            }
            trabalhando = false
            conferir()
            aoMudar()
        }
    }
}
