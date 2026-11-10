import Foundation
import Network

/// Tiny loopback-only HTTP/1.1 file server used to feed AVPlayer the fMP4 HLS files
/// that ffmpeg writes while remuxing a Matroska source (and, in tests, any local media).
///
/// - Binds to 127.0.0.1 on an ephemeral port (never exposed on the LAN).
/// - GET + HEAD, byte ranges (`Range: bytes=...`), concurrent connections, keep-alive.
/// - Correct Content-Types for `.m3u8`, `.m4s`, `.mp4`, `.ts` and `Cache-Control: no-cache`
///   so AVPlayer re-reads the growing event playlist.
/// - All socket I/O happens on a private serial queue; callbacks are delivered on the main queue.
final class HLSServer {
    private let root: URL
    private let queue = DispatchQueue(label: "ir.ccloud.player.hlsserver")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    private var stopped = false
    private let stateLock = NSLock()
    private var _port: UInt16 = 0

    /// Ephemeral port assigned by the system, valid once `onReady` fired.
    var port: UInt16 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _port
    }

    /// Called on the main queue when the listener is ready.
    var onReady: ((UInt16) -> Void)?
    /// Called on the main queue when the listener could not start.
    var onFailure: ((String) -> Void)?
    /// Optional request log (called on the server queue); used by the test harness.
    var logHandler: ((String) -> Void)?

    init(root: URL, logHandler: ((String) -> Void)? = nil) {
        self.root = root.standardizedFileURL
        self.logHandler = logHandler
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { self.startLocked() }
    }

    func stop() {
        queue.async { self.stopLocked() }
    }

    private func startLocked() {
        guard listener == nil, !stopped else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Bind explicitly to loopback so no firewall prompt appears and nothing is exposed.
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                self?.queue.async { self?.handleState(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.queue.async { self.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            let message = "راه‌اندازی سرور پخش محلی ممکن نشد"
            DispatchQueue.main.async { [weak self] in self?.onFailure?(message) }
        }
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            let assigned = listener?.port?.rawValue ?? 0
            stateLock.lock()
            _port = assigned
            stateLock.unlock()
            DispatchQueue.main.async { [weak self] in self?.onReady?(assigned) }
        case .failed:
            DispatchQueue.main.async { [weak self] in
                self?.onFailure?("راه‌اندازی سرور پخش محلی ممکن نشد")
            }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped else { connection.cancel(); return }
        // Defense in depth: the listener is loopback-only, but double-check the peer address.
        if case let .hostPort(host, _) = connection.endpoint {
            let isLoopback: Bool
            switch host {
            case .ipv4(let address):
                isLoopback = address == .loopback
            case .ipv6(let address):
                isLoopback = address == .loopback
            case .name(let name, _):
                isLoopback = name == "localhost" || name == "127.0.0.1" || name == "::1"
            @unknown default:
                isLoopback = false
            }
            if !isLoopback { connection.cancel(); return }
        }
        let handler = HTTPConnection(connection: connection, server: self)
        connections[ObjectIdentifier(handler)] = handler
        handler.onClose = { [weak self, weak handler] in
            guard let self, let handler else { return }
            self.queue.async { self.connections.removeValue(forKey: ObjectIdentifier(handler)) }
        }
        handler.start()
    }

    private func stopLocked() {
        guard !stopped else { return }
        stopped = true
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for handler in connections.values { handler.cancel() }
        connections.removeAll()
    }

    // MARK: - Request handling (server queue)

    fileprivate func handleRequest(_ request: HTTPRequest, on connection: HTTPConnection) {
        log("\(request.method) \(request.path)\(request.rangeHeader.map { " range=\($0)" } ?? "")")
        guard request.method == "GET" || request.method == "HEAD" else {
            connection.respond(status: 405, reason: "Method Not Allowed", contentType: "text/plain; charset=utf-8",
                              body: Data("Method Not Allowed\n".utf8), headOnly: request.method == "HEAD")
            return
        }
        guard let fileURL = resolve(path: request.path), let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let type = attributes[.type] as? FileAttributeType, type == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            connection.respond(status: 404, reason: "Not Found", contentType: "text/plain; charset=utf-8",
                              body: Data("Not Found\n".utf8), headOnly: request.method == "HEAD")
            return
        }

        let contentType = HLSServer.contentType(for: fileURL.pathExtension)
        var start: UInt64 = 0
        var end: UInt64 = size > 0 ? size - 1 : 0
        var status = 200
        var reason = "OK"
        if let header = request.rangeHeader, size > 0 {
            guard let parsed = HLSServer.parseRange(header, size: size) else {
                var headers = "Content-Range: bytes */\(size)\r\n"
                headers += HLSServer.commonHeaders(contentType: contentType)
                connection.respondRaw(status: 416, reason: "Range Not Satisfiable", extraHeaders: headers,
                                     body: Data(), headOnly: request.method == "HEAD")
                return
            }
            start = parsed.0
            end = parsed.1
            status = 206
            reason = "Partial Content"
        }

        var headers = ""
        if status == 206 {
            headers += "Content-Range: bytes \(start)-\(end)/\(size)\r\n"
        }
        headers += HLSServer.commonHeaders(contentType: contentType)
        let length = size == 0 ? 0 : end - start + 1
        connection.respondFile(url: fileURL, start: start, length: length, status: status, reason: reason,
                               extraHeaders: headers, headOnly: request.method == "HEAD")
    }

    fileprivate func log(_ line: String) {
        logHandler?(line)
    }

    private func resolve(path: String) -> URL? {
        var relative = path
        if let query = relative.firstIndex(of: "?") { relative = String(relative[..<query]) }
        if let fragment = relative.firstIndex(of: "#") { relative = String(relative[..<fragment]) }
        relative = relative.removingPercentEncoding ?? relative
        while relative.hasPrefix("/") { relative.removeFirst() }
        guard !relative.isEmpty, !relative.contains("\0") else { return nil }
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath) else { return nil }
        return candidate
    }

    private static func commonHeaders(contentType: String) -> String {
        var headers = "Content-Type: \(contentType)\r\n"
        headers += "Cache-Control: no-cache, no-store, must-revalidate\r\n"
        headers += "Pragma: no-cache\r\n"
        headers += "Accept-Ranges: bytes\r\n"
        headers += "Access-Control-Allow-Origin: *\r\n"
        return headers
    }

    static func contentType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "m3u8", "m3u": return "application/vnd.apple.mpegurl"
        case "m4s": return "video/iso.segment"
        case "mp4", "m4v", "m4a": return "video/mp4"
        case "ts": return "video/mp2t"
        case "aac": return "audio/aac"
        case "vtt": return "text/vtt"
        case "key": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }

    /// Parses a single-range `bytes=` header into inclusive (start, end) offsets.
    static func parseRange(_ header: String, size: UInt64) -> (UInt64, UInt64)? {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes="), size > 0 else { return nil }
        let spec = trimmed.dropFirst("bytes=".count)
        guard !spec.contains(",") else { return nil } // multi-range not supported; AVPlayer never asks
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        let endText = parts[1].trimmingCharacters(in: .whitespaces)
        if startText.isEmpty {
            // suffix range: last N bytes
            guard let suffix = UInt64(endText), suffix > 0 else { return nil }
            let count = min(suffix, size)
            return (size - count, size - 1)
        }
        guard let start = UInt64(startText), start < size else { return nil }
        if endText.isEmpty { return (start, size - 1) }
        guard let end = UInt64(endText) else { return nil }
        return (start, min(max(end, start), size - 1))
    }
}

