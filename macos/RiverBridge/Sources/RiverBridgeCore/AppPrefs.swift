// App-side preferences (language, theme) — UI concerns, so they persist in
// UserDefaults, NOT in the daemon's .env (which only holds daemon config).

import Foundation
import Observation

@MainActor
@Observable
public final class AppPrefs {
    public static let shared = AppPrefs()

    public enum Language: String, CaseIterable, Identifiable, Sendable {
        case system, ptBR, enUS
        public var id: String { rawValue }
    }

    public enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
        case auto, light, dark
        public var id: String { rawValue }
    }

    public var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "rub.language") }
    }
    public var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "rub.theme") }
    }

    /// pt-BR is the product's home locale: "system" resolves to Portuguese
    /// unless the OS is set to English.
    public var isPT: Bool {
        switch language {
        case .ptBR: true
        case .enUS: false
        case .system: Locale.current.language.languageCode?.identifier != "en"
        }
    }

    private init() {
        language = Language(rawValue: UserDefaults.standard.string(forKey: "rub.language") ?? "") ?? .system
        themeMode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: "rub.theme") ?? "") ?? .auto
    }
}

/// Two-language lookup AT the call site: `L10n.t("Eventos", "Events")` —
/// both languages visible where they are used, no key indirection to rot.
/// Nonisolated on purpose (enum labels are nonisolated): reads the same
/// UserDefaults key AppPrefs writes; UserDefaults is thread-safe. Language
/// changes re-render via .id(language) at the window root.
public enum L10n {
    public static func t(_ pt: String, _ en: String) -> String {
        isPT ? pt : en
    }

    public static var isPT: Bool {
        switch UserDefaults.standard.string(forKey: "rub.language") {
        case AppPrefs.Language.ptBR.rawValue: true
        case AppPrefs.Language.enUS.rawValue: false
        default: Locale.current.language.languageCode?.identifier != "en"
        }
    }
}
