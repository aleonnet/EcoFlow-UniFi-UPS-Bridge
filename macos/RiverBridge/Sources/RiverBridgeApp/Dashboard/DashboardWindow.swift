// v5 "Central de Energia": glass side rail (UniFi pattern), the power flow
// as the central hero, full-width dense chart. Glass lives ONLY on the
// control layer; content sits directly on the near-black ground.

import RiverBridgeCore
import ServiceManagement
import SwiftUI

struct DashboardWindow: View {
    // Geometria DESTA janela: a faixa que os botões de fechar/minimizar/ampliar
    // ocupam na barra de título escondida. Não é respiro, é desvio de obstáculo.
    private static let faixaDosBotoesDaJanela: CGFloat = 72

    var store: TelemetryStore
    @State private var section: Section = DashboardWindow.initialSection()
    @State private var headerWidth: CGFloat = 1000
    @State private var beatPulse = false
    @State private var prefs = AppPrefs.shared
    @Namespace private var railNS

    /// Dev seam: `--secao saude|ajustes` opens on that tab (screenshot
    /// validation); normal launches always start on Energia.
    static func initialSection() -> Section {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--secao"), index + 1 < args.count {
            switch args[index + 1] {
            case "saude": return .saude
            case "ajustes": return .ajustes
            default: break
            }
        }
        return .energia
    }

    enum Section: String, CaseIterable, Identifiable {
        case energia = "Energia"
        case saude = "Saúde"
        case ajustes = "Ajustes"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .energia: L10n.t("Energia", "Energy")
            case .saude: L10n.t("Saúde", "Health")
            case .ajustes: L10n.t("Ajustes", "Settings")
            }
        }
        var symbol: String {
            switch self {
            case .energia: "bolt.fill"
            case .saude: "waveform.path.ecg"
            case .ajustes: "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground(store: store)

            VStack(spacing: Espaco.medio) {
                // Nav lives in the hidden-title-bar dead strip: zero useful
                // height spent (owner's call 2026-08-31 — top over side rail,
                // and the same capsule becomes a bottom tab bar on iPhone).
                header

                Group {
                    switch section {
                    case .energia:
                        EnergiaSection(store: store)
                    case .saude: HealthView(store: store)
                    case .ajustes: SettingsView(store: store)
                    }
                }
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Horizontal inset lives INSIDE each section's scroll content:
                // an inset ScrollView paints its backdrop haze as a full-height
                // column and breaks the ground gradient at both edges (owner's
                // print, light theme). Full-bleed scroll, padded content.
                .padding(.bottom, Espaco.largo)
            }
        }
        // Language switch rebuilds the CONTENT tree; the section state lives
        // here (outside the .id boundary), so the open tab survives.
        .id(prefs.language)
        .animation(.snappy(duration: 0.3), value: section)
    }

    // Adaptive tab capsule following the system's own floating tab bar
    // convention (owner 2026-08-31): when narrow, the SELECTED tab keeps
    // icon+label and the others collapse to icon-only with a tooltip.
    private var header: some View {
        let accent = Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
        return HStack {
            HStack(spacing: Espaco.medio) {
                // The logo BEATS with the data: each applied SSE reading
                // (store.beat) fires one systole/diastole — a live pulse,
                // not a decorative loop (owner 2026-08-31).
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        Theme.accentGradient(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
                    )
                    .scaleEffect(beatPulse ? 1.12 : 1.0)
                    .shadow(color: accent.opacity(beatPulse ? 0.75 : 0.25),
                            radius: beatPulse ? 11 : 4)
                if headerWidth >= 560 {
                    Text("River Bridge")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                }
            }
            .padding(.leading, Self.faixaDosBotoesDaJanela)

            Spacer(minLength: 8)

            HStack(spacing: Espaco.fio) {
                ForEach(Section.allCases) { item in
                    let isSelected = section == item
                    let showsLabel = headerWidth >= 700 || isSelected
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: Espaco.mini) {
                            Image(systemName: item.symbol)
                            if showsLabel {
                                Text(item.label)
                                    .fixedSize()
                            }
                        }
                        .font(.system(.callout, design: .rounded)
                            .weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, showsLabel ? 14 : 11)
                        .padding(.vertical, Espaco.pequeno)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.primary.opacity(0.14))
                                .matchedGeometryEffect(id: "rail-sel", in: railNS)
                        }
                    }
                    .help(item.label)
                    .accessibilityLabel(item.label)
                }
            }
            .padding(Espaco.micro)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.trailing, Espaco.secao)
        }
        .padding(.top, Espaco.medio)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            headerWidth = width
        }
        .animation(.snappy(duration: 0.25), value: headerWidth >= 700)
        .onChange(of: store.beat) {
            withAnimation(.easeOut(duration: 0.12)) { beatPulse = true }
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: 0.5)) { beatPulse = false }
            }
        }
    }

}

