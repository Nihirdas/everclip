import Foundation
import Network

/// A one-shot loopback HTTP receiver used to capture the OAuth redirect on
/// `http://127.0.0.1:<port>`. Handles a single request, replies with a friendly
/// page, and yields the authorization code.
final class LoopbackReceiver: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.nihirdas.everclip.oauth-loopback")
    private var continuation: CheckedContinuation<String, Error>?
    private var didFinish = false
    private let lock = NSLock()

    /// Starts listening on an ephemeral loopback port and returns it.
    func start() throws -> UInt16 {
        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }

        let sem = DispatchSemaphore(value: 0)
        var startError: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: sem.signal()
            case .failed(let error): startError = error; sem.signal()
            default: break
            }
        }
        listener.start(queue: queue)
        _ = sem.wait(timeout: .now() + 5)
        if let startError { throw startError }
        guard let port = listener.port?.rawValue else {
            throw ExportError.authFailed("Could not open a loopback port.")
        }
        return port
    }

    func waitForCode(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            self.continuation = cont
            lock.unlock()
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(ExportError.authFailed("Timed out waiting for consent.")))
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let request = String(data: data, encoding: .utf8) {
                let result = Self.parseCode(from: request)
                let ok: Bool
                if case .success = result { ok = true } else { ok = false }
                self.respond(on: connection, success: ok)
                self.finish(result)
            } else if let error {
                self.respond(on: connection, success: false)
                self.finish(.failure(error))
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(on connection: NWConnection, success: Bool) {
        let title = success ? "EverClip is connected" : "Authorization failed"
        let message = success
            ? "You can close this tab and return to EverClip."
            : "Something went wrong. Return to EverClip and try again."
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font-family:-apple-system,system-ui,sans-serif;background:#0b0c10;color:#e8eaf0;
        display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}
        .card{text-align:center;padding:40px}h1{font-size:20px;margin:0 0 8px}p{color:#9aa3b2}</style></head>
        <body><div class="card"><h1>\(title)</h1><p>\(message)</p></div></body></html>
        """
        let bytes = Array(body.utf8)
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bytes.count)\r
        Connection: close\r
        \r

        """
        var payload = Data(headers.utf8)
        payload.append(contentsOf: bytes)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        didFinish = true
        let cont = continuation
        continuation = nil
        listener?.cancel()
        listener = nil
        switch result {
        case .success(let code): cont?.resume(returning: code)
        case .failure(let error): cont?.resume(throwing: error)
        }
    }

    /// Parses the first request line and pulls out `code` (or an `error`).
    static func parseCode(from request: String) -> Result<String, Error> {
        guard let firstLine = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first else {
            return .failure(ExportError.authFailed("Empty request."))
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return .failure(ExportError.authFailed("Malformed request."))
        }
        let path = String(parts[1])
        guard let components = URLComponents(string: "http://127.0.0.1\(path)") else {
            return .failure(ExportError.authFailed("Malformed redirect."))
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            return .failure(ExportError.authFailed(error))
        }
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return .success(code)
        }
        return .failure(ExportError.authFailed("No authorization code in redirect."))
    }
}
