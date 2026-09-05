// Models mirroring the daemon's §7.3 JSON (docs/API_LOCAL_20260831.md).
// Hard rule: every telemetry field is Optional — absent data renders as "—",
// never as an invented value.

import Foundation

public struct UpsState: Codable, Equatable, Sendable {
    public struct Identity: Codable, Equatable, Sendable {
        public var name: String?
        public var manufacturer: String?
        public var model: String?
        public var serial: String?
    }

    public struct Power: Codable, Equatable, Sendable {
        public var state: String?
        public var states: [String]?
        public var inputPresent: Bool?
        public var inputVoltageV: Double?
        public var outputVoltageV: Double?
        public var outputPowerW: Double?
        public var loadPercent: Double?
        /// O que ENTRA da rede, quando o aparelho publica (River 3 Plus, pela
        /// porta serial do mesmo cabo).
        public var inputPowerW: Double?
        public var lineFrequencyHz: Double?
    }

    /// Consumo por tomada. Só existe quando o aparelho tem uma segunda porta que
    /// o publique; ausente vira "—", nunca zero.
    public struct Outlets: Codable, Equatable, Sendable {
        public var totalW: Double?
        public var inputW: Double?
        public var inputAcW: Double?
        public var inputSolarDcW: Double?
        public var acW: Double?
        public var dcW: Double?
        public var usbAW: Double?
        public var usbCW: Double?
        public var lineFrequencyHz: Double?
        // Sem CodingKeys: o decodificador da casa já converte `usb_a_w` em
        // `usbAW` (convertFromSnakeCase). Declará-las aqui em snake_case fazia o
        // par nunca casar, e a tela mostrava traço com o dado na mão.
    }

    public struct Battery: Codable, Equatable, Sendable {
        public var chargePercent: Double?
        /// O aviso de bateria fraca DO APARELHO (o "Low battery reminder" do
        /// aplicativo da EcoFlow). É gravável: a tela de Ajustes o edita.
        public var chargeLowPercent: Double?
        public var runtimeSeconds: Double?
        public var voltageV: Double?
        public var temperatureC: Double?
    }

    public struct Health: Codable, Equatable, Sendable {
        public var communicationOk: Bool?
        public var lowBattery: Bool?
        public var overload: Bool?
        public var alarm: [String]?
        public var unknownStatusTokens: [String]?
        public var lastError: String?
    }

    public var identity: Identity?
    public var power: Power?
    public var battery: Battery?
    public var health: Health?
    public var outlets: Outlets?
    public var timestamp: String?
}

public struct HealthChain: Codable, Equatable, Sendable {
    public var usb: String?
    public var nut: String?
    public var bridge: String?
    public var unifi: String?
    /// Fase 3'-EXP — closed enum from the daemon's protection policy
    /// (docs/API_LOCAL_20260831.md). nil on daemons that predate the phase.
    public var udr7: String?
    public var udr7Detail: Udr7Detail?
    /// Every protected device, from the daemon's plugin registry (P6). `udr7` and
    /// `udr7Detail` above stay as an alias of the entry with id "udr7".
    /// Optional: daemons that predate the plugin phase publish nothing here.
    public var plugins: [HealthPlugin]?
    public var ha: String?
    public var lastError: String?
    public var hasSnapshot: Bool?
}

/// Detail of one protected device (the SSH engine's status, any type). Every
/// field optional: the daemon publishes null until the first tick, and older
/// daemons publish nothing at all. `Udr7Detail` stays as the historical name.
public typealias Udr7Detail = DeviceDetail

public struct DeviceDetail: Codable, Equatable, Sendable {
    public var state: String?
    public var dryRun: Bool?
    public var enabled: Bool?
    public var source: String?
    public var sourceDetail: String?
    public var missingKey: String?
    public var cutoff: Int?
    public var threshold: Int?
    public var chargeLow: Double?
    public var marginEstimateS: Int?
    public var warnings: [String]?
    public var sshHost: String?
    public var sshBinary: String?
    public var lastEvent: String?
    public var lastEventAt: String?
    public var outage: Bool?
    public var attempts: Int?
    public var sentPendingRestore: Bool?
    /// O serviço já provou que fala com este aparelho? Desde a 0.6.0 armar exige
    /// isso — e a tela mostra a razão antes do clique, não depois.
    public var alcanceVerificado: Bool?
    public var alcanceModelo: String?
    /// The name the user gave the device (`UDR7_NAME`). The daemon already puts
    /// its default here when the key is blank.
    public var name: String?
}

