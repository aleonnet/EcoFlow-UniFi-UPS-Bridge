// O widget do macOS (0.10.0): carga, autonomia, fonte e watts na área de
// widgets, como o widget de Baterias da Apple. Dois tamanhos.
//
// Este processo roda em caixa de areia e não fala com o serviço: lê o retrato
// que o app grava no contêiner do grupo (RetratoDoWidget, no Core) e desenha.
// A linha do tempo tem entradas a cada 5 min até 25 min — a idade do retrato
// cresce a cada entrada sem recarga — e pede recarga aos 30 (`.after`), o que dá
// 48 pedidos por dia, dentro do orçamento documentado de 40 a 70. A última
// entrada fica em 25 min de propósito: uma em 30 cairia SEMPRE no traço (o
// retrato tem 0–2 min ao recarregar; 30 + 2 > 30), mesmo com o app aberto.
// Se o sistema atrasar a recarga, o widget fica em "às HH:MM", que é a verdade. Cada pedido
// atendido fica em `recargas.log` no contêiner, para a bancada medir quantos o
// sistema honra de fato. Sem retrato ou com retrato de mais de meia hora, o
// widget mostra traço e o que fazer — dado velho não é presente.

import RiverBridgeCore
import SwiftUI
import WidgetKit

struct Entrada: TimelineEntry {
    let date: Date
    let retrato: RetratoDoWidget?
}

struct Provedor: TimelineProvider {
    static let passo: TimeInterval = 5 * 60
    static let janela: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> Entrada {
        Entrada(date: .now, retrato: Self.exemplo(agora: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) {
        let retrato = context.isPreview ? Self.exemplo(agora: .now) : Self.retratoAtual()
        completion(Entrada(date: .now, retrato: retrato))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        Self.registraRecarga()
        let agora = Date.now
        let retrato = Self.retratoAtual()
        let entradas = stride(from: 0.0, to: Self.janela, by: Self.passo)
            .map { Entrada(date: agora.addingTimeInterval($0), retrato: retrato) }
        completion(Timeline(entries: entradas, policy: .after(agora.addingTimeInterval(Self.janela))))
    }

    static func retratoAtual() -> RetratoDoWidget? {
        RetratoDoWidget.url().flatMap(RetratoDoWidget.ler(de:))
    }

    /// O que a galeria mostra antes de haver retrato: um River na tomada.
    static func exemplo(agora: Date) -> RetratoDoWidget {
        RetratoDoWidget(quando: agora, emPortugues: Locale.current.language.languageCode?.identifier != "en",
                        servicoNoAr: true, cargaPct: 100, autonomiaS: 9240, estado: "ONLINE",
                        carregando: false, entradaW: 70, consumoW: 65, bateriaBaixa: false)
    }

    /// Uma linha por pedido de recarga atendido — a medição do orçamento.
    static func registraRecarga(agora: Date = .now) {
        guard let pasta = RetratoDoWidget.url()?.deletingLastPathComponent() else { return }
        let arquivo = pasta.appendingPathComponent("recargas.log")
        let linha = ISO8601DateFormatter().string(from: agora) + "\n"
        if let h = try? FileHandle(forWritingTo: arquivo) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(linha.utf8))
        } else {
            try? Data(linha.utf8).write(to: arquivo)
        }
    }
}

// MARK: - Cores (a paleta vive no Core; aqui só se constrói o Color)

extension Color {
    init(paleta: Paleta.RGB) { self.init(red: paleta.r, green: paleta.g, blue: paleta.b) }
}

/// Os textos e as cores de uma entrada, decididos uma vez por desenho.
struct Leitura {
    let retrato: RetratoDoWidget?
    let idade: IdadeDoRetrato
    let emPortugues: Bool

    init(entrada: Entrada) {
        retrato = entrada.retrato
        idade = IdadeDoRetrato.para(retrato: entrada.retrato, agora: entrada.date)
        emPortugues = entrada.retrato?.emPortugues ?? (Locale.current.language.languageCode?.identifier != "en")
    }

    func t(_ pt: String, _ en: String) -> String { emPortugues ? pt : en }

