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
    /// The integration chain, polled here instead of by each view: the health is
    /// what carries the plugin list and the names the user gave, and two pollers
    /// would show two different truths on the same screen.
    public private(set) var health: HealthChain?
    /// Resolved device names. Configuration, not telemetry: it survives the
    /// service going down (the state disappears, the name stays).
    public private(set) var deviceNames: DeviceNames

    private var task: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private let client: APIClient?
    private let seams: [String: String]
    private var environment: [String: String]
    /// Generation counter, NOT single-flight: single-flight would swallow the
    /// refresh right after a PUT, which is the one that matters. An older GET
    /// finishing late never re-displays a stale name.
    private var healthGeneration = 0

    /// A single init, every parameter with a default: `TelemetryStore()` keeps
    /// working everywhere it is called. `environment` is injectable so a test can
    /// be hermetic — without it the test would find the real service on the
    /// developer's machine and pass or fail depending on who runs it.
    public init(arguments: [String] = ProcessInfo.processInfo.arguments,
                client: APIClient? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.client = client
        let seams = DeviceNames.parseSeams(arguments)
        self.seams = seams
        self.deviceNames = DeviceNames.resolve(health: nil, seams: seams)
        self.environment = environment
    }

    // MARK: - Health

    public func refreshHealth() async {
        healthGeneration += 1
        let mine = healthGeneration
        let api = client ?? ApiEndpoint.discover(environment: environment).map { APIClient(endpoint: $0) }
        guard let api else { return }
        let chain = try? await api.health()
        guard mine == healthGeneration else { return }
        health = chain
        // `if let`: with the service down the state disappears, but the name is
        // configuration and must stay. Without the guard it would snap back to
        // "UDR7" the moment a GET failed.
        if let chain { deviceNames = DeviceNames.resolve(health: chain, seams: seams) }
    }

    // MARK: - Stream lifecycle

    public func start(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard task == nil else { return }
        // Kept for refreshHealth: resolving the endpoint with a different
        // environment would lose the hermeticity that RUB_STATE_DIR gives tests.
        self.environment = environment
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshHealth()
                try? await Task.sleep(for: .seconds(5))
            }
        }
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
        healthTask?.cancel()
        healthTask = nil
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