public struct HistoryRow: Codable, Equatable, Sendable {
    public var ts: Int
    public var avg: Double?
}

public struct HistoryResponse: Codable, Equatable, Sendable {
    public var metric: String
    public var bucketSeconds: Int
    public var rows: [HistoryRow]
}

public struct BridgeEvent: Codable, Equatable, Sendable, Identifiable {
    public var ts: String
    public var event: String
    public var state: String?
    public var charge: Double?
    public var reason: String?
    /// The owning device INSTANCE (2026-09-03); nil for bridge events and for
    /// rows written before the daemon carried it.
    public var device: String?
    /// Sequência do serviço (2026-09-03): só cresce, e é o que distingue dois
    /// eventos do mesmo tipo no mesmo segundo. Ausente nas linhas do histórico
    /// e em serviços anteriores.
    public var seq: Int?

    /// A identidade da linha na tela. A sequência do serviço distingue dois
    /// eventos iguais no mesmo segundo; sem ela (linhas vindas do histórico), o
    /// dono do evento e o detalhe entram na conta, porque dois dispositivos do
    /// mesmo tipo colidiam e a lista descartava um.
    public var id: String {
        seq.map(String.init) ?? "\(ts)-\(event)-\(device ?? "-")-\(reason ?? "-")"
    }

    /// O instante do evento, quando o carimbo é legível.
    public var date: Date? { parsedDate }

    private var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: ts)
    }

    /// "31/08 · 15:11:30" for list rows (owner: date+time on the event).
    public var dayTimeText: String {
        guard let date = parsedDate else { return ts }
        let out = DateFormatter()
        out.dateFormat = "dd/MM · HH:mm:ss"
        return out.string(from: date)
    }
}

public struct ConfigResponse: Codable, Equatable, Sendable {
    public var config: [String: ConfigValue]
}

/// GET /v1/version — a versão do SERVIÇO que responde (a do app vem do bundle).
public struct VersionResponse: Codable, Equatable, Sendable {
    public var version: String
}

/// Config values arrive as heterogeneous JSON (string/int/bool).
public enum ConfigValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let b = try? single.decode(Bool.self) { self = .bool(b); return }
        if let i = try? single.decode(Int.self) { self = .int(i); return }
        self = .string(try single.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .string(let s): try single.encode(s)
        case .int(let i): try single.encode(i)
        case .bool(let b): try single.encode(b)
        }
    }

    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    /// String view for text fields (ints/bools render as their text form).
    public var stringValue: String {
        switch self {
        case .string(let s): s
        case .int(let i): String(i)
        case .bool(let b): b ? "1" : "0"
        }
    }

    /// Bool view: JSON true/false, or the .env 1/0 convention.
    public var boolValue: Bool? {
        switch self {
        case .bool(let b): b
        case .int(let i): i != 0
        case .string(let s): ["1", "true", "TRUE", "yes"].contains(s) ? true
            : (["0", "false", "FALSE", "no"].contains(s) ? false : nil)
        }
    }
}

public enum JSONCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// One persisted row from GET /v1/events/log ({ts, type, detail, device}).
public struct EventLogRow: Codable, Equatable, Sendable, Identifiable {
    public var ts: Int
    public var type: String
    public var detail: String?
    public var device: String?

    public var id: String { "\(ts)-\(type)-\(device ?? "-")-\(detail ?? "-")" }

    /// O mesmo instante na forma do evento do stream, para a lista desenhar um
    /// tipo de linha só.
    ///
    /// O serviço grava o detalhe dos eventos do bridge em forma de máquina
    /// (`estado=ON_BATTERY carga=42`), que é ótima no registro e **péssima na
    /// tela**. Aqui ela é decodificada nos campos que a tela já mostra em
    /// português; o que não casa com esse formato continua indo como veio.
    public var asBridgeEvent: BridgeEvent {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let iso = formatter.string(from: Date(timeIntervalSince1970: Double(ts)))
        let (estado, carga, resto) = EventLogRow.decodeDetalhe(detail)
        return BridgeEvent(ts: iso, event: type, state: estado, charge: carga,
                           reason: resto, device: device)
    }

