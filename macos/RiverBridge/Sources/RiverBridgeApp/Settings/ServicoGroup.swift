// O grupo "Serviço" dos Ajustes: em que pé o serviço está, e remover por completo.
//
// Arrastar o programa para Aplicativos põe o programa lá, e mais nada. O serviço
// que vigia a energia vai junto dentro do pacote, mas alguém precisa registrá-lo
// — e isso acontece SOZINHO na abertura do programa (`registrarNaAbertura()`,
// chamado pelo aviso do topo do painel), como a Apple manda: "check the
// authorization status at launch. If helper executables don't have
// authorization, alert the user, and call openSystemSettingsLoginItems()". As
// citações estão em RiverBridgeCore/ServicoDoSistema.swift.
//
// Até a 0.8.0 o registro era um botão aqui dentro, "Instalar o serviço". O dono
// abriu o programa no Mac mini, não achou nada na abertura, e chamou o que era
// (2026-09-05): a autorização que o macOS cobra tem de ser pedida na abertura,
// não escondida em Ajustes. Este grupo fica com o que é de Ajustes: o estado,
// a remoção completa, e o "Registrar de novo" para o caso raro de o registro da
// abertura ter falhado.
//
// `register()` NÃO termina o trabalho. Ele começa, e o estado fica esperando a
// autorização até o dono agir. A tela diz isso com todas as letras — dizer
// "instalado" ali seria mentir, e o dono descobriria na próxima queda de energia.

import RiverBridgeCore
import ServiceManagement
import SwiftUI

struct ServicoGroup: View {
    /// O nome do arquivo do serviço dentro do pacote. Tem de bater com o que o
    /// empacotador escreve em `Contents/Library/LaunchDaemons/`.
    static let plistDoServico = "com.river.unifi-bridge.plist"

