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
}
