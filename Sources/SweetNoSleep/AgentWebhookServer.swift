import Foundation
import Network

/// Loopback-only HTTP webhook that lets local tools drive agent leases.
///
/// Binds strictly to 127.0.0.1:18290 so macOS never shows a firewall prompt.
/// Each TCP connection serves exactly one HTTP/1.1 request and then closes.
/// All model mutations hop to @MainActor via Task before touching state.
final class AgentWebhookServer: @unchecked Sendable {
    private let port: UInt16
    private let token: String
    private let onEvent: @MainActor @Sendable (String, String, String?) -> Void
    private let onError: @MainActor @Sendable (String?) -> Void
    private let queue = DispatchQueue(label: "SweetNoSleep.AgentWebhookServer")
    private var listener: NWListener?
    private var isRunning = false
    private var wantsRunning = false
    private var bindRetries = 0

    private static let maxBindRetries = 5
    private static let bindRetryDelay: TimeInterval = 0.1

    private static let maxHeadersBytes = 8 * 1024
    private static let maxBodyBytes = 4 * 1024
    private static let expectedHost = "127.0.0.1:18290"
    private static let expectedOrigin = "http://127.0.0.1:18290"

    /// - Parameters:
    ///   - port: TCP port to bind (default 18290).
    ///   - token: Bearer token expected in Authorization headers.
    ///   - onEvent: Called on @MainActor with (action, sessionID, reason).
    ///   - onError: Called on @MainActor with a user-facing error or nil on recovery.
    init(
        port: UInt16 = 18290,
        token: String,
        onEvent: @MainActor @Sendable @escaping (String, String, String?) -> Void,
        onError: @MainActor @Sendable @escaping (String?) -> Void
    ) {
        self.port = port
        self.token = token
        self.onEvent = onEvent
        self.onError = onError
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = true
            self.startOnQueue()
        }
    }

    func stop() {
        // Must run synchronously: callers drop their strong reference right
        // after stop() returns, so an async block capturing self weakly could
        // be deallocated before executing and leave a zombie NWListener
        // holding the port forever.
        queue.sync {
            wantsRunning = false
            isRunning = false
            bindRetries = 0
            listener?.cancel()
            listener = nil
        }
    }

    // MARK: Listener lifecycle

    private func startOnQueue() {
        guard wantsRunning, !isRunning else { return }
        isRunning = true
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                isRunning = false
                reportError(L10n.text("Port 18290 is already in use"))
                return
            }
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: nwPort
            )
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = endpoint
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleState(state)
            }
            listener.start(queue: queue)
        } catch {
            isRunning = false
            reportError(L10n.text("Port 18290 is already in use"))
        }
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .failed(let error):
            listener = nil
            isRunning = false
            if case .posix(let code) = error, code == .EADDRINUSE,
               bindRetries < Self.maxBindRetries {
                bindRetries += 1
                queue.asyncAfter(deadline: .now() + Self.bindRetryDelay) { [weak self] in
                    guard let self, self.wantsRunning else { return }
                    self.startOnQueue()
                }
                return
            }
            if case .posix(let code) = error, code == .EADDRINUSE {
                reportError(L10n.text("Port 18290 is already in use"))
            } else {
                reportError(L10n.format("Webhook listener failed: %@", String(describing: error)))
            }
        case .cancelled:
            isRunning = false
        case .ready:
            bindRetries = 0
            reportError(nil)
        default:
            break
        }
    }

    private func reportError(_ message: String?) {
        let callback = onError
        Task { @MainActor in
            callback(message)
        }
    }

    private func reportEvent(action: String, sessionID: String, reason: String?) {
        let callback = onEvent
        Task { @MainActor in
            callback(action, sessionID, reason)
        }
    }

    // MARK: Connections (one request per connection)

    private func accept(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let content, !content.isEmpty {
                buffer.append(content)
            }
            if buffer.count > Self.maxHeadersBytes + Self.maxBodyBytes + 512 {
                self.sendResponse(on: connection, status: 413, json: "{\"error\":\"payload too large\"}")
                return
            }
            guard let headerEnd = self.headerEndIndex(in: buffer) else {
                if buffer.count > Self.maxHeadersBytes {
                    self.sendResponse(on: connection, status: 413, json: "{\"error\":\"headers too large\"}")
                    return
                }
                if isComplete {
                    self.sendResponse(on: connection, status: 400, json: "{\"error\":\"bad request\"}")
                    return
                }
                self.receiveRequest(on: connection, accumulated: buffer)
                return
            }
            self.handleHeaders(
                on: connection,
                headerData: buffer[buffer.startIndex..<headerEnd],
                bodyPrefix: Data(buffer[headerEnd..<buffer.count]),
                receivedComplete: isComplete
            )
        }
    }

    private func headerEndIndex(in data: Data) -> Data.Index? {
        let needle: [UInt8] = [13, 10, 13, 10]
        guard data.count >= needle.count else { return nil }
        var index = data.startIndex
        let end = data.index(data.endIndex, offsetBy: -needle.count)
        while index <= end {
            if data[index] == 13,
               data[data.index(index, offsetBy: 1)] == 10,
               data[data.index(index, offsetBy: 2)] == 13,
               data[data.index(index, offsetBy: 3)] == 10 {
                return data.index(index, offsetBy: 4)
            }
            index = data.index(after: index)
        }
        return nil
    }

    private func handleHeaders(
        on connection: NWConnection,
        headerData: Data,
        bodyPrefix: Data,
        receivedComplete: Bool
    ) {
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            sendResponse(on: connection, status: 400, json: "{\"error\":\"bad request\"}")
            return
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(on: connection, status: 400, json: "{\"error\":\"bad request\"}")
            return
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard requestParts.count == 3 else {
            sendResponse(on: connection, status: 400, json: "{\"error\":\"bad request\"}")
            return
        }
        let method = String(requestParts[0]).uppercased()
        let rawPath = String(requestParts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[name] == nil {
                headers[name] = value
            }
        }

        guard method == "POST" else {
            sendResponse(on: connection, status: 405, json: "{\"error\":\"method not allowed\"}")
            return
        }

        guard let host = headers["host"]?.trimmingCharacters(in: .whitespaces),
              host == Self.expectedHost else {
            sendResponse(on: connection, status: 403, json: "{\"error\":\"forbidden host\"}")
            return
        }

        if let origin = headers["origin"]?.trimmingCharacters(in: .whitespaces), !origin.isEmpty {
            guard origin == Self.expectedOrigin || origin == "null" else {
                sendResponse(on: connection, status: 403, json: "{\"error\":\"forbidden origin\"}")
                return
            }
        }

        guard let authorization = headers["authorization"],
              Self.constantTimeEqual(authorization, "Bearer \(token)") else {
            sendResponse(on: connection, status: 401, json: "{\"error\":\"unauthorized\"}")
            return
        }

        guard let action = Self.action(for: rawPath) else {
            sendResponse(on: connection, status: 404, json: "{\"error\":\"not found\"}")
            return
        }

        let contentLength = Int(headers["content-length"]?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
        if contentLength < 0 || contentLength > Self.maxBodyBytes {
            sendResponse(on: connection, status: 413, json: "{\"error\":\"payload too large\"}")
            return
        }

        if let expect = headers["expect"]?.lowercased(), expect.contains("100-continue") {
            connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
        }

        if bodyPrefix.count >= contentLength {
            let body = bodyPrefix.prefix(contentLength)
            handleBody(on: connection, action: action, body: Data(body))
            return
        }
        if bodyPrefix.count > Self.maxBodyBytes {
            sendResponse(on: connection, status: 413, json: "{\"error\":\"payload too large\"}")
            return
        }
        receiveBody(
            on: connection,
            action: action,
            accumulated: bodyPrefix,
            remaining: contentLength - bodyPrefix.count
        )
    }

    private func receiveBody(
        on connection: NWConnection,
        action: String,
        accumulated: Data,
        remaining: Int
    ) {
        if remaining <= 0 {
            handleBody(on: connection, action: action, body: accumulated)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 8 * 1024)) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var next = accumulated
            if let content, !content.isEmpty {
                next.append(content)
            }
            if next.count > Self.maxBodyBytes {
                self.sendResponse(on: connection, status: 413, json: "{\"error\":\"payload too large\"}")
                return
            }
            let left = remaining - (content?.count ?? 0)
            if left <= 0 {
                self.handleBody(on: connection, action: action, body: next)
                return
            }
            if isComplete {
                self.sendResponse(on: connection, status: 400, json: "{\"error\":\"incomplete body\"}")
                return
            }
            self.receiveBody(on: connection, action: action, accumulated: next, remaining: left)
        }
    }

    private func handleBody(on connection: NWConnection, action: String, body: Data) {
        guard !body.isEmpty else {
            sendResponse(on: connection, status: 400, json: "{\"error\":\"missing session\"}")
            return
        }
        guard body.count <= Self.maxBodyBytes else {
            sendResponse(on: connection, status: 413, json: "{\"error\":\"payload too large\"}")
            return
        }
        let decoded: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: body, options: [])
            guard let dictionary = object as? [String: Any] else {
                sendResponse(on: connection, status: 400, json: "{\"error\":\"bad json\"}")
                return
            }
            decoded = dictionary
        } catch {
            sendResponse(on: connection, status: 400, json: "{\"error\":\"bad json\"}")
            return
        }
        guard let sessionID = decoded["session"] as? String,
              !sessionID.isEmpty,
              sessionID.count <= 120 else {
            sendResponse(on: connection, status: 400, json: "{\"error\":\"missing session\"}")
            return
        }
        let reason = decoded["reason"] as? String
        reportEvent(action: action, sessionID: sessionID, reason: reason)
        sendResponse(on: connection, status: 200, json: "{\"ok\":true}")
    }

    private static func action(for rawPath: String) -> String? {
        let path = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? rawPath
        switch path {
        case "/agent/start": return "start"
        case "/agent/heartbeat": return "heartbeat"
        case "/agent/waiting": return "waiting"
        case "/agent/done": return "done"
        case "/agent/failed": return "failed"
        default: return nil
        }
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }

    private func sendResponse(on connection: NWConnection, status: Int, json: String) {
        let phrase: String
        switch status {
        case 200: phrase = "OK"
        case 400: phrase = "Bad Request"
        case 401: phrase = "Unauthorized"
        case 403: phrase = "Forbidden"
        case 404: phrase = "Not Found"
        case 405: phrase = "Method Not Allowed"
        case 413: phrase = "Payload Too Large"
        default: phrase = "Error"
        }
        let body = Data(json.utf8)
        let header = "HTTP/1.1 \(status) \(phrase)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
    }
}