    /// A fonte viva: o serviço responde? (`.enabled` no sistema é "eligible to
    /// run", não "rodando" — o dono viu "no ar" ao lado de "sem resposta".)
    var store: TelemetryStore
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
                // "trash", e não "trash.slash": o Lixo agora REMOVE (0.8.0) — a
                // lixeira riscada contradizia a frase (visto na captura de 2026-09-05).
                Aviso(tom: .neutro, texto: RemocaoCompleta.avisoDoLixo, simbolo: "trash")
            }
            // A linha de botões só existe quando há botão: no estado "mova para
            // Aplicativos" sobrava uma divisória com nada embaixo (captura de
            // 2026-09-05).
            if estado.precisaRegistrar || estado.acaoNaAbertura != nil || estado.podeRemover {
                SettingsRows.divider
                HStack(spacing: Espaco.medio) {
                    if estado.precisaRegistrar {
                        Button(AcaoDoServico.registrar.rotulo, action: registrarDeNovo)
                            .buttonStyle(.borderedProminent)
                            .disabled(trabalhando)
                    }
                    if estado.acaoNaAbertura == .abrirAjustesDoSistema {
                        Button(AcaoDoServico.abrirAjustesDoSistema.rotulo) {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                    if estado.acaoNaAbertura == .religar {
                        Button(AcaoDoServico.religar.rotulo, action: registrarDeNovo)
                            .buttonStyle(.borderedProminent)
                            .disabled(trabalhando)
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
                    rotuloDaAcao: remocao.rotuloDoBotao,
                    destrutivo: true, acao: remover)
            },
            set: { if $0 == nil { perguntandoSeRemove = false } }))
    }

    private var remocao: RemocaoCompleta {
        RemocaoCompleta(servicoResponde: store.phase == .live)
    }

    private var icone: String {
        switch estado {
        case .noAr: return "checkmark.seal.fill"
        case .esperandoAprovacao, .registradoMasParado: return "exclamationmark.triangle.fill"
        case .instaladoPelaLinhaDeComando: return "questionmark.circle.fill"
        default: return "power"
        }
    }

    private var cor: Color {
        switch estado {
        case .noAr: return Cor.bom
        case .esperandoAprovacao, .registradoMasParado, .instaladoPelaLinhaDeComando: return Cor.atencao
        default: return Cor.neutro
        }
    }

    // MARK: - o que a tela faz

    private func conferir() {
        estado = Self.estadoAgora(respondendo: store.phase == .live)
    }

    /// Em que pé o serviço está, AGORA, perguntando ao sistema.
    ///
    /// É função de módulo porque o painel principal também precisa dela: até
    /// aqui ele decidia pela presença do arquivo de ficha, e uma ficha órfã de
    /// uma instalação removida o fazia dizer "sem comunicação com o serviço"
    /// quando a verdade era "o serviço não está instalado" (visto pelo dono no
    /// Mac mini, 2026-09-05). Duas fontes para a mesma pergunta, e a errada
    /// falava primeiro.
    static func estadoAgora(respondendo: Bool) -> EstadoDoServico {
        let registro = registroAgora()
        return EstadoDoServico.combinado(
            registro: registro, respondendo: respondendo,
            haQuantoTempoHabilitado: relogio.haQuantoTempo(registro: registro, respondendo: respondendo))
    }

    /// O relógio de "habilitado sem resposta" (regra e teste no Core).
    @MainActor private static var relogio = EstadoDoServico.RelogioDoRegistro()

    /// O que o SISTEMA diz do registro — uma das fontes; a outra é o serviço
    /// responder, e `estadoAgora(respondendo:)` combina as duas.
    static func registroAgora() -> EstadoDoServico {
        // A recusa cruzada vem PRIMEIRO: com o serviço instalado pela linha de
        // comando, registrar outro daria dois vigias disputando o mesmo cabo e a
        // mesma porta, e o que perdesse ficaria mudo sem ninguém perceber.
        if InstalacaoPelaLinhaDeComando.existe() { return .instaladoPelaLinhaDeComando }
        // Depois, ONDE o programa está: aberto do disco de instalação ou de
        // Downloads, nada é registrado — o serviço apontaria para um caminho que
        // some. (E é o que impede a cópia de ensaio das capturas, em /private/tmp,
        // de registrar um serviço na máquina de quem desenvolve.)
        if !emAplicativos() { return .foraDeAplicativos }
        switch SMAppService.daemon(plistName: plistDoServico).status {
        case .enabled: return .noAr
        case .requiresApproval: return .esperandoAprovacao
        case .notRegistered: return .naoInstalado
        case .notFound: return .naoEncontradoPeloSistema
        @unknown default: return .naoInstalado
        }
    }

    /// O pacote está numa pasta Aplicativos (da máquina ou do usuário)? A regra
    /// é `PastaDeAplicativos.contem`, no Core, onde o teste a refuta.
    static func emAplicativos() -> Bool {
        PastaDeAplicativos.contem(
            Bundle.main.bundleURL,
            pastas: FileManager.default.urls(for: .applicationDirectory,
                                             in: [.localDomainMask, .userDomainMask]))
    }

    /// Registra o serviço no sistema. Devolve a queixa do macOS — só quando ela
    /// impediu o registro.
    ///
    /// Erro que NÃO impediu o registro não é queixa: o dono via, na mesma tela,
    /// "falta aprovar" e "a operação não pôde ser concluída", e as duas não
    /// podiam ser verdade ao mesmo tempo (Mac mini, 2026-09-05). Se o sistema já
    /// conhece o serviço, o registro valeu — o que falta é a autorização dele,
    /// que a frase do estado já explica.
    static func registrar() -> String? {
        var queixa: String?
        do {
            try SMAppService.daemon(plistName: plistDoServico).register()
        } catch {
            queixa = L10n.t("O macOS respondeu: ", "macOS said: ") + error.localizedDescription
        }
        let depois = registroAgora()
        return (depois == .esperandoAprovacao || depois == .noAr) ? nil : queixa
    }

    /// Registrado mas parado: o mesmo `register()`. Medido no Mac mini em
    /// 2026-09-06: num registro já autorizado, `register()` devolve ok e o
    /// launchd sobe o serviço em segundos, sem nova autorização. O relógio
    /// zera para dar ao serviço o tempo de subir.
    static func religar() -> String? {
        relogio = EstadoDoServico.RelogioDoRegistro()
        return registrar()
    }

    /// O registro da ABERTURA: uma tentativa por lançamento do programa, feita
    /// pelo aviso do topo quando o sistema ainda não conhece o serviço. Devolve
    /// se tentou (para o aviso guardar a queixa só quando houve tentativa).
    @MainActor private static var registroTentadoNestaAbertura = false

    @MainActor static func registrarNaAbertura() -> (tentou: Bool, queixa: String?) {
        guard !registroTentadoNestaAbertura else { return (false, nil) }
        registroTentadoNestaAbertura = true
        // O mesmo ato do botão, inclusive o relógio zerado: no caso do registro
        // herdado, a tentativa acontece aos 15 s de silêncio, e sem zerar a
        // faixa "não responde" ficaria na tela durante a subida do serviço
        // (revisão fria da 0.8.4).
        return (true, religar())
    }

    private func registrarDeNovo() {
        trabalhando = true
        recado = estado == .registradoMasParado ? Self.religar() : Self.registrar()
        trabalhando = false
        conferir()
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
            // Sem o serviço respondendo, a confirmação já disse que a chave e as
            // senhas ficam: não há pedido a fazer, nem erro cru em inglês a mostrar
            // ("Could not connect to the server", visto pelo dono em 2026-09-06).
            if store.phase == .live, let endpoint = ApiEndpoint.discover() {
                let cliente = APIClient(endpoint: endpoint)
                do {
                    try await cliente.apagarEstadoDoServico()
                } catch {
                    recado = L10n.t("O serviço não apagou a chave e as senhas; elas ficam em "
                                    + "/Library/Application Support/river-unifi-bridge.",
                                    "The service did not erase the key and the passwords; they "
                                    + "stay in /Library/Application Support/river-unifi-bridge.")
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