    /// Traço quando o retrato é velho ou não existe, ou quando o serviço não lia.
    var vivo: RetratoDoWidget? {
        guard idade != .traco, let retrato, retrato.servicoNoAr else { return nil }
        return retrato
    }
    var fracao: Double { min(max((vivo?.cargaPct ?? 0) / 100, 0), 1) }
    var cargaTexto: String { TelemetryStore.percentText(vivo?.cargaPct) }
    var autonomiaTexto: String { TelemetryStore.runtimeText(vivo?.autonomiaS) }
    var entradaTexto: String { TelemetryStore.wattsText(vivo?.entradaW) }
    var consumoTexto: String { TelemetryStore.wattsText(vivo?.consumoW) }
    var fonteTexto: String {
        guard let vivo else { return "—" }
        switch vivo.estado {
        case "ONLINE": return t("Na tomada", "On grid")
        case "ON_BATTERY": return t("Na bateria", "On battery")
        case "OUTPUT_OFF": return t("Saída desligada", "Output off")
        default: return t("Sem leitura", "No reading")
        }
    }
    var cores: [Color] {
        Paleta.doEstado(naBateria: vivo?.naBateria == true, baixa: vivo?.bateriaBaixa == true).map(Color.init(paleta:))
    }
    /// A linha de baixo: a hora quando o retrato já tem mais de 2 min; o que
    /// fazer quando é traço.
    var rodape: String? {
        switch idade {
        case .valores: return vivo == nil ? t("sem leitura do River", "no reading from the River") : nil
        case .valoresComHora(let hora): return t("às ", "at ") + hora
        case .traco: return t("abra o River Bridge", "open River Bridge")
        }
    }
}

struct Anel: View {
    let leitura: Leitura
    var espessura: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, style: StrokeStyle(lineWidth: espessura, lineCap: .round))
            Circle()
                .trim(from: 0, to: leitura.vivo == nil ? 0 : leitura.fracao)
                .stroke(AngularGradient(colors: [leitura.cores[0], leitura.cores[1], leitura.cores[0]], center: .center),
                        style: StrokeStyle(lineWidth: espessura, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(leitura.cargaTexto)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(Espaco.cartao)
        }
    }
}

struct VistaPequena: View {
    let leitura: Leitura

    var body: some View {
        VStack(spacing: Espaco.pequeno) {
            Anel(leitura: leitura)
            VStack(spacing: Espaco.fio) {
                // Sem leitura viva, o anel já mostra o traço: a linha de baixo
                // fica só para o que fazer (o rodapé).
                if leitura.vivo != nil {
                    Text("\(leitura.fonteTexto) · \(leitura.autonomiaTexto)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let rodape = leitura.rodape {
                    Text(rodape).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(Espaco.mini)
    }
}

struct VistaMedia: View {
    let leitura: Leitura

    var body: some View {
        HStack(spacing: Espaco.largo) {
            Anel(leitura: leitura)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: Espaco.pequeno) {
                Text("River").font(.headline)
                linha(leitura.t("Fonte", "Source"), leitura.fonteTexto)
                linha(leitura.t("Autonomia", "Runtime"), leitura.autonomiaTexto)
                linha(leitura.t("Entrada da rede", "Grid input"), leitura.entradaTexto)
                linha(leitura.t("Consumo", "Draw"), leitura.consumoTexto)
                if let rodape = leitura.rodape {
                    Text(rodape).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Espaco.mini)
    }

    private func linha(_ rotulo: String, _ valor: String) -> some View {
        HStack(spacing: Espaco.pequeno) {
            Text(rotulo).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: Espaco.micro)
            Text(valor).font(.caption.weight(.medium)).monospacedDigit()
        }
    }
}

struct RiverBridgeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entrada: Entrada

    var body: some View {
        let leitura = Leitura(entrada: entrada)
        Group {
            switch family {
            case .systemMedium: VistaMedia(leitura: leitura)
            default: VistaPequena(leitura: leitura)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

@main
struct RiverBridgeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RetratoDoWidget.kind, provider: Provedor()) { entrada in
            RiverBridgeWidgetEntryView(entrada: entrada)
        }
        .configurationDisplayName("River Bridge")
        .description(Locale.current.language.languageCode?.identifier == "en"
                     ? "Charge, runtime, source and watts of your River."
                     : "Carga, autonomia, fonte e watts do seu River.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