    /// `estado=ON_BATTERY carga=42` → ("ON_BATTERY", 42, nil). Sem esse formato,
    /// devolve o texto intacto no terceiro item.
    static func decodeDetalhe(_ detalhe: String?) -> (String?, Double?, String?) {
        guard let detalhe, !detalhe.isEmpty else { return (nil, nil, nil) }
        var estado: String?
        var carga: Double?
        var sobrou: [String] = []
        for pedaco in detalhe.split(separator: " ") {
            if pedaco.hasPrefix("estado=") {
                estado = String(pedaco.dropFirst("estado=".count))
            } else if pedaco.hasPrefix("carga="), let n = Double(pedaco.dropFirst("carga=".count)) {
                carga = n
            } else {
                sobrou.append(String(pedaco))
            }
        }
        if estado == nil && carga == nil { return (nil, nil, detalhe) }
        return (estado, carga, sobrou.isEmpty ? nil : sobrou.joined(separator: " "))
    }
}

public struct EventsLogResponse: Codable, Sendable {
    public var rows: [EventLogRow]
}

// MARK: - Instâncias de dispositivos protegidos (2026-09-03)

/// One protected-device INSTANCE as `GET /v1/devices` publishes it. `fields` is
/// the type's own dictionary (the app knows each type's fields by hand — no
/// schema→UI). O estado de cada dispositivo vem do health, que é o que a tela
/// já acompanha; ler o mesmo estado por duas rotas dava duas verdades.
public struct DeviceInstance: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var name: String
    public var enabled: Bool?
    public var dryRun: Bool?
    public var fields: [String: ConfigValue]
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: String, type: String, name: String, enabled: Bool? = nil, dryRun: Bool? = nil,
                fields: [String: ConfigValue] = [:], createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.enabled = enabled
        self.dryRun = dryRun
        self.fields = fields
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DevicesResponse: Codable, Sendable {
    public var devices: [DeviceInstance]
}

public struct DeviceResponse: Codable, Sendable {
    public var device: DeviceInstance
}

/// One field of a device TYPE, from `GET /v1/device-types`. Consumed for
/// defaults and for the contract test (`fieldKeys` == catalog) — never to
/// generate a form.
public struct DeviceTypeField: Codable, Equatable, Sendable {
    public var name: String
    public var type: String
    public var defaultValue: ConfigValue?
    public var enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case name, type
        case defaultValue = "default"
        case enumValues = "enum"
    }
}

public struct DeviceTypeInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var labelPt: String
    public var fields: [DeviceTypeField]
    /// O vocabulário fechado de estados que o serviço pode publicar para este
    /// tipo. O app confere que sabe desenhar todos — estado sem selo apareceria
    /// como dispositivo bloqueado e sem explicação nenhuma.
    public var states: [String]?

    public func defaultValue(for field: String) -> ConfigValue? {
        fields.first { $0.name == field }?.defaultValue
    }
}

/// Quem está com o cabo do River, como o serviço publica em `/v1/river/cabo`.
public struct EstadoDoCabo: Codable, Equatable, Sendable {
    /// `nil` quando o serviço não cuida do leitor (instalação antiga).
    public var lendo: Bool?
    public var pausado: Bool?
    public var motivo: String?

    public init(lendo: Bool?, pausado: Bool?, motivo: String? = nil) {
        self.lendo = lendo
        self.pausado = pausado
        self.motivo = motivo
    }
}

public struct DeviceTypesResponse: Codable, Sendable {
    public var types: [DeviceTypeInfo]
}


/// O que a rota de preparar devolve. A chave PRIVADA não está aqui, e nunca
/// estará: o serviço não a expõe por rota nenhuma.
public struct AcessoPreparado: Decodable, Sendable {
    public let chavePublica: String
    public let impressaoDaChave: String
    public let impressaoDoConsole: String
}

/// O resultado de "Testar conexão": o que o console respondeu, e a prova gravada.
public struct AcessoTestado: Decodable, Sendable {
    public struct Resposta: Decodable, Sendable {
        public let probe: String?
        public let model: String?
        public let firmware: String?
    }

    public let alcance: Bool
    public let resposta: Resposta?
    public let motivo: String?
}
