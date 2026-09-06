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
        short(name: name, emPortugues: L10n.cachedIsPT)
    }

    /// A mesma legenda com o idioma DADO: quem monta uma lista inteira lê o
    /// idioma uma vez e passa-o adiante, para todos os rótulos saírem no mesmo.
    public func short(name: String, emPortugues: Bool) -> String {
        "\(name) \(emPortugues ? shortPT : shortEN)"
    }

    /// Timeline row.
    public func long(name: String) -> String {
        "\(name) — \(L10n.t(longPT, longEN))"
    }

    /// Timeline row de um evento que NÃO é de dispositivo: sem nome de aparelho
    /// na frente, porque o dono do evento é o próprio serviço.
    public func long() -> String { L10n.t(longPT, longEN) }
}

// MARK: - O vocabulário de eventos do SERVIÇO

extension DeviceEventKind {
    /// Os eventos que o serviço emite por conta própria — energia, o River como
    /// aparelho, o cabo indo e voltando.
    ///
    /// Esta lista existe porque a tela **não pode** ter um caminho que mostre o
    /// nome cru. Antes dela, `EventsTimeline` tinha um `switch` que terminava em
    /// "devolve o nome" — e oito dos quinze eventos do serviço apareciam assim,
    /// em maiúsculas com sublinhados, na linha do tempo (medido em 2026-09-05).
    ///
    /// A lista é conferida contra `tests/fixtures/eventos.json`, que o serviço
    /// gera do vocabulário dele: nome novo lá sem frase aqui reprova o teste.
    public static let doServico: [DeviceEventKind] = [
        DeviceEventKind(type: "POWER_LOSS", symbol: "bolt.slash.fill",
                        tone: .warning, shortPT: "queda", shortEN: "loss",
                        longPT: "Queda de energia — na bateria",
                        longEN: "Power loss — on battery"),
        DeviceEventKind(type: "POWER_RESTORED", symbol: "bolt.badge.checkmark.fill",
                        tone: .family, shortPT: "voltou", shortEN: "restored",
                        longPT: "Energia restaurada", longEN: "Power restored"),
        DeviceEventKind(type: "LOW_BATTERY", symbol: "battery.25percent",
                        tone: .warning, shortPT: "bateria baixa", shortEN: "low battery",
                        longPT: "Bateria baixa", longEN: "Low battery"),
        DeviceEventKind(type: "COMM_LOST", symbol: "antenna.radiowaves.left.and.right.slash",
                        tone: .danger, shortPT: "sem sinal", shortEN: "no signal",
                        longPT: "Comunicação perdida com o RIVER",
                        longEN: "Communication with the RIVER lost"),
        DeviceEventKind(type: "COMM_RESTORED", symbol: "antenna.radiowaves.left.and.right",
                        tone: .family, shortPT: "sinal de volta", shortEN: "signal back",
                        longPT: "Comunicação restabelecida", longEN: "Communication restored"),
        // O River como aparelho
        DeviceEventKind(type: "RIVER_DESLIGANDO", symbol: "power.circle.fill",
                        tone: .danger, shortPT: "desligando", shortEN: "powering off",
                        longPT: "Desligando o River — ordem recebida",
                        longEN: "Powering the River off — order received"),
        DeviceEventKind(type: "RIVER_POWEROFF_SENT", symbol: "power.circle.fill",
                        tone: .danger, shortPT: "desligado", shortEN: "powered off",
                        longPT: "Ordem de desligar o River enviada",
                        longEN: "River power-off order sent"),
        DeviceEventKind(type: "RIVER_DESLIGAR_FALHOU", symbol: "exclamationmark.triangle.fill",
                        tone: .danger, shortPT: "falhou", shortEN: "failed",
                        longPT: "Não consegui desligar o River",
                        longEN: "Could not power the River off"),
        DeviceEventKind(type: "RIVER_DESLIGAR_RECUSADO", symbol: "hand.raised.fill",
                        tone: .warning, shortPT: "recusado", shortEN: "refused",
                        longPT: "Desligar o River foi recusado por uma trava",
                        longEN: "Powering the River off was refused by a lock"),
        DeviceEventKind(type: "RIVER_KILLPOWER_FLAG_ABERTA", symbol: "lock.open.trianglebadge.exclamationmark.fill",
                        tone: .danger, shortPT: "trava aberta", shortEN: "lock open",
                        longPT: "A trava de desligamento do leitor ficou aberta — reinicie o serviço",
                        longEN: "The reader's power-off lock stayed open — restart the service"),
        // O cabo indo e voltando sozinho
        DeviceEventKind(type: "CABO_LARGADO_AUTOMATICO", symbol: "cable.connector.horizontal",
                        tone: .toggle, shortPT: "cabo emprestado", shortEN: "cable lent",
                        longPT: "Cabo passado para o aplicativo da EcoFlow",
                        longEN: "Cable handed over to the EcoFlow app"),
        DeviceEventKind(type: "CABO_RETOMADO_AUTOMATICO", symbol: "cable.connector",
                        tone: .family, shortPT: "cabo de volta", shortEN: "cable back",
                        longPT: "Cabo de volta com o serviço",
                        longEN: "Cable back with the service"),
        DeviceEventKind(type: "CABO_MANTIDO_PROTECAO_ARMADA", symbol: "shield.lefthalf.filled",
                        tone: .warning, shortPT: "cabo mantido", shortEN: "cable kept",
                        longPT: "Cabo mantido: há proteção armada",
                        longEN: "Cable kept: a protection is armed"),
        // O pacote foi para o Lixo (0.8.0): o serviço se retirou sozinho
        DeviceEventKind(type: "PACOTE_NO_LIXO_REMOVIDO", symbol: "trash.fill",
                        tone: .warning, shortPT: "removido", shortEN: "removed",
                        longPT: "O programa foi para o Lixo: o serviço se removeu por completo",
                        longEN: "The app went to the Trash: the service removed itself completely"),
    ]
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
            // As ordens que o DONO dá à mão — pela tela ou pelo Home Assistant
            // (0.7.0). São diferentes do que a proteção faz sozinha numa queda:
            // aqui alguém apertou agora.
            DeviceEventKind(type: "UDR7_ORDEM_ENVIADA", symbol: "hand.tap.fill",
                            tone: .danger, shortPT: "ordem", shortEN: "order",
                            longPT: "ordem enviada à mão", longEN: "order sent by hand"),
            DeviceEventKind(type: "UDR7_ORDEM_FALHOU", symbol: "exclamationmark.triangle.fill",
                            tone: .danger, shortPT: "ordem falhou", shortEN: "order failed",
                            longPT: "a ordem dada à mão não chegou",
                            longEN: "the order sent by hand did not arrive"),
            DeviceEventKind(type: "UDR7_ORDEM_RECUSADA", symbol: "hand.raised.fill",
                            tone: .warning, shortPT: "ordem recusada", shortEN: "order refused",
                            longPT: "ordem recusada por uma trava do serviço",
                            longEN: "order refused by a service lock"),
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
    /// The suggested name for a new instance, in the app's language ("SSH
    /// server" in English, "Servidor SSH" in Portuguese — the owner saw the
    /// Portuguese one on an English screen, 2026-09-03). UDR7 is the same in both.
    public let defaultNamePT: String
    public let defaultNameEN: String
    public var defaultName: String { defaultName(emPortugues: L10n.cachedIsPT) }
    public func defaultName(emPortugues: Bool) -> String { emPortugues ? defaultNamePT : defaultNameEN }
    public let labelPT: String
    public let labelEN: String
    public let blurbPT: String
    public let blurbEN: String
    /// The type's instance fields (daemon field names), as the catalogue lists
    /// them; a sheet may leave one alone (`retry_max` today), never invent one.
    public let fieldKeys: [String]
    public let events: [DeviceEventKind]

