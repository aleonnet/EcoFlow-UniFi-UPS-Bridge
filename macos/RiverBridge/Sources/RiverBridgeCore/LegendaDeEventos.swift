// A legenda do histograma de eventos — e, com ela, o DOMÍNIO da escala de cor.
//
// Regra única deste arquivo: **toda barra tem a sua cor no domínio.** O Swift
// Charts, com `chartForegroundStyleScale(domain:range:)` explícito, mata o
// processo (SIGTRAP, "brk 1" dentro de Charts) quando uma marca traz um valor
// que não está no domínio. Medido em 2026-09-06, fora do aplicativo, com
// `ImageRenderer` sobre um gráfico de duas barras: domínio ["A"] com uma barra
// "B" → rc 133 (Trace/BPT trap); domínio ["A", "B"] → renderiza. Foi a queda
// que o dono viu ao abrir 24 h / 7 d de eventos: os eventos do cabo
// (CABO_LARGADO_AUTOMATICO…) ganhavam rótulo na barra, mas a legenda só
// conhecia os cinco tipos do bridge e os dos dispositivos — o rótulo ficava
// fora do domínio, e o Charts derrubava o aplicativo.
//
// Por isso a legenda nasce aqui, pura e testável: as chaves saem dos MESMOS
// eventos que viram barra, e o que nenhuma lista conhece entra no fim em vez
// de ficar de fora.

import Foundation

public enum LegendaDeEventos {
    /// Uma entrada da legenda: o texto (que é o valor da escala de cor) e o
    /// tipo de evento de onde a cor sai.
    public struct Chave: Equatable, Sendable {
        public let rotulo: String
        public let tipo: String
        public init(rotulo: String, tipo: String) {
            self.rotulo = rotulo
            self.tipo = tipo
        }
    }

    /// Os eventos do próprio no-break, na ordem em que a legenda os mostra.
    public static let tiposDoBridge = ["POWER_LOSS", "POWER_RESTORED", "LOW_BATTERY", "COMM_LOST", "COMM_RESTORED"]

    /// O rótulo de UMA barra. Dispositivo: o nome único da instância (ordinal
    /// quando duas compartilham o nome) mais o nome curto do evento; sem dono
    /// listado, o nome do tipo. Serviço: o nome curto do vocabulário único da
    /// casa (`DeviceEventKind.doServico`). Desconhecido: "Outro".
    ///
    /// `emPortugues` é o idioma do rótulo. Quem monta a lista inteira lê o idioma
    /// UMA vez e passa-o a cada rótulo: é estado global, e dois rótulos lidos em
    /// instantes diferentes podiam sair em idiomas diferentes.
    public static func rotulo(tipo: String, dispositivo: String?,
                              rotulosUnicos: [String: String], nomes: DeviceNames,
                              dispositivos: [DeviceInstance],
                              emPortugues: Bool = L10n.cachedIsPT) -> String {
        if let kind = DeviceTypeRegistry.eventKind(tipo) {
            let dono = dispositivo.flatMap { rotulosUnicos[$0] }
                ?? nomes.name(forEvent: tipo, device: dispositivo, devices: dispositivos, emPortugues: emPortugues)
            return kind.short(name: dono, emPortugues: emPortugues)
        }
        return DeviceTypeRegistry.qualquerEvento(tipo)?.short(name: "", emPortugues: emPortugues)
            .trimmingCharacters(in: .whitespaces)
            ?? (emPortugues ? "Outro" : "Other")
    }

    /// As chaves da legenda para ESTES eventos, em ordem estável: o bridge, o
    /// vocabulário de cada instância, os demais eventos do serviço — e, no fim,
    /// na ordem de chegada, qualquer evento que nenhuma dessas listas situa (tipo
    /// novo, evento de instância removida). Rótulos únicos; nenhum rótulo
    /// presente fica de fora. É esse último passo que impede a queda do topo.
    ///
    /// O rótulo de cada evento é calculado UMA vez, e a ordem sai da identidade
    /// do evento (tipo e dono), não de uma segunda leitura do rótulo: o idioma é
    /// estado global, e comparar dois rótulos lidos em instantes diferentes era
    /// uma corrida (os testes do Core rodam em paralelo e alternam o idioma).
    public static func chaves(eventos: [(tipo: String, dispositivo: String?)],
                              nomes: DeviceNames, dispositivos: [DeviceInstance],
                              emPortugues: Bool = L10n.cachedIsPT) -> [Chave] {
        let unicos = DeviceNames.uniqueLabels(instances: dispositivos)
        let sobra = lugaresConhecidos(dispositivos: dispositivos)
        var primeira: [String: (tipo: String, posicao: Int)] = [:]
        for (indice, evento) in eventos.enumerated() {
            let texto = rotulo(tipo: evento.tipo, dispositivo: evento.dispositivo, rotulosUnicos: unicos,
                               nomes: nomes, dispositivos: dispositivos, emPortugues: emPortugues)
            // Sem lugar nas listas: entra no fim, na ordem de chegada. Deixar de
            // fora é a queda descrita no topo.
            let posicao = lugar(tipo: evento.tipo, dispositivo: evento.dispositivo, dispositivos: dispositivos) ?? sobra + indice
            if let existente = primeira[texto], existente.posicao <= posicao { continue }
            primeira[texto] = (evento.tipo, posicao)
        }
        return primeira
            .sorted { ($0.value.posicao, $0.key) < ($1.value.posicao, $1.key) }
            .map { Chave(rotulo: $0.key, tipo: $0.value.tipo) }
    }

    /// Os eventos do serviço que não são os cinco do bridge, na ordem da casa.
    private static var demaisDoServico: [DeviceEventKind] {
        DeviceEventKind.doServico.filter { !tiposDoBridge.contains($0.type) }
    }

    /// Quantos lugares as listas conhecidas ocupam; a sobra começa depois deles.
    private static func lugaresConhecidos(dispositivos: [DeviceInstance]) -> Int {
        tiposDoBridge.count
            + dispositivos.reduce(0) { $0 + (DeviceTypeRegistry.type(id: $1.type)?.events.count ?? 0) }
            + demaisDoServico.count
    }

    /// A posição de um evento na ordem da legenda, ou `nil` quando nenhuma lista
    /// o situa. Espelha `rotulo`: evento de dispositivo sem dono declarado vai
    /// para a única instância do tipo, e só para ela.
    private static func lugar(tipo: String, dispositivo: String?, dispositivos: [DeviceInstance]) -> Int? {
        if let indice = tiposDoBridge.firstIndex(of: tipo) { return indice }
        var base = tiposDoBridge.count
        if let kind = DeviceTypeRegistry.type(forEventType: tipo) {
            let dono: Int? = dispositivo.map { id in dispositivos.firstIndex { $0.id == id } }
                ?? unicaInstancia(doTipo: kind.id, em: dispositivos)
            guard let dono else { return nil }
            for (indice, instancia) in dispositivos.enumerated() {
                let vocabulario = DeviceTypeRegistry.type(id: instancia.type)?.events ?? []
                if indice == dono {
                    return vocabulario.firstIndex { $0.type == tipo }.map { base + $0 }
                }
                base += vocabulario.count
            }
            return nil
        }
        base = lugaresConhecidos(dispositivos: dispositivos) - demaisDoServico.count
        return demaisDoServico.firstIndex { $0.type == tipo }.map { base + $0 }
    }

    private static func unicaInstancia(doTipo tipo: String, em dispositivos: [DeviceInstance]) -> Int? {
        let indices = dispositivos.indices.filter { dispositivos[$0].type == tipo }
        return indices.count == 1 ? indices[0] : nil
    }
}