// Energia = hero flow + dense chart + compact events, all on the ground.
struct EnergiaSection: View {
    var store: TelemetryStore
    @State private var scrollOffset: CGFloat = 0
    @State private var headerMinY: CGFloat = 1000
    /// Ids dos chips ligados (4 do bridge + 1 por instância; vazio = tudo).
    /// `--seam-chip-queda` liga o de queda; `--seam-chip-protecao` liga o chip da
    /// PRIMEIRA instância assim que a lista chega (a captura do chip de proteção).
    @State private var chipIDs: Set<String> =
        ProcessInfo.processInfo.arguments.contains("--seam-chip-queda") ? ["queda"] : []
    @State private var seamProtecao = ProcessInfo.processInfo.arguments.contains("--seam-chip-protecao")
    // Dev seam (screenshot runs): --periodo-datas opens with Datas active.
    @State private var eventPeriod: EventPeriod =
        ProcessInfo.processInfo.arguments.contains("--periodo-datas") ? .personalizado : .tudo
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var customTo = Date.now

    // Validated pattern (onScrollGeometryChange, macOS 15+): the header is
    // TRANSPARENT at rest; material fades in ONLY while it is pinned with
    // content passing underneath — never a visible band on a still page.
    private var headerLit: Bool { scrollOffset > 4 && headerMinY <= 1 }

    var body: some View {
        // Single scroll, no nested scrolling (UX smell): the EVENTOS eyebrow
        // pins at the top while rows pass under — same pattern as Saúde.
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Espaco.medio, pinnedViews: [.sectionHeaders]) {
                Section {
                    // O aviso do topo diz o que está faltando AGORA, e o que
                    // fazer. Ele pergunta ao sistema em que pé o serviço está —
                    // não deduz pela presença de um arquivo.
                    AvisoDoTopo(store: store)
                    FlowScene(store: store)
                    ChartsView(store: store, chips: selectedChips)
                }
                Section {
                    EventsTimeline(store: store, chips: selectedChips, period: eventPeriod,
                                   customFrom: customFrom, customTo: customTo)
                } header: {
                    EventsFilterBar(chipIDs: $chipIDs, all: EventChip.all(devices: store.devices),
                                    period: $eventPeriod,
                                    customFrom: $customFrom, customTo: $customTo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Espaco.pequeno)
                        .background {
                            Rectangle().fill(.ultraThinMaterial)
                                .mask {
                                    LinearGradient(colors: [.black, .black, .clear],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                                .opacity(headerLit ? 1 : 0)
                                .animation(.easeInOut(duration: 0.15), value: headerLit)
                        }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .scrollView).minY
                        } action: { minY in
                            headerMinY = minY
                        }
                }
            }
            .padding(.horizontal, Espaco.respiro)
            .padding(.bottom, Espaco.pequeno)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, offset in
            scrollOffset = offset
        }
        .onChange(of: store.devices, initial: true) { applyChipSeam() }
    }

    private var selectedChips: [EventChip] {
        EventChip.selected(ids: chipIDs, devices: store.devices)
    }

    private func applyChipSeam() {
        guard seamProtecao, let first = EventChip.all(devices: store.devices).first(where: { $0.spec.deviceID != nil }) else { return }
        chipIDs = [first.id]
        seamProtecao = false
    }
}

