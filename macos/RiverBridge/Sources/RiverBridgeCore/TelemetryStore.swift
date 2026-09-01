// Single source of truth for the UI. Consumes the SSE stream with
// reconnection/backoff; formats values honestly ("—" for absent data).

import Foundation
import Observation

public enum ConnectionPhase: Equatable, Sendable {
    case connecting
    case live
    case serviceDown(String)
}

@MainActor
@Observable
public final class TelemetryStore {
    public private(set) var latest: UpsState?
    public private(set) var events: [BridgeEvent] = []
    public private(set) var phase: ConnectionPhase = .connecting
    /// Increments on every applied state reading — the UI's data heartbeat.
    public private(set) var beat: Int = 0

    private var task: Task<Void, Never>?

    public init() {}

    // MARK: - Stream lifecycle

    public func start(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard task == nil else { return }
        task = Task { [weak self] in
            var backoff: Double = 0.5
            while !Task.isCancelled {
                guard let endpoint = ApiEndpoint.discover(environment: environment) else {
                    self?.phase = .serviceDown("Serviço não instalado ou nunca iniciado")
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                do {
                    let client = SSEClient(endpoint: endpoint)
                    for try await message in client.messages() {
                        backoff = 0.5
                        self?.phase = .live
                        self?.apply(message)
                    }
                } catch {
                    self?.phase = .serviceDown("Sem comunicação com o serviço")
                }
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 10)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func apply(_ message: SSEMessage) {
        let decoder = JSONCoding.decoder()
        let data = Data(message.data.utf8)
        switch message.event {
        case "state":
            if let state = try? decoder.decode(UpsState.self, from: data) {
                latest = state
                beat &+= 1
            }
        case "event":
            if let event = try? decoder.decode(BridgeEvent.self, from: data) {
                events.insert(event, at: 0)
                if events.count > 100 { events.removeLast() }
            }
        default:
            break
        }
    }

    // MARK: - Derived, honest display values (pt-BR; "—" = not observed)

    public var stateLabel: String {
        guard phase == .live, let state = latest?.power?.state else { return "—" }
        switch state {
        case "ONLINE": return L10n.t("Na tomada", "On grid")
        case "ON_BATTERY": return L10n.t("Na bateria", "On battery")
        case "OUTPUT_OFF": return L10n.t("Saída desligada", "Output off")
        default: return L10n.t("Sem leitura", "No reading")
        }
    }

    public var isOnBattery: Bool { latest?.power?.state == "ON_BATTERY" }
    public var isCharging: Bool { latest?.power?.states?.contains("CHARGING") == true }
    public var isLowBattery: Bool { latest?.health?.lowBattery == true }

    public var chargeFraction: Double? {
        guard let charge = latest?.battery?.chargePercent else { return nil }
        return min(max(charge / 100.0, 0), 1)
    }

    public var chargeText: String {
        Self.percentText(latest?.battery?.chargePercent)
    }

    public var runtimeText: String {
        Self.runtimeText(latest?.battery?.runtimeSeconds)
    }

    public var loadText: String {
        Self.percentText(latest?.power?.loadPercent)
    }

    public var powerText: String {
        Self.wattsText(latest?.power?.outputPowerW)
    }

    public var outputVoltageText: String {
        Self.voltageText(latest?.power?.outputVoltageV)
    }

    // MARK: - Pure formatters (unit-tested)

    nonisolated public static func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    nonisolated public static func wattsText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) W"
    }

    nonisolated public static func voltageText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f V", value)
    }

    /// 9240 s -> "2 h 34 min"; 540 s -> "9 min"; nil -> "—".
    nonisolated public static func runtimeText(_ seconds: Double?) -> String {
        guard let seconds, seconds >= 0 else { return "—" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(total) s"
    }
}