    public init(id: String, symbol: String, defaultNamePT: String, defaultNameEN: String, labelPT: String, labelEN: String,
                blurbPT: String, blurbEN: String, fieldKeys: [String], events: [DeviceEventKind]) {
        self.id = id
        self.symbol = symbol
        self.defaultNamePT = defaultNamePT
        self.defaultNameEN = defaultNameEN
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
        defaultNamePT: "UDR7", defaultNameEN: "UDR7",
        labelPT: "Console UniFi (UDR7)", labelEN: "UniFi console (UDR7)",
        blurbPT: "Desliga o console pela chave SSH antes de a bateria acabar.",
        blurbEN: "Shuts the console down over SSH before the battery runs out.",
        fieldKeys: sshFieldKeys + ["wol_mac"],
        events: DeviceEventKind.sshEngine
    )

    public static let sshHost = DeviceTypeDescriptor(
        id: "ssh_host",
        symbol: "desktopcomputer",
        defaultNamePT: "Servidor SSH", defaultNameEN: "SSH server",
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

    /// O evento, seja ele de dispositivo ou do próprio serviço.
    ///
    /// Um só ponto de entrada de propósito: com dois, a tela consultava um e
    /// caía no "devolve o nome cru" para os do outro.
    public static func qualquerEvento(_ type: String) -> DeviceEventKind? {
        eventKind(type) ?? DeviceEventKind.doServico.first { $0.type == type }
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
    /// Below this CONTAINER width (the sheet as actually drawn, or the settings
    /// pane), label and control stack. The sheet MEASURES its own width and
    /// compares it with this number; the arithmetic in `size(host:)` is only the
    /// first guess. The number is set by CAPTURE, not by adding up text widths
    /// (2026-09-03, Portuguese): at 420 (the old cut) the side-by-side key row
    /// wrapped "Chave privada (caminho absoluto)" in two lines; at a 465-pt sheet
    /// drawn wide the group headers were clipped; at a 560-pt sheet every
    /// side-by-side row of both device sheets — key path, "Comando de
    /// desligamento" with its caption and the monospaced command popup — fits on
    /// one line, and at 600 as well.
    public static let narrowBelow: CGFloat = 560
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

    public func name(forDevice id: String, type: DeviceTypeDescriptor? = nil,
                     emPortugues: Bool = L10n.cachedIsPT) -> String {
        byPluginID[id] ?? type?.defaultName(emPortugues: emPortugues) ?? id
    }

    /// The owner of an event row. A known instance id wins; without one, a
    /// single instance of the event's type is unambiguous; otherwise the type's
    /// default name — never a guess between two devices. `emPortugues`: the
    /// language of that default name, so a caller building a whole list reads
    /// the (global) language once and every name comes out in the same one.
    public func name(forEvent type: String, device: String?, devices: [DeviceInstance],
                     emPortugues: Bool = L10n.cachedIsPT) -> String {
        guard let kind = DeviceTypeRegistry.type(forEventType: type) else { return "" }
        // An owner that is no longer listed (a removed instance) keeps the type's
        // name — never another instance's (revisão fria, 2026-09-03).
        if let device { return byPluginID[device] ?? kind.defaultName(emPortugues: emPortugues) }
        let ofType = devices.filter { $0.type == kind.id }
        if ofType.count == 1 { return name(forDevice: ofType[0].id, type: kind, emPortugues: emPortugues) }
        return kind.defaultName(emPortugues: emPortugues)
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
