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
    }

    public struct Battery: Codable, Equatable, Sendable {
        public var chargePercent: Double?
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
    public var timestamp: String?
}

public struct HealthChain: Codable, Equatable, Sendable {
    public var usb: String?
    public var nut: String?
    public var bridge: String?
    public var unifi: String?
    public var ha: String?
    public var lastError: String?
    public var hasSnapshot: Bool?
}

public struct HistoryRow: Codable, Equatable, Sendable {
    public var ts: Int
    public var avg: Double?
    public var min: Double?
    public var max: Double?
    public var n: Int
}

public struct HistoryResponse: Codable, Equatable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public var ts: Int
        public var type: String
        public var detail: String?
    }

    public var metric: String
    public var bucketSeconds: Int
    public var rows: [HistoryRow]
    public var events: [Event]
}

public struct BridgeEvent: Codable, Equatable, Sendable, Identifiable {
    public var ts: String
    public var event: String
    public var state: String?
    public var charge: Double?
    public var reason: String?

    public var id: String { ts + event }
}

public struct ConfigResponse: Codable, Equatable, Sendable {
    public var config: [String: ConfigValue]
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
}

public enum JSONCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
