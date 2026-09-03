// DevicePlugins.swift — the app's side of the device-plugin contract.
//
// A "device plugin" is a piece of hardware the bridge protects: the UDR7 is the
// first one. Each plugin brings its own name (given by the user), its own icon,
// its own settings sheet and its own event vocabulary. Everything here is PURE
// (no SwiftUI, no I/O) so it can be tested without a window; the UI half lives
// in RiverBridgeApp/Plugins.
//
// Molde: the Stats app for macOS — a module declares name, icon, enabled flag and
// its own settings view, and a STATIC registry lists them. No disk discovery, no
// schema: with one plugin that would be structure without a consumer.
//
// House rule: only members with a runtime consumer. `fieldKeys` is declarative
// data: the list of each type's fields, consumed by the test that compares it
// with the daemon's catalogue (`GET /v1/device-types`).
import Foundation

// MARK: - Health, as the daemon publishes it

/// One entry of `health.plugins` (daemon P6). `udr7`/`udr7_detail` stay as an
/// alias of the first plugin, so the installer's `sed` keeps working.
/// Not `Identifiable`: nobody iterates `chain.plugins` — the UI list iterates the
/// INSTANCES from `GET /v1/devices`; the health only reinforces name and state.
public struct HealthPlugin: Codable, Equatable, Sendable {
    public var id: String?
    /// The device TYPE of this instance (2026-09-03); nil on older daemons.
    public var type: String?
    public var name: String?
    public var state: String?
    public var detail: DeviceDetail?

    public init(id: String? = nil, type: String? = nil, name: String? = nil, state: String? = nil, detail: DeviceDetail? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.state = state
        self.detail = detail
    }
}

extension HealthChain {
    /// The id of the instance migrated from the flat `.env` (the daemon's
    /// LEGACY_INSTANCE_ID): the only one the `udr7`/`udr7_detail` alias mirrors.
    public static let legacyInstanceID = "udr7"

