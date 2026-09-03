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

    public func state() async throws -> UpsState {
        try JSONCoding.decoder().decode(
            UpsState.self, from: try await run(request("v1/state"))
        )
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

    public func device(id: String) async throws -> DeviceInstance {
        try JSONCoding.decoder().decode(
            DeviceResponse.self, from: try await run(request("v1/devices/\(id)"))
        ).device
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
}
