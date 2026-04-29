import Foundation
import Network

// MARK: - Request

struct HttpRequest {
    let method:  String
    let path:    String
    let headers: [String: String]
    let body:    Data

    /// Parse a JSON body into a Decodable type.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }

    /// Query parameter extracted from path, e.g. /foo?bar=baz
    var queryParams: [String: String] {
        guard let idx = path.firstIndex(of: "?") else { return [:] }
        let qs = String(path[path.index(after: idx)...])
        var result: [String: String] = [:]
        for pair in qs.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let k = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let v = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                result[k] = v
            }
        }
        return result
    }

    /// Path without query string.
    var cleanPath: String {
        path.split(separator: "?").first.map(String.init) ?? path
    }
}

// MARK: - Response

final class HttpResponse {
    let statusCode: Int
    var headers:    [(String, String)]
    var body:       Data?
    /// Non-nil for SSE responses; server streams these as `data: ...\n\n`.
    var sseStream:  AsyncStream<String>?

    private init(statusCode: Int, headers: [(String, String)]) {
        self.statusCode = statusCode
        self.headers    = headers
    }

    // ── Factories ─────────────────────────────────────────────────────────────

    static func json<T: Encodable>(
        _ value: T,
        status: Int = 200
    ) -> HttpResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        let r = HttpResponse(statusCode: status, headers: [
            ("Content-Type",   "application/json"),
            ("Content-Length", "\(data.count)"),
        ])
        r.body = data
        return r
    }

    static func error(_ message: String, status: Int = 500) -> HttpResponse {
        json(ErrorResponse(error: message), status: status)
    }

    static func sse(_ stream: AsyncStream<String>) -> HttpResponse {
        let r = HttpResponse(statusCode: 200, headers: [
            ("Content-Type",  "text/event-stream"),
            ("Cache-Control", "no-cache"),
            ("Connection",    "keep-alive"),
        ])
        r.sseStream = stream
        return r
    }

    // ── Common headers ────────────────────────────────────────────────────────

    func addCors() -> HttpResponse {
        headers.append(("Access-Control-Allow-Origin",  "*"))
        headers.append(("Access-Control-Allow-Methods", "GET, POST, OPTIONS"))
        headers.append(("Access-Control-Allow-Headers", "Content-Type, Authorization"))
        return self
    }
}

// MARK: - NWConnection async extensions

extension NWConnection {
    enum ConnectionError: Error { case closed }

    /// Async wrapper around `receive`.
    func receiveData(maxLength: Int = 65536) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: maxLength) {
                data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: ConnectionError.closed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    /// Async wrapper around `send`.
    func sendData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            send(content: data, completion: .contentProcessed { error in
                if let error = error { c.resume(throwing: error) }
                else { c.resume() }
            })
        }
    }
}