    /// The user's name for a plugin, or nil when the daemon doesn't publish one.
    /// Reads the `plugins` list first and falls back to the `udr7_detail` alias,
    /// so a daemon from before P6 still yields a name. Blank (or spaces only)
    /// counts as absent — the caller decides the default.
    public func pluginName(id: String) -> String? {
        let fromList = plugins?.first(where: { $0.id == id })?.name
        let fromAlias = id == HealthChain.legacyInstanceID ? udr7Detail?.name : nil
        for candidate in [fromList, fromAlias] {
            if let value = candidate?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// The plugin's detail object. The state is `pluginDetail(id:)?.state` — a
    /// separate `pluginState` would have no consumer.
    public func pluginDetail(id: String) -> Udr7Detail? {
        if let fromList = plugins?.first(where: { $0.id == id })?.detail { return fromList }
        return id == HealthChain.legacyInstanceID ? udr7Detail : nil
    }
}

// MARK: - Event vocabulary

/// Colour FAMILY of an event. Core must not import SwiftUI, so the tone is an
/// enum here and becomes a `Color` in the App layer (Theme.swift).
public enum DeviceEventTone: String, Equatable, Sendable {
    case family, danger, warning, toggle, wake
}

/// One event type of a plugin: how to draw it and how to name it, in both
/// languages. `L10n.t` is NEVER called here — it would freeze the language at
/// static-init time; the label functions run at render time.
public struct DeviceEventKind: Equatable, Sendable {
    public let type: String
    public let symbol: String
    public let tone: DeviceEventTone
    public let shortPT: String
    public let shortEN: String
    public let longPT: String
    public let longEN: String

    public init(type: String, symbol: String, tone: DeviceEventTone,
                shortPT: String, shortEN: String, longPT: String, longEN: String) {
        self.type = type
        self.symbol = symbol
        self.tone = tone
        self.shortPT = shortPT
        self.shortEN = shortEN
        self.longPT = longPT
        self.longEN = longEN
    }

    /// Chart legend. The colour scale's DOMAIN is this string, so it has to be
    /// unique per type — with any name the user picks.
    public func short(name: String) -> String {
        "\(name) \(L10n.t(shortPT, shortEN))"
    }

    /// Timeline row.
    public func long(name: String) -> String {
        "\(name) — \(L10n.t(longPT, longEN))"
    }
}

// MARK: - The SSH engine's event vocabulary

extension DeviceEventKind {
    /// The ten events of the daemon's SSH engine, in the UDR7 prefix. Every
    /// type built on the engine reuses this list and renames the prefix.
    public static let sshEngine: [DeviceEventKind] = [
            DeviceEventKind(type: "UDR7_SHUTDOWN_DRYRUN", symbol: "shield.lefthalf.filled",
                            tone: .family, shortPT: "ensaio", shortEN: "rehearsal",
                            longPT: "ensaio: desligaria agora", longEN: "rehearsal: would shut down now"),
            DeviceEventKind(type: "UDR7_SHUTDOWN_SENT", symbol: "power.circle.fill",
                            tone: .danger, shortPT: "enviado", shortEN: "sent",
                            longPT: "desligamento enviado", longEN: "shutdown sent"),
            DeviceEventKind(type: "UDR7_SHUTDOWN_FAILED", symbol: "exclamationmark.shield.fill",
                            tone: .danger, shortPT: "falhou", shortEN: "failed",
                            longPT: "desligamento falhou", longEN: "shutdown failed"),
            DeviceEventKind(type: "UDR7_SHUTDOWN_BLOCKED", symbol: "hand.raised.fill",
                            tone: .warning, shortPT: "bloqueado", shortEN: "blocked",
                            longPT: "desligamento bloqueado por cerca", longEN: "shutdown blocked by a fence"),
            DeviceEventKind(type: "UDR7_PROTECTION_REARMED", symbol: "shield.lefthalf.filled",
                            tone: .family, shortPT: "rearmado", shortEN: "re-armed",
                            longPT: "proteção rearmada (energia voltou)", longEN: "protection re-armed (power back)"),
            DeviceEventKind(type: "UDR7_PROTECTION_BLIND", symbol: "eye.slash.fill",
                            tone: .warning, shortPT: "às cegas", shortEN: "blind",
                            longPT: "sem telemetria durante a queda", longEN: "no telemetry during the outage"),
            DeviceEventKind(type: "UDR7_ARMED", symbol: "shield.lefthalf.filled",
                            tone: .toggle, shortPT: "armado", shortEN: "armed",
                            longPT: "proteção armada", longEN: "protection armed"),
            DeviceEventKind(type: "UDR7_DISARMED", symbol: "shield.lefthalf.filled",
                            tone: .toggle, shortPT: "desarmado", shortEN: "disarmed",
                            longPT: "proteção desarmada", longEN: "protection disarmed"),
            DeviceEventKind(type: "UDR7_WOL_SENT", symbol: "wake",
                            tone: .wake, shortPT: "WoL", shortEN: "WoL",
                            longPT: "pacote de religamento enviado", longEN: "wake packet sent"),
            DeviceEventKind(type: "UDR7_WOL_DRYRUN", symbol: "wake",
                            tone: .wake, shortPT: "WoL ensaio", shortEN: "WoL rehearsal",
                            longPT: "ensaio: religaria agora", longEN: "rehearsal: would wake now"),
    ]
}

// MARK: - The names the user gave

/// Resolved names, by plugin id. Pure value: the store rebuilds it whenever the
/// health changes, and the views just read it.
public struct DeviceNames: Equatable, Sendable {
    public var byPluginID: [String: String]

    public init(byPluginID: [String: String] = [:]) {
        self.byPluginID = byPluginID
    }

    /// `--seam-nome-plugin "udr7=Meu UDR"` (repeatable). Launch only — it exists
    /// so a screenshot can show a non-default name without a daemon.
    public static func parseSeams(_ args: [String]) -> [String: String] {
        var seams: [String: String] = [:]
        var index = 0
        while index + 1 < args.count {
            if args[index] == "--seam-nome-plugin" {
                let pair = args[index + 1]
                if let split = pair.firstIndex(of: "=") {
                    let id = String(pair[pair.startIndex..<split])
                    let name = String(pair[pair.index(after: split)...])
                    if !id.isEmpty && !name.isEmpty { seams[id] = name }
                }
                index += 2
                continue
            }
            index += 1
        }
        return seams
    }
}

// MARK: - Saving the sheet

/// Pure helpers for the settings sheet (P8), here so they can be tested without
/// a window.
public enum ProtectionSave {
    /// The name travels in its OWN PUT, before the rest: it is accepted while the
    /// protection is armed, and the rest may be refused with 409. Splitting means
    /// a rename is never lost because a threshold was refused.
    public static func split(changes: [String: String], nameKey: String)
        -> (name: String?, rest: [String: String]) {
        var rest = changes
        let name = rest.removeValue(forKey: nameKey)
        return (name, rest)
    }

    /// Feedback when the first PUT lands and the second is refused. It NAMES the
    /// refused keys — "algumas chaves foram recusadas" would leave the person
    /// hunting. There is no "name refused" branch: a refused name is a plain
    /// failure, and a skipped name with a refused rest is a plain refusal.
    public static func partialFeedback(refused: [String], motivo: String) -> String {
        let keys = refused.sorted().joined(separator: ", ")
        return L10n.t("nome salvo; recusadas: \(keys) — \(motivo)",
                      "name saved; refused: \(keys) — \(motivo)")
    }
}

// MARK: - Tipos × instâncias (2026-09-03)

/// A device TYPE, as the app knows it: icon, human labels, the fields its
/// hand-written sheet may edit (checked against the daemon's catalog by a test),
/// and its event vocabulary. An INSTANCE is a `DeviceInstance` from the daemon.
public struct DeviceTypeDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbol: String
    public let defaultName: String
    public let labelPT: String
    public let labelEN: String
    public let blurbPT: String
    public let blurbEN: String
    /// The type's instance fields (daemon field names), as the catalogue lists
    /// them; a sheet may leave one alone (`retry_max` today), never invent one.
    public let fieldKeys: [String]
    public let events: [DeviceEventKind]

    public init(id: String, symbol: String, defaultName: String, labelPT: String, labelEN: String,
                blurbPT: String, blurbEN: String, fieldKeys: [String], events: [DeviceEventKind]) {
        self.id = id
        self.symbol = symbol
        self.defaultName = defaultName
        self.labelPT = labelPT
        self.labelEN = labelEN
        self.blurbPT = blurbPT
        self.blurbEN = blurbEN
        self.fieldKeys = fieldKeys
        self.events = events
    }

    public var label: String { L10n.t(labelPT, labelEN) }
    public var blurb: String { L10n.t(blurbPT, blurbEN) }
}

extension DeviceEventKind {
    /// The same vocabulary with another type's prefix (the daemon's SSH engine
    /// speaks UDR7_* and each type renames the prefix).
    fileprivate func renamed(from oldPrefix: String, to newPrefix: String) -> DeviceEventKind {
        DeviceEventKind(type: newPrefix + type.dropFirst(oldPrefix.count), symbol: symbol, tone: tone,
                        shortPT: shortPT, shortEN: shortEN, longPT: longPT, longEN: longEN)
    }
}

extension DeviceTypeDescriptor {
    static let sshFieldKeys = [
        "ssh_host", "ssh_port", "ssh_user", "ssh_key", "shutdown_percent",
        "discharge_seconds_per_pct", "runtime_minutes", "min_outage_seconds", "confirm_seconds", "retry_max",
    ]

