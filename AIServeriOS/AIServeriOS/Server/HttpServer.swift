import Foundation
import Network

typealias RouteHandler = (HttpRequest) async -> HttpResponse

// MARK: - Router

final class Router {
    private struct Route {
        let method:  String
        let path:    String
        let handler: RouteHandler
    }

    private var routes: [Route] = []

    func add(_ method: String, _ path: String, handler: @escaping RouteHandler) {
        routes.append(Route(method: method, path: path, handler: handler))
    }

    func handle(_ request: HttpRequest) async -> HttpResponse {
        let clean = request.cleanPath
        // OPTIONS preflight — blanket allow
        if request.method == "OPTIONS" {
            return HttpResponse.json(EmptyBody(), status: 204).addCors()
        }
        for route in routes where route.method == request.method && route.path == clean {
            let resp = await route.handler(request)
            return resp.addCors()
        }
        return HttpResponse.error("Not found", status: 404).addCors()
    }
}

private struct EmptyBody: Encodable {}

// MARK: - Server

/// Minimal HTTP/1.1 server backed by Network.framework.
/// Supports JSON responses and SSE (server-sent events) streaming.
final class HttpServer {

    private var listener: NWListener?
    var port: UInt16
    let router = Router()

    enum State { case stopped, starting, running, error(String) }
    private(set) var state: State = .stopped

    var onStateChange: ((State) -> Void)?

    init(port: UInt16 = 8080) { self.port = port }

    // ── Start / stop ──────────────────────────────────────────────────────────

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HttpServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }

        listener = try NWListener(using: params, on: nwPort)
        state = .starting

        listener?.stateUpdateHandler = { [weak self] s in
            switch s {
            case .ready:
                self?.state = .running
                self?.onStateChange?(.running)
            case .failed(let e):
                let msg = e.localizedDescription
                self?.state = .error(msg)
                self?.onStateChange?(.error(msg))
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }

        listener?.start(queue: .global(qos: .userInteractive))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
        onStateChange?(.stopped)
    }

    // ── Connection handling ───────────────────────────────────────────────────

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInteractive))
        Task {
            do {
                let request  = try await parseRequest(connection)
                let response = await router.handle(request)
                try await send(response, to: connection)
            } catch {
                // Best-effort 400 on parse failure; ignore send errors
                let resp = HttpResponse.error("Bad request", status: 400).addCors()
                try? await send(resp, to: connection)
            }
            // Graceful TCP FIN before cancel so the client can finish reading.
            await connection.sendFin()
            connection.cancel()
        }
    }

    // ── HTTP parser ───────────────────────────────────────────────────────────

    private let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    private func parseRequest(_ conn: NWConnection) async throws -> HttpRequest {
        var buffer = Data()

        // Read until we see \r\n\r\n
        while !buffer.contains(sequence: headerTerminator) {
            let chunk = try await conn.receiveData()
            if chunk.isEmpty { throw NWConnection.ConnectionError.closed }
            buffer.append(chunk)
        }

        // Split headers / body
        guard let termRange = buffer.range(of: headerTerminator) else {
            throw NWConnection.ConnectionError.closed
        }
        let headerData  = buffer[..<termRange.lowerBound]
        var bodyBuffer  = Data(buffer[termRange.upperBound...])

        // Parse request line
        guard let headerStr = String(data: headerData, encoding: .utf8) else {
            throw NWConnection.ConnectionError.closed
        }
        var lines = headerStr.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw NWConnection.ConnectionError.closed }

        let requestLine = lines.removeFirst().split(separator: " ", maxSplits: 2)
        guard requestLine.count >= 2 else { throw NWConnection.ConnectionError.closed }

        let method = String(requestLine[0]).uppercased()
        let path   = String(requestLine[1])

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            if let colon = line.firstIndex(of: ":") {
                let key   = line[..<colon].lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Read body — guard against excessively large payloads (10 MB limit)
        let maxBodySize = 10 * 1024 * 1024
        if let lenStr = headers["content-length"], let contentLength = Int(lenStr), contentLength > 0 {
            guard contentLength <= maxBodySize else {
                throw NWConnection.ConnectionError.closed
            }
            while bodyBuffer.count < contentLength {
                let chunk = try await conn.receiveData()
                if chunk.isEmpty { break }
                bodyBuffer.append(chunk)
                if bodyBuffer.count > maxBodySize { break }
            }
        }

        return HttpRequest(
            method:  method,
            path:    path,
            headers: headers,
            body:    Data(bodyBuffer)
        )
    }

    // ── Response writer ───────────────────────────────────────────────────────

    private func send(_ response: HttpResponse, to conn: NWConnection) async throws {
        var headerStr = "HTTP/1.1 \(response.statusCode) \(statusMessage(response.statusCode))\r\n"
        for (k, v) in response.headers {
            headerStr += "\(k): \(v)\r\n"
        }

        if let sseStream = response.sseStream {
            // ── SSE path ──────────────────────────────────────────────────────
            headerStr += "\r\n"
            try await conn.sendData(Data(headerStr.utf8))

            for await event in sseStream {
                let chunk = "data: \(event)\n\n"
                try await conn.sendData(Data(chunk.utf8))
            }
            // Final SSE done sentinel
            try await conn.sendData(Data("data: [DONE]\n\n".utf8))

        } else {
            // ── Regular response ──────────────────────────────────────────────
            // Content-Length is already set in HttpResponse.headers by the
            // json() factory — do not append it again or Dart's HTTP client
            // will reject the response with "content-length occurred more than once".
            let body = response.body ?? Data()
            headerStr += "\r\n"
            var out = Data(headerStr.utf8)
            out.append(body)
            try await conn.sendData(out)
        }
    }

    private func statusMessage(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default:  return "Unknown"
        }
    }
}

// MARK: - Data helper

private extension Data {
    func contains(sequence: Data) -> Bool {
        range(of: sequence) != nil
    }
}

// MARK: - NWConnection graceful close

private extension NWConnection {
    /// Sends a TCP FIN (half-close the write side) so the remote peer can
    /// finish reading before we call cancel().  Best-effort — errors ignored.
    func sendFin() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            send(
                content: nil,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in cont.resume() }
            )
        }
    }
}