/// O aviso do topo: o que está faltando agora, e o que fazer a respeito.
///
/// Ele existe porque a tela silenciava ou errava justamente quando o dono mais
/// precisava dela. Duas coisas medidas no Mac mini em 2026-09-05:
///
/// - com uma ficha órfã de uma instalação removida, o painel dizia "sem
///   comunicação com o serviço" — como se houvesse um serviço inalcançável —
///   quando a verdade era que ele não estava instalado. A pergunta agora é feita
///   ao sistema (`ServicoGroup.estadoAgora(respondendo:)`), não ao sistema de arquivos.
/// - sem o NUT instalado, o serviço sobe, não acha o leitor do no-break e diz
///   isso no estado do cabo; a tela não mostrava nada, e o dono via um programa
///   vazio e mudo.
///
/// A ordem é a de quem está travado: primeiro o que impede tudo.
///
/// E é AQUI, na abertura, que o serviço é registrado e a autorização do macOS é
/// pedida — não num botão dentro de Ajustes (o dono abriu o programa no Mac
/// mini, não achou nada na abertura, e chamou o que era, 2026-09-05). A Apple é
/// literal: "check the authorization status at launch. If helper executables
/// don't have authorization, alert the user, and call
/// openSystemSettingsLoginItems()" (citação inteira em ServicoDoSistema.swift).
struct AvisoDoTopo: View {
    var store: TelemetryStore
    @State private var servico: EstadoDoServico = .naoInstalado
    /// A queixa do macOS quando o registro falhou. Vive só enquanto o estado
    /// for "não registrado": assim que o sistema conhece o serviço (por este
    /// botão, pelo de Ajustes, ou porque o macOS completou tarde), ela some —
    /// senão a tela diria "autorize" e "o macOS recusou" ao mesmo tempo, o par
    /// impossível que o dono viu no Mac mini (revisão fria da 0.8.1).
    @State private var queixaDoRegistro: String?

    var body: some View {
        Group {
            if servico.avisaNaAbertura {
                let acao = servico.acaoNaAbertura
                Aviso(tom: .atencao, texto: servico.titulo,
                      detalhe: [servico.explicacao, queixaDoRegistro].compactMap { $0 }
                          .joined(separator: "\n"),
                      simbolo: "power",
                      rotuloDaAcao: acao?.rotulo,
                      acao: acao.map { acao in { executar(acao) } },
                      acaoEmDestaque: true)
            } else if let motivoDoCabo = store.health?.cabo?.motivo,
                      store.health?.cabo?.lendo == false {
                // A frase vem do SERVIÇO — é ele que sabe se o NUT falta, se o
                // leitor não subiu ou se o cabo está emprestado.
                Aviso(tom: .atencao,
                      texto: L10n.t("O River não está sendo lido",
                                    "The River is not being read"),
                      detalhe: motivoDoCabo,
                      simbolo: "cable.connector.horizontal")
            }
        }
        .task {
            // De novo, e de novo. O macOS não avisa quando o dono liga a chave
            // nos Ajustes do Sistema: quem tem de perguntar somos nós. Sem isto
            // a tela ficava congelada em "falta aprovar" DEPOIS de aprovado —
            // visto pelo dono no Mac mini, 2026-09-05, e ele chamou o que era.
            while !Task.isCancelled {
                servico = ServicoGroup.estadoAgora(respondendo: store.phase == .live)
                if !servico.precisaRegistrar { queixaDoRegistro = nil }
                if servico.precisaRegistrar {
                    // O registro da abertura: uma vez por lançamento. Depois
                    // dele o macOS mostra a notificação de autorização, e o
                    // estado passa a "autorize" — o botão ao lado leva ao mesmo
                    // interruptor nos Ajustes do Sistema.
                    let tentativa = ServicoGroup.registrarNaAbertura()
                    if tentativa.tentou {
                        queixaDoRegistro = tentativa.queixa
                        servico = ServicoGroup.estadoAgora(respondendo: store.phase == .live)
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func executar(_ acao: AcaoDoServico) {
        switch acao {
        case .registrar:
            queixaDoRegistro = ServicoGroup.registrar()
            servico = ServicoGroup.estadoAgora(respondendo: store.phase == .live)
            if !servico.precisaRegistrar { queixaDoRegistro = nil }
        case .abrirAjustesDoSistema:
            SMAppService.openSystemSettingsLoginItems()
        case .refazerRegistro:
            Task {
                queixaDoRegistro = await ServicoGroup.refazer()
                servico = ServicoGroup.estadoAgora(respondendo: store.phase == .live)
            }
        }
    }
}