    public static let udr7 = DeviceTypeDescriptor(
        id: "udr7_ssh",
        symbol: "shield.lefthalf.filled",
        defaultName: "UDR7",
        labelPT: "Console UniFi (UDR7)", labelEN: "UniFi console (UDR7)",
        blurbPT: "Desliga o console pela chave SSH antes de a bateria acabar.",
        blurbEN: "Shuts the console down over SSH before the battery runs out.",
        fieldKeys: sshFieldKeys + ["wol_mac"],
        events: DeviceEventKind.sshEngine
    )

    public static let sshHost = DeviceTypeDescriptor(
        id: "ssh_host",
        symbol: "desktopcomputer",
        defaultName: "Servidor SSH",
        labelPT: "Computador ou servidor via SSH", labelEN: "Computer or server over SSH",
        blurbPT: "Roda um comando de desligamento por SSH em qualquer máquina.",
        blurbEN: "Runs a shutdown command over SSH on any machine.",
        fieldKeys: sshFieldKeys + ["shutdown_command"],
        // The engine's vocabulary without WoL (the type has no wake MAC).
        events: DeviceEventKind.sshEngine
            .filter { !$0.type.contains("WOL") }
            .map { $0.renamed(from: "UDR7_", to: "SSH_HOST_") }
    )
}

public enum DeviceTypeRegistry {
    /// Static, in code. A third type is one entry here plus its sheet.
    public static let all: [DeviceTypeDescriptor] = [.udr7, .sshHost]

