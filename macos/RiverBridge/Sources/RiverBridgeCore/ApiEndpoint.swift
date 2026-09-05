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

    /// A pasta do usuário — onde o serviço instalado pela linha de comando guarda
    /// o estado, porque ali ele roda como o próprio usuário.
    public static func userStateDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/river-unifi-bridge")
    }

    /// A pasta do sistema — onde o serviço instalado ARRASTANDO o app guarda o
    /// estado, porque ali ele roda como serviço de sistema. Estado de serviço de
    /// sistema não mora na pasta de um usuário.
    public static let systemStateDir = URL(fileURLWithPath: "/Library/Application Support/river-unifi-bridge")

    /// Onde procurar o estado. A ordem importa: a pasta do usuário primeiro.
    ///
    /// As duas formas de instalar convivem, e quem tem as duas quer falar com a
    /// que ele acabou de usar. Procurando só numa delas, o app dizia "serviço
    /// parado" com o serviço no ar — que é o pior desfecho possível para uma tela
    /// que existe para dizer se a energia está sendo vigiada.
    public static func stateDirs(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        if let override = environment["RUB_STATE_DIR"], !override.isEmpty {
            return [URL(fileURLWithPath: override)]
        }
        return [userStateDir(), systemStateDir]
    }

    public static func stateDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let candidatas = stateDirs(environment: environment)
        let fm = FileManager.default
        for pasta in candidatas
        where fm.isReadableFile(atPath: pasta.appendingPathComponent(tokenFilename).path) {
            return pasta
        }
        return candidatas[0]
    }

    public static let tokenFilename = "ui-api.token"

    public static func port(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        if let raw = environment["RUB_API_PORT"], let value = Int(raw) { return value }
        return 35493
    }

    /// Reads the daemon's token file. nil = daemon never ran (UI shows
    /// "serviço parado", never a fabricated connection).
    public static func readToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for pasta in stateDirs(environment: environment) {
            let path = pasta.appendingPathComponent(tokenFilename)
            guard let raw = try? String(contentsOf: path, encoding: .utf8) else { continue }
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        return nil
    }

    public static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) -> ApiEndpoint? {
        guard let token = readToken(environment: environment) else { return nil }
        let url = URL(string: "http://127.0.0.1:\(port(environment: environment))")!
        return ApiEndpoint(baseURL: url, token: token)
    }
}
