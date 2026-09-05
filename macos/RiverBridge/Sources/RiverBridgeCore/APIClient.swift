// Thin async client for the daemon's local API. Request/response only —
// the SSE stream lives in SSEClient.

import Foundation

public enum APIError: Error, Equatable {
    case badStatus(Int, String)
    case notConnected
}

public struct APIClient: Sendable {
    public var endpoint: ApiEndpoint
    private let session: URLSession

    public init(endpoint: ApiEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: endpoint.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.timeoutInterval = 5
        return req
    }

    private func run(_ req: URLRequest, accept: Set<Int> = [200]) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard accept.contains(status) else {
            throw APIError.badStatus(status, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    public func health() async throws -> HealthChain {
        try JSONCoding.decoder().decode(
            HealthChain.self, from: try await run(request("v1/health"))
        )
    }

    public func history(metric: String, bucketSeconds: Int, from: Int = 0) async throws -> HistoryResponse {
        var components = URLComponents(
            url: endpoint.baseURL.appendingPathComponent("v1/history"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "metric", value: metric),
            .init(name: "bucket", value: String(bucketSeconds)),
            .init(name: "from", value: String(from)),
        ]
        var req = request("v1/history")
        req.url = components.url
        return try JSONCoding.decoder().decode(HistoryResponse.self, from: try await run(req))
    }

    /// GET /v1/events/log — persisted log, newest first.
    public func eventsLog(from: Int? = nil, to: Int? = nil,
                          types: [String] = [], limit: Int = 200,
                          device: String? = nil) async throws -> [EventLogRow] {
        var components = URLComponents(
            url: endpoint.baseURL.appendingPathComponent("v1/events/log"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let from { items.append(.init(name: "from", value: String(from))) }
        if let to { items.append(.init(name: "to", value: String(to))) }
        if !types.isEmpty {
            items.append(.init(name: "types", value: types.joined(separator: ",")))
        }
        if let device { items.append(.init(name: "device", value: device)) }
        components.queryItems = items
        var req = request("v1/events/log")
        req.url = components.url
        return try JSONCoding.decoder()
            .decode(EventsLogResponse.self, from: try await run(req)).rows
    }

    /// DELETE /v1/events/log — `to` is mandatory by API contract (a
    /// parameterless DELETE never wipes the log). Returns rows removed.
    public func deleteEvents(from: Int = 0, to: Int) async throws -> Int {
        var components = URLComponents(
            url: endpoint.baseURL.appendingPathComponent("v1/events/log"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "from", value: String(from)),
            .init(name: "to", value: String(to)),
        ]
        var req = request("v1/events/log", method: "DELETE")
        req.url = components.url
        struct Reply: Codable { var removidos: Int }
        return try JSONCoding.decoder().decode(Reply.self, from: try await run(req)).removidos
    }

    public func config() async throws -> ConfigResponse {
        try JSONCoding.decoder().decode(
            ConfigResponse.self, from: try await run(request("v1/config"))
        )
    }

    public func version() async throws -> VersionResponse {
        try JSONCoding.decoder().decode(
            VersionResponse.self, from: try await run(request("v1/version"))
        )
    }

    /// PUT /v1/config — returns (hot-applied keys, restart_required).
    public func putConfig(_ changes: [String: String]) async throws -> (applied: [String], restartRequired: Bool) {
        let body = try JSONEncoder().encode(changes)
        let data = try await run(request("v1/config", method: "PUT", body: body))
        struct Reply: Codable {
            var aplicadasAQuente: [String]
            var restartRequired: Bool
        }
        let reply = try JSONCoding.decoder().decode(Reply.self, from: data)
        return (reply.aplicadasAQuente, reply.restartRequired)
    }

    /// 202 = restart scheduled by the daemon (§7A.3 contract).
    public func restartService() async throws {
        _ = try await run(request("v1/service/restart", method: "POST"), accept: [202])
    }

    /// Apaga o que o serviço criou nesta máquina — chave do console, senhas,
    /// histórico, dispositivos e o trecho dele na configuração do no-break.
    ///
    /// Quem apaga é o SERVIÇO, não o programa: instalado arrastando, ele roda
    /// como serviço de sistema e é dono dos arquivos; o programa roda como o
    /// dono e não conseguiria tocá-los. E é por isso que esta chamada vem ANTES
    /// de desregistrar — desregistrar mata o serviço e deixaria tudo no disco.
    @discardableResult
    public func apagarEstadoDoServico() async throws -> [String] {
        struct Resposta: Decodable { let apagados: [String] }
        let dados = try await run(request("v1/service/apagar-estado", method: "POST"))
        return (try? JSONCoding.decoder().decode(Resposta.self, from: dados).apagados) ?? []
    }

    // MARK: - Dispositivos por instância (2026-09-03)

    /// GET /v1/device-types — the daemon's catalog of types (404 on a 0.2.0 daemon).
    public func deviceTypes() async throws -> [DeviceTypeInfo] {
        try JSONCoding.decoder().decode(
            DeviceTypesResponse.self, from: try await run(request("v1/device-types"))
        ).types
    }

    /// GET /v1/devices — every instance, in the daemon's order.
    public func devices() async throws -> [DeviceInstance] {
        try JSONCoding.decoder().decode(
            DevicesResponse.self, from: try await run(request("v1/devices"))
        ).devices
    }

    /// POST /v1/devices — a new instance is born disabled and in rehearsal
    /// (the daemon refuses `enabled && !dry_run` at creation). 201 on success.
    public func createDevice(type: String, name: String, fields: [String: String]) async throws -> DeviceInstance {
        struct Body: Encodable { var type: String; var name: String; var fields: [String: String] }
        let body = try JSONEncoder().encode(Body(type: type, name: name, fields: fields))
        let data = try await run(request("v1/devices", method: "POST", body: body), accept: [201])
        return try JSONCoding.decoder().decode(DeviceResponse.self, from: data).device
    }

    /// PUT /v1/devices/{id} — a partial patch; every argument nil = untouched.
    public func updateDevice(id: String, name: String? = nil, enabled: Bool? = nil,
                             dryRun: Bool? = nil, fields: [String: String]? = nil) async throws -> DeviceInstance {
        var patch: [String: Any] = [:]
        if let name { patch["name"] = name }
        if let enabled { patch["enabled"] = enabled }
        if let dryRun { patch["dry_run"] = dryRun }
        if let fields { patch["fields"] = fields }
        let body = try JSONSerialization.data(withJSONObject: patch)
        let data = try await run(request("v1/devices/\(id)", method: "PUT", body: body))
        return try JSONCoding.decoder().decode(DeviceResponse.self, from: data).device
    }

    /// DELETE /v1/devices/{id} — 204; 409 `armado` while the instance is armed.
    public func deleteDevice(id: String) async throws {
        _ = try await run(request("v1/devices/\(id)", method: "DELETE"), accept: [200, 204])
    }

    // MARK: - O River como aparelho (2026-09-04)

    // --- acesso ao console (0.6.0) -------------------------------------------
    /// Prepara o acesso: o SERVIÇO cria a chave e lê a identidade do console.
    /// A chave privada nunca vem — só a pública e as impressões digitais.
    public func acessoPreparar(id: String, aceitarIdentidade: Bool = false) async throws -> AcessoPreparado {
        let body = try JSONSerialization.data(withJSONObject: ["aceitar_identidade": aceitarIdentidade])
        return try JSONCoding.decoder().decode(
            AcessoPreparado.self,
            from: try await run(request("v1/devices/\(id)/acesso/preparar", method: "POST", body: body)))
    }

    /// Instala a chave no console usando a senha UMA vez. A senha vai no corpo,
    /// para a máquina ao lado, e não é guardada em lugar nenhum.
    public func acessoInstalar(id: String, senha: String) async throws -> AcessoTestado {
        let body = try JSONSerialization.data(withJSONObject: ["senha": senha])
        return try JSONCoding.decoder().decode(
            AcessoTestado.self,
            from: try await run(request("v1/devices/\(id)/acesso/instalar", method: "POST", body: body)))
    }

    /// Roda os comandos de leitura pelo mesmo caminho que executa o desligamento.
    public func acessoTestar(id: String) async throws -> AcessoTestado {
        try JSONCoding.decoder().decode(
            AcessoTestado.self,
            from: try await run(request("v1/devices/\(id)/acesso/testar", method: "POST",
                                        body: Data("{}".utf8))))
    }

    /// Apaga chave, identidade e prova — o dispositivo volta ao ponto zero.
    public func acessoEsquecer(id: String) async throws {
        _ = try await run(request("v1/devices/\(id)/acesso/esquecer", method: "POST",
                                  body: Data("{}".utf8)))
    }

    /// Quem está com o cabo agora. Só leitura: o cabo vai e volta sozinho quando o
    /// aplicativo do fabricante abre e fecha — a tela informa, não manda.
    public func riverCabo() async throws -> EstadoDoCabo {
        try JSONCoding.decoder().decode(EstadoDoCabo.self, from: try await run(request("v1/river/cabo")))
    }

    /// Desliga o PRÓPRIO River. Corta a energia de tudo o que está nele — a tela
    /// só chama isto depois da confirmação, e o serviço ainda exige a trava de
    /// arquivo aberta.
    public func riverDesligar() async throws {
        _ = try await run(request("v1/river/desligar", method: "POST"))
    }

    /// Muda o aviso de bateria fraca DO APARELHO (o "Low battery reminder" do
    /// aplicativo da EcoFlow). Devolve o que o aparelho passou a informar.
    public func riverAvisoBateriaBaixa(_ porcento: Int) async throws -> String? {
        struct Resposta: Decodable { var batteryChargeLow: String? }
        let body = try JSONSerialization.data(withJSONObject: ["battery_charge_low": porcento])
        let dados = try await run(request("v1/river/aparelho", method: "PUT", body: body))
        return try JSONCoding.decoder().decode(Resposta.self, from: dados).batteryChargeLow
    }
}