    public static func type(id: String) -> DeviceTypeDescriptor? {
        all.first { $0.id == id }
    }

    public static func type(forEventType type: String) -> DeviceTypeDescriptor? {
        all.first { $0.events.contains { $0.type == type } }
    }

    public static func eventKind(_ type: String) -> DeviceEventKind? {
        for descriptor in all {
            if let kind = descriptor.events.first(where: { $0.type == type }) { return kind }
        }
        return nil
    }

    public static var allEventTypes: [String] {
        all.flatMap { $0.events.map(\.type) }
    }

    /// Turning the protection ON while the rehearsal is OFF arms the device for
    /// real, so it needs a confirmation. UNKNOWN also asks: `nil` must never open
    /// the hole. Turning it off is a pure disarm — always accepted, no dialog.
    public static func toggleNeedsConfirmation(on: Bool, dryRun: Bool?) -> Bool {
        on && dryRun != true
    }
}

/// The sheet's geometry, as pure arithmetic: the host window can shrink to
/// 414×480 (RiverBridgeApp), and every device sheet has to fit inside it with
/// 20 pt of slack on each side. The sheets AND the test read these numbers.
public enum DeviceSheetMetrics {
    public static let minWidth: CGFloat = 340
    public static let minHeight: CGFloat = 380
    public static let maxWidth: CGFloat = 600
    public static let maxHeight: CGFloat = 640
    /// Below this width, label and field stack (same cut as the filter bar).
    public static let narrowBelow: CGFloat = 420
    public static let margin: CGFloat = 40

    public static func size(host: CGSize) -> CGSize {
        CGSize(width: max(minWidth, min(maxWidth, host.width - margin)),
               height: max(minHeight, min(maxHeight, host.height - margin)))
    }

    public static func isNarrow(width: CGFloat) -> Bool { width < narrowBelow }
}

/// Whether the daemon we talk to manages device instances.
public enum DeviceAPISupport: Equatable, Sendable {
    case unknown
    case supported
    /// The reason, for the settings screen ("serviço 0.2.0", "404", …).
    case unsupported(String)

    /// Pure: what a failed `GET /v1/devices` means. 404 = a daemon that predates
    /// instances (0.2.0); anything else is a transient failure, not a verdict.
    public static func verdict(for error: Error, version: String?) -> DeviceAPISupport {
        if case APIError.badStatus(404, _) = error {
            return .unsupported(version.map { L10n.t("serviço \($0)", "service \($0)") }
                                ?? L10n.t("serviço antigo", "old service"))
        }
        return .unknown
    }
}

extension DeviceNames {
    /// Names by INSTANCE id: `/v1/devices` is the configuration, the health is
    /// a reinforcement (it carries `name` too), the seam wins over both.
    public static func resolve(devices: [DeviceInstance], health: HealthChain?,
                               seams: [String: String] = [:]) -> DeviceNames {
        var names: [String: String] = [:]
        for entry in health?.plugins ?? [] {
            if let id = entry.id, let name = entry.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                names[id] = name
            }
        }
        for device in devices {
            let name = device.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { names[device.id] = name }
        }
        for (id, seam) in seams where !seam.isEmpty { names[id] = seam }
        return DeviceNames(byPluginID: names)
    }

    public func name(forDevice id: String, type: DeviceTypeDescriptor? = nil) -> String {
        byPluginID[id] ?? type?.defaultName ?? id
    }

    /// The owner of an event row. A known instance id wins; without one, a
    /// single instance of the event's type is unambiguous; otherwise the type's
    /// default name — never a guess between two devices.
    public func name(forEvent type: String, device: String?, devices: [DeviceInstance]) -> String {
        guard let kind = DeviceTypeRegistry.type(forEventType: type) else { return "" }
        // An owner that is no longer listed (a removed instance) keeps the type's
        // name — never another instance's (revisão fria, 2026-09-03).
        if let device { return byPluginID[device] ?? kind.defaultName }
        let ofType = devices.filter { $0.type == kind.id }
        if ofType.count == 1 { return name(forDevice: ofType[0].id, type: kind) }
        return kind.defaultName
    }

