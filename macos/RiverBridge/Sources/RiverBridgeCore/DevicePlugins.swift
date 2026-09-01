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
// House rule: only members with a runtime consumer. `sheetKeys` is declarative
// data, and it is consumed by the sheet that builds the PUT body (P8) and by the
// test that compares it with the daemon's own list.
import Foundation

// MARK: - Health, as the daemon publishes it

/// One entry of `health.plugins` (daemon P6). `udr7`/`udr7_detail` stay as an
/// alias of the first plugin, so the installer's `sed` keeps working.
/// Not `Identifiable`: nobody iterates `chain.plugins` — the UI list iterates the
/// registry, which is the source of what CAN be shown.
public struct HealthPlugin: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String?
    public var state: String?
    public var detail: Udr7Detail?

    public init(id: String? = nil, name: String? = nil, state: String? = nil, detail: Udr7Detail? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.detail = detail
    }
}

extension HealthChain {
    /// The user's name for a plugin, or nil when the daemon doesn't publish one.
    /// Reads the `plugins` list first and falls back to the `udr7_detail` alias,
    /// so a daemon from before P6 still yields a name. Blank (or spaces only)
    /// counts as absent — the caller decides the default.
    public func pluginName(id: String) -> String? {
        let fromList = plugins?.first(where: { $0.id == id })?.name
        let fromAlias = id == DevicePluginDescriptor.udr7.id ? udr7Detail?.name : nil
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
        return id == DevicePluginDescriptor.udr7.id ? udr7Detail : nil
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

// MARK: - The plugin descriptor and the registry

public struct DevicePluginDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbol: String
    public let defaultName: String
    /// The key that turns the protection on and off.
    public let enableKey: String
    /// The key that holds the user's name for the device.
    public let nameKey: String
    /// The keys the settings SHEET edits. Deliberately a different name from the
    /// daemon's `config_keys` (17): the sheet does not edit `UDR7_ARM_ALLOWED`
    /// (file-only) nor `UDR7_RETRY_MAX`, and `PROTECT_DRY_RUN` travels on its own
    /// in the arming dialog. Consumed by the sheet that builds the PUT (P8).
    public let sheetKeys: [String]
    public let events: [DeviceEventKind]

    public init(id: String, symbol: String, defaultName: String, enableKey: String,
                nameKey: String, sheetKeys: [String], events: [DeviceEventKind]) {
        self.id = id
        self.symbol = symbol
        self.defaultName = defaultName
        self.enableKey = enableKey
        self.nameKey = nameKey
        self.sheetKeys = sheetKeys
        self.events = events
    }
}

extension DevicePluginDescriptor {
    public static let udr7 = DevicePluginDescriptor(
        id: "udr7",
        symbol: "shield.lefthalf.filled",
        defaultName: "UDR7",
        enableKey: "PROTECT_UDR7",
        nameKey: "UDR7_NAME",
        sheetKeys: [
            "UDR7_SSH_HOST", "UDR7_SSH_PORT", "UDR7_SSH_USER", "UDR7_SSH_KEY",
            "UDR7_EXPECTED_SERIAL", "UDR7_CUTOFF_PERCENT", "UDR7_SHUTDOWN_PERCENT",
            "UDR7_DISCHARGE_SECONDS_PER_PCT", "UDR7_RUNTIME_MINUTES",
            "UDR7_MIN_OUTAGE_SECONDS", "UDR7_CONFIRM_SECONDS", "UDR7_WOL_MAC",
        ],
        events: [
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
    )
}

public enum DevicePluginRegistry {
    /// Static, like Stats. A second plugin is one line here.
    public static let all: [DevicePluginDescriptor] = [.udr7]

    public static func plugin(id: String) -> DevicePluginDescriptor? {
        all.first { $0.id == id }
    }

    public static func plugin(forEventType type: String) -> DevicePluginDescriptor? {
        all.first { $0.events.contains { $0.type == type } }
    }

    public static func eventKind(_ type: String) -> DeviceEventKind? {
        for plugin in all {
            if let kind = plugin.events.first(where: { $0.type == type }) { return kind }
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

// MARK: - The names the user gave

/// Resolved names, by plugin id. Pure value: the store rebuilds it whenever the
/// health changes, and the views just read it.
public struct DeviceNames: Equatable, Sendable {
    public var byPluginID: [String: String]

    public init(byPluginID: [String: String] = [:]) {
        self.byPluginID = byPluginID
    }

    public func name(for descriptor: DevicePluginDescriptor) -> String {
        byPluginID[descriptor.id] ?? descriptor.defaultName
    }

    public func name(forEventType type: String) -> String {
        guard let plugin = DevicePluginRegistry.plugin(forEventType: type) else { return "" }
        return name(for: plugin)
    }

    /// seam > health > default. `health` is optional because the store resolves
    /// once at init, before any GET has happened.
    public static func resolve(
        health: HealthChain?,
        seams: [String: String] = [:],
        registry: [DevicePluginDescriptor] = DevicePluginRegistry.all
    ) -> DeviceNames {
        var names: [String: String] = [:]
        for plugin in registry {
            if let seam = seams[plugin.id], !seam.isEmpty {
                names[plugin.id] = seam
            } else if let published = health?.pluginName(id: plugin.id) {
                names[plugin.id] = published
            }
        }
        return DeviceNames(byPluginID: names)
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
