// A folha de detalhe do River: tudo o que o aparelho publica, em quatro grupos
// (aparelho, potência, bateria, rede), já formatado — "—" onde não há leitura.
//
// Mora no Core, e não na camada de desenho, porque é o que se testa: cada linha
// tem rótulo e valor decididos aqui a partir do estado que o serviço publica
// (`/v1/state`), e a tela só desenha a lista. Regra da casa que vale inteira:
// dado ausente vira traço, nunca zero — e com o serviço parado ou o aparelho
// mudo (`viva == false`) a folha inteira é traço, porque a última leitura não é
// o presente.
//
// O idioma é parâmetro lido uma vez por chamada (é estado global, e os testes do
// Core rodam em paralelo — ver LegendaDeEventos).

import Foundation

public struct FolhaDoRiver: Equatable, Sendable {
    public struct Linha: Equatable, Sendable {
        public let rotulo: String
        public let valor: String
        /// Uma observação curta sob o valor, quando o traço precisa de motivo.
        public let nota: String?
        public init(rotulo: String, valor: String, nota: String? = nil) {
            self.rotulo = rotulo
            self.valor = valor
            self.nota = nota
        }
    }

    public struct Grupo: Equatable, Sendable {
        public let titulo: String
        public let linhas: [Linha]
        public init(titulo: String, linhas: [Linha]) {
            self.titulo = titulo
            self.linhas = linhas
        }
    }

    /// O nome do aparelho (o modelo que o no-break informa) e a série.
    public let titulo: String
    public let serie: String
    public let grupos: [Grupo]

    public init(estado: UpsState?, viva: Bool, emPortugues: Bool = L10n.cachedIsPT) {
        func t(_ pt: String, _ en: String) -> String { emPortugues ? pt : en }
        let e = viva ? estado : nil
        let o = e?.outlets
        titulo = e?.identity?.model ?? "River"
        serie = e?.identity?.serial ?? "—"

        let carregando = e?.power?.states?.contains("CHARGING") == true
        let notaDaCarga: String? = (o?.timeToFullMinutes == nil && viva)
            ? (carregando ? nil : t("só aparece enquanto carrega", "shown only while charging"))
            : nil

        grupos = [
            Grupo(titulo: t("Aparelho", "Device"), linhas: [
                Linha(rotulo: t("Modelo", "Model"), valor: e?.identity?.model ?? "—"),
                Linha(rotulo: t("Série", "Serial"), valor: e?.identity?.serial ?? "—"),
                Linha(rotulo: t("Capacidade de projeto", "Design capacity"),
                      valor: Self.mahText(o?.designCapacityMah, emPortugues: emPortugues)),
            ]),
            Grupo(titulo: t("Potência", "Power"), linhas: [
                Linha(rotulo: t("Entrada da rede", "Grid input"), valor: TelemetryStore.wattsText(o?.inputAcW)),
                Linha(rotulo: t("Entrada solar/DC", "Solar/DC input"), valor: TelemetryStore.wattsText(o?.inputSolarDcW)),
                Linha(rotulo: t("Tomada 120 V", "120 V outlet"), valor: TelemetryStore.wattsText(o?.acW)),
                Linha(rotulo: t("Saída 12 V", "12 V output"), valor: TelemetryStore.wattsText(o?.dcW)),
                Linha(rotulo: "USB-A", valor: TelemetryStore.wattsText(o?.usbAW)),
                Linha(rotulo: "USB-C", valor: TelemetryStore.wattsText(o?.usbCW)),
                Linha(rotulo: t("Consumo total", "Total draw"), valor: TelemetryStore.wattsText(o?.totalW)),
            ]),
            Grupo(titulo: t("Bateria", "Battery"), linhas: [
                Linha(rotulo: t("Nível", "Level"), valor: TelemetryStore.percentText(e?.battery?.chargePercent)),
                Linha(rotulo: t("Autonomia", "Runtime"), valor: TelemetryStore.runtimeText(e?.battery?.runtimeSeconds)),
                Linha(rotulo: t("Tempo para carga completa", "Time to full charge"),
                      valor: Self.minutesText(o?.timeToFullMinutes), nota: notaDaCarga),
                Linha(rotulo: t("Temperatura da bateria", "Battery temperature"),
                      valor: Self.celsiusText(o?.batteryTemperatureC ?? e?.battery?.temperatureC)),
                Linha(rotulo: t("Temperatura do sistema", "System temperature"),
                      valor: Self.celsiusText(o?.systemTemperatureC)),
            ]),
            Grupo(titulo: t("Rede", "Grid"), linhas: [
                Linha(rotulo: t("Frequência", "Frequency"), valor: Self.hertzText(o?.lineFrequencyHz ?? e?.power?.lineFrequencyHz)),
                Linha(rotulo: t("Situação", "Status"), valor: Self.situacaoText(e?.power?.state, emPortugues: emPortugues)),
            ]),
        ]
    }

    // MARK: - Formatadores (puros)

    /// 12800 → "12.800 mAh" (pt) / "12,800 mAh" (en); nil → "—".
    public static func mahText(_ value: Int?, emPortugues: Bool) -> String {
        guard let value else { return "—" }
        let digitos = String(value)
        var agrupado = ""
        for (i, c) in digitos.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { agrupado.append(emPortugues ? "." : ",") }
            agrupado.append(c)
        }
        return String(agrupado.reversed()) + " mAh"
    }

    /// 34.0 → "34 °C"; nil → "—".
    public static func celsiusText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) °C"
    }

    /// 90 → "1 h 30 min"; 45 → "45 min"; nil → "—" (não está carregando).
    public static func minutesText(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        return TelemetryStore.runtimeText(Double(minutes) * 60)
    }

    /// 60.0 → "60 Hz"; nil → "—".
    public static func hertzText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) Hz"
    }

    public static func situacaoText(_ state: String?, emPortugues: Bool) -> String {
        switch state {
        case "ONLINE": return emPortugues ? "Na tomada" : "On grid"
        case "ON_BATTERY": return emPortugues ? "Na bateria" : "On battery"
        case "OUTPUT_OFF": return emPortugues ? "Saída desligada" : "Output off"
        case nil: return "—"
        default: return emPortugues ? "Sem leitura" : "No reading"
        }
    }
}
