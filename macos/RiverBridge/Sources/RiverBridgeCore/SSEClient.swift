// SSE consumer for GET /v1/events. Parsing is a pure, unit-tested state
// machine (SSEParser); reconnection with backoff is the caller's loop
// (TelemetryStore) — reconnection is NOT automatic in URLSession, that
// EventSource behavior only exists in browsers.

import Foundation

public struct SSEMessage: Equatable, Sendable {
    public var event: String
    public var data: String

    public init(event: String, data: String) {
        self.event = event
        self.data = data
    }
}

/// Pure line-fed parser: feed lines, collect complete messages.
public struct SSEParser: Sendable {
    private var currentEvent = "message"
    private var dataLines: [String] = []

    public init() {}

    public mutating func feed(line: String) -> SSEMessage? {
        if line.isEmpty {
            defer {
                currentEvent = "message"
                dataLines = []
            }
            guard !dataLines.isEmpty else { return nil }
            return SSEMessage(event: currentEvent, data: dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil } // comment/heartbeat
        if line.hasPrefix("event:") {
            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            return nil
        }
        return nil
    }
}

public struct SSEClient: Sendable {
    public var endpoint: ApiEndpoint

    public init(endpoint: ApiEndpoint) {
        self.endpoint = endpoint
    }

    /// One connection's worth of messages; throws when the stream drops.
    public func messages() -> AsyncThrowingStream<SSEMessage, Error> {
        let endpoint = self.endpoint
        return AsyncThrowingStream { continuation in
            let task = Task {
                var req = URLRequest(url: endpoint.baseURL.appendingPathComponent("v1/events"))
                req.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 3600
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw APIError.badStatus(
                            (response as? HTTPURLResponse)?.statusCode ?? 0, "SSE"
                        )
                    }
                    // Manual line accumulation: URLSession's `bytes.lines`
                    // omits EMPTY lines, and SSE delimits messages exactly by
                    // the empty line — so we must split ourselves.
                    var parser = SSEParser()
                    var buffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(decoding: buffer, as: UTF8.self)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                            buffer.removeAll(keepingCapacity: true)
                            if let message = parser.feed(line: line) {
                                continuation.yield(message)
                            }
                        } else {
                            buffer.append(byte)
                        }
                    }
                    continuation.finish(throwing: APIError.notConnected)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