    /// B14: two instances with the same name would collapse in the chart's
    /// colour domain and in the chips. When names collide, EVERY one of them
    /// gets an ordinal (nobody is "the one without a number").
    public static func uniqueLabels(instances: [DeviceInstance]) -> [String: String] {
        var counts: [String: Int] = [:]
        for instance in instances { counts[instance.name.trimmingCharacters(in: .whitespaces), default: 0] += 1 }
        var seen: [String: Int] = [:]
        var out: [String: String] = [:]
        for instance in instances {
            let base = instance.name.trimmingCharacters(in: .whitespaces)
            if counts[base, default: 0] > 1 {
                seen[base, default: 0] += 1
                out[instance.id] = "\(base) \(seen[base]!)"
            } else {
                out[instance.id] = base
            }
        }
        return out
    }

    /// "Servidor SSH", then "Servidor SSH 2", "Servidor SSH 3"… — unique among
    /// the existing names (casefold), so the form never opens with a collision.
    public static func suggestedName(type: DeviceTypeDescriptor, existing: [DeviceInstance]) -> String {
        let taken = Set(existing.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        if !taken.contains(type.defaultName.lowercased()) { return type.defaultName }
        var n = 2
        while taken.contains("\(type.defaultName) \(n)".lowercased()) { n += 1 }
        return "\(type.defaultName) \(n)"
    }
}

/// A filter chip of the timeline, as pure data: four bridge subjects plus one
/// chip per device instance (B13). Colours are App-side.
public struct EventChipSpec: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case queda, restaurada, bateria, comunicacao
        case device(id: String, type: String)
    }

    public let kind: Kind
    public let symbol: String
    public let types: [String]
    /// The instance's (unique) label for device chips; nil for bridge chips.
    public let name: String?

    public var id: String {
        switch kind {
        case .queda: "queda"
        case .restaurada: "restaurada"
        case .bateria: "bateria"
        case .comunicacao: "comunicacao"
        case .device(let id, _): "device:\(id)"
        }
    }

    public var deviceID: String? {
        if case .device(let id, _) = kind { return id }
        return nil
    }

    /// Whether an event belongs under this chip. A device chip claims the
    /// events that carry its id; an event WITHOUT an owner (recorded before
    /// instances existed) belongs to the only instance of its type, and to
    /// nobody when there are two — the same rule as `DeviceNames.name(forEvent:)`.
    public func matches(eventType: String, device: String?, devices: [DeviceInstance]) -> Bool {
        guard types.contains(eventType) else { return false }
        guard let mine = deviceID else { return true }
        if let device { return device == mine }
        guard let kind = DeviceTypeRegistry.type(forEventType: eventType) else { return false }
        let ofType = devices.filter { $0.type == kind.id }
        return ofType.count == 1 && ofType[0].id == mine
    }

    public static func all(devices: [DeviceInstance]) -> [EventChipSpec] {
        let labels = DeviceNames.uniqueLabels(instances: devices)
        let bridge: [EventChipSpec] = [
            .init(kind: .queda, symbol: "bolt.slash.fill", types: ["POWER_LOSS"], name: nil),
            .init(kind: .restaurada, symbol: "bolt.badge.checkmark.fill", types: ["POWER_RESTORED"], name: nil),
            .init(kind: .bateria, symbol: "battery.25percent", types: ["LOW_BATTERY"], name: nil),
            .init(kind: .comunicacao, symbol: "antenna.radiowaves.left.and.right",
                  types: ["COMM_LOST", "COMM_RESTORED"], name: nil),
        ]
        let perDevice = devices.map { device -> EventChipSpec in
            let type = DeviceTypeRegistry.type(id: device.type)
            return .init(kind: .device(id: device.id, type: device.type),
                         symbol: type?.symbol ?? "shield.lefthalf.filled",
                         types: type?.events.map(\.type) ?? [],
                         name: labels[device.id] ?? device.name)
        }
        return bridge + perDevice
    }
}