// MARK: - HTTP request parsing

struct HTTPRequest {
    let method: String
    let path: String
    let rangeHeader: String?
    let connectionClose: Bool
}

extension HTTPRequest {
    /// Parses a request head (everything before the blank line). Returns nil if malformed.
    init?(head: String) {
        let lines = head.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        method = String(parts[0]).uppercased()
        path = String(parts[1])
        var range: String?
        var close = false
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch name {
            case "range": range = value
            case "connection": close = value.lowercased().contains("close")
            default: break
            }
        }
        rangeHeader = range
        connectionClose = close
    }
}

// MARK: - One TCP connection (may serve many keep-alive requests)

final class HTTPConnection {
    private let connection: NWConnection
    private unowned let server: HLSServer
    private let stateQueue = DispatchQueue(label: "ir.ccloud.player.hlsserver.conn")
    private var buffer = Data()
    private var closed = false
    private var sending = false
    private var keepAlive = true
    var onClose: (() -> Void)?

    init(connection: NWConnection, server: HLSServer) {
        self.connection = connection
        self.server = server
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.stateQueue.async { self?.close() }
            default:
                break
            }
        }
        connection.start(queue: stateQueue)
        stateQueue.async { [weak self] in self?.receive() }
    }

    /// Safe to call from any queue; the connection is closed on its own state queue.
    func cancel() {
        stateQueue.async { [weak self] in self?.close() }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?()
    }

    private func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.pump()
            }
            if error != nil || isComplete {
                self.close()
                return
            }
            if !self.closed && !self.sending { self.receive() }
        }
    }

    /// Parses and dispatches one queued request (if any); only one in flight at a time.
    private func pump() {
        guard !closed, !sending, !buffer.isEmpty else { return }
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > 64 * 1024 { close() }
            return
        }
        let headData = buffer.subdata(in: 0..<headerRange.lowerBound)
        buffer.removeSubrange(0..<headerRange.upperBound)
        guard let head = String(data: headData, encoding: .utf8), let request = HTTPRequest(head: head) else {
            close()
            return
        }
        sending = true
        self.keepAlive = !request.connectionClose
        server.handleRequest(request, on: self)
    }

    private func finishResponse() {
        sending = false
        if closed { return }
        if !keepAlive {
            close()
            return
        }
        if buffer.isEmpty {
            receive()
        } else {
            pump()
        }
    }

    // MARK: Responses

    func respond(status: Int, reason: String, contentType: String, body: Data, headOnly: Bool) {
        var headers = "Content-Type: \(contentType)\r\n"
        headers += "Cache-Control: no-cache, no-store, must-revalidate\r\n"
        headers += "Accept-Ranges: bytes\r\n"
        respondRaw(status: status, reason: reason, extraHeaders: headers, body: body, headOnly: headOnly)
    }

    func respondRaw(status: Int, reason: String, extraHeaders: String, body: Data, headOnly: Bool) {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += extraHeaders
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n"
        head += "\r\n"
        var payload = Data(head.utf8)
        if !headOnly { payload.append(body) }
        send(payload) { [weak self] in self?.finishResponse() }
    }

    func respondFile(url: URL, start: UInt64, length: UInt64, status: Int, reason: String,
                     extraHeaders: String, headOnly: Bool) {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += extraHeaders
        head += "Content-Length: \(length)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n"
        head += "\r\n"
        let headerData = Data(head.utf8)
        guard !headOnly, length > 0 else {
            send(headerData) { [weak self] in self?.finishResponse() }
            return
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            respond(status: 404, reason: "Not Found", contentType: "text/plain; charset=utf-8",
                    body: Data("Not Found\n".utf8), headOnly: headOnly)
            return
        }
        do {
            try handle.seek(toOffset: start)
        } catch {
            try? handle.close()
            respond(status: 500, reason: "Internal Server Error", contentType: "text/plain; charset=utf-8",
                    body: Data(), headOnly: headOnly)
            return
        }
        sendChunks(handle: handle, header: headerData, remaining: length, chunkSize: 256 * 1024)
    }

    private func sendChunks(handle: FileHandle, header: Data?, remaining: UInt64, chunkSize: Int) {
        guard !closed else {
            try? handle.close()
            return
        }
        var prefix = Data()
        if let header { prefix = header }
        if remaining == 0 {
            try? handle.close()
            send(prefix) { [weak self] in self?.finishResponse() }
            return
        }
        let toRead = Int(min(UInt64(chunkSize), remaining))
        let chunk: Data
        do {
            chunk = try handle.read(upToCount: toRead) ?? Data()
        } catch {
            try? handle.close()
            close()
            return
        }
        guard !chunk.isEmpty else {
            // File truncated while streaming: terminate this response.
            try? handle.close()
            send(prefix) { [weak self] in self?.finishResponse() }
            return
        }
        var payload = prefix
        payload.append(chunk)
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self else { try? handle.close(); return }
            if error != nil {
                try? handle.close()
                self.close()
                return
            }
            self.sendChunks(handle: handle, header: nil, remaining: remaining - UInt64(chunk.count), chunkSize: chunkSize)
        })
    }

    private func send(_ data: Data, completion: (() -> Void)? = nil) {
        guard !closed else {
            completion?()
            return
        }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.close()
                return
            }
            completion?()
        })
    }
}
