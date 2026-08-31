// Where the daemon lives and how to authenticate to it (§7A.3).
// Mirrors the daemon's conventions: state dir overridable via RUB_STATE_DIR
// (hermetic tests), port via RUB_API_PORT (default 35493).

import Foundation

public struct ApiEndpoint: Sendable {
    public var baseURL: URL
    public var token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    public static func stateDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["RUB_STATE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/river-unifi-bridge")
    }

    public static func port(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        if let raw = environment["RUB_API_PORT"], let value = Int(raw) { return value }
        return 35493
    }

    /// Reads the daemon's token file. nil = daemon never ran (UI shows
    /// "serviço parado", never a fabricated connection).
    public static func readToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let path = stateDir(environment: environment).appendingPathComponent("ui-api.token")
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    public static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> ApiEndpoint? {
        guard let token = readToken(environment: environment) else { return nil }
        let url = URL(string: "http://127.0.0.1:\(port(environment: environment))")!
        return ApiEndpoint(baseURL: url, token: token)
    }
}
