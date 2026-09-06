// O retrato que o app grava para o widget (0.10.0), e as regras em volta dele:
// quando pedir recarga e como a idade do retrato vira o que a tela mostra.
//
// Por que um arquivo: a extensão de widget roda em caixa de areia, noutro
// processo, sem a ficha do serviço nem o soquete — o único chão comum é o
// contêiner do grupo de aplicativos (`<Team ID>.<nome>`, sem registro na Apple:
// "You don't need to register app groups that use this format on the Apple
// Developer website", docs/bundleresources/entitlements/com.apple.security.application-groups;
// e "macOS checks that the code signature of processes that try to access the
// app group container contains the same [Team ID]", docs/xcode/configuring-app-groups).
// Medido em 2026-09-06 nesta máquina: `containerURL(forSecurityApplicationGroupIdentifier:)`
// → ~/Library/Group Containers/8A47D8UNV2.com.river.bridge, gravável pelo app.
//
// Por que "só quando muda" e "só em mudança de significado": o WidgetKit dá a
// cada widget um orçamento de 40 a 70 recargas por dia (docs/widgetkit/keeping-a-widget-up-to-date);
// um estado chega por SSE a cada ~2 s. O app grava o arquivo quando o conteúdo
// muda (não a hora) e pede recarga quando o SIGNIFICADO muda (fonte, bateria
// baixa, serviço, degrau de 10 pontos). O periódico é da linha do tempo do
// próprio widget.
//
// Regra da casa que vale aqui inteira: dado ausente é `nil`, nunca zero; e dado
// velho não é presente (IdadeDoRetrato).

import Foundation

public struct RetratoDoWidget: Codable, Equatable, Sendable {
    /// O grupo de aplicativos — Team ID + nome. O empacotador confere que o Team
    /// ID da identidade de assinatura é este prefixo (build-app.sh).
    public static let grupo = "8A47D8UNV2.com.river.bridge"
    /// O `kind` do widget (o mesmo em WidgetCenter.reloadTimelines).
    public static let kind = "river-bridge"
    public static let nomeDoArquivo = "retrato.json"
    /// Degrau de carga que conta como mudança de significado (pontos percentuais).
    public static let degrauDeCarga = 10.0

    public var quando: Date
    public var emPortugues: Bool
    public var servicoNoAr: Bool
    public var cargaPct: Double?
    public var autonomiaS: Double?
    /// "ONLINE", "ON_BATTERY", "OUTPUT_OFF", "UNKNOWN" — o `power.state` do serviço.
    public var estado: String?
    public var carregando: Bool
    public var entradaW: Double?
    public var consumoW: Double?
    public var bateriaBaixa: Bool

    public init(quando: Date, emPortugues: Bool, servicoNoAr: Bool, cargaPct: Double? = nil,
                autonomiaS: Double? = nil, estado: String? = nil, carregando: Bool = false,
                entradaW: Double? = nil, consumoW: Double? = nil, bateriaBaixa: Bool = false) {
        self.quando = quando
        self.emPortugues = emPortugues
        self.servicoNoAr = servicoNoAr
        self.cargaPct = cargaPct
        self.autonomiaS = autonomiaS
        self.estado = estado
        self.carregando = carregando
        self.entradaW = entradaW
        self.consumoW = consumoW
        self.bateriaBaixa = bateriaBaixa
    }

    /// O retrato a partir do estado que o serviço publicou. `viva == false`
    /// (serviço parado ou aparelho mudo) = retrato sem números: a última leitura
    /// não é o presente.
    public static func de(estado: UpsState?, viva: Bool, emPortugues: Bool, agora: Date) -> RetratoDoWidget {
        let e = viva ? estado : nil
        return RetratoDoWidget(
            quando: agora, emPortugues: emPortugues, servicoNoAr: viva,
            cargaPct: e?.battery?.chargePercent,
            autonomiaS: e?.battery?.runtimeSeconds,
            estado: e?.power?.state,
            carregando: e?.power?.states?.contains("CHARGING") == true,
            entradaW: e?.power?.inputPowerW,
            consumoW: e?.power?.outputPowerW,
            bateriaBaixa: e?.health?.lowBattery == true)
    }

    /// O mesmo conteúdo, ignorando a hora: é o que decide se o arquivo é regravado.
    public func mesmoConteudo(que outro: RetratoDoWidget) -> Bool {
        var a = self, b = outro
        a.quando = .distantPast; b.quando = .distantPast
        return a == b
    }

    public var naBateria: Bool { estado == "ON_BATTERY" }

    /// O app pede recarga só quando o SIGNIFICADO mudou. Sem relógio: o
    /// periódico é da linha do tempo do widget.
    public static func deveRecarregar(anterior: RetratoDoWidget?, novo: RetratoDoWidget) -> Bool {
        guard let anterior else { return true }
        let mudouFonte = anterior.naBateria != novo.naBateria
        let mudouBaixa = anterior.bateriaBaixa != novo.bateriaBaixa
        let mudouServico = anterior.servicoNoAr != novo.servicoNoAr
        let cruzouDegrau = degrau(anterior.cargaPct) != degrau(novo.cargaPct)
        return mudouFonte || mudouBaixa || mudouServico || cruzouDegrau
    }

    private static func degrau(_ carga: Double?) -> Int {
        guard let carga else { return -1 }
        return Int((carga / degrauDeCarga).rounded(.down))
    }

    // MARK: - Disco

    /// Onde o retrato mora: o contêiner do grupo. `nil` quando o sistema não dá
    /// contêiner (assinatura sem o grupo, por exemplo).
    public static func url(fm: FileManager = .default) -> URL? {
        fm.containerURL(forSecurityApplicationGroupIdentifier: grupo)?.appendingPathComponent(nomeDoArquivo)
    }

    private static func codificador() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decodificador() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func gravar(em url: URL, fm: FileManager = .default) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.codificador().encode(self).write(to: url, options: .atomic)
    }

    public static func ler(de url: URL) -> RetratoDoWidget? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decodificador().decode(RetratoDoWidget.self, from: data)
    }
}

/// O que o widget mostra conforme a idade do retrato. Dado velho não é presente.
public enum IdadeDoRetrato: Equatable, Sendable {
    /// Até 2 min: os valores, sem mais.
    case valores
    /// De 2 a 30 min: os valores e a hora em que foram lidos.
    case valoresComHora(String)
    /// Mais de 30 min, ou sem retrato: traço, e o que fazer.
    case traco

    public static let limiteDaHora: TimeInterval = 2 * 60
    public static let limiteDoTraco: TimeInterval = 30 * 60

    public static func para(retrato: RetratoDoWidget?, agora: Date,
                            calendario: Calendar = .current) -> IdadeDoRetrato {
        guard let retrato else { return .traco }
        let idade = agora.timeIntervalSince(retrato.quando)
        if idade > limiteDoTraco { return .traco }
        if idade > limiteDaHora {
            let c = calendario.dateComponents([.hour, .minute], from: retrato.quando)
            return .valoresComHora(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
        }
        return .valores
    }
}
