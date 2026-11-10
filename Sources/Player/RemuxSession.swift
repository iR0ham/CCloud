import Foundation

// MARK: - ffmpeg discovery

/// Locates the ffmpeg binary used for the Matroska → fMP4 HLS remux pipeline.
/// Order: explicit test override → bundled app resource → Homebrew/standard locations → PATH.
enum FFmpegLocator {
    /// Environment override used by the test harness to exercise the "ffmpeg missing" error path.
    static let overrideKey = "CCLOUD_FFMPEG_PATH"

    static func locate() -> String? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        if let override = env[overrideKey] {
            return fm.isExecutableFile(atPath: override) ? override : nil
        }

        var candidates: [String] = []
        // Bundled app resource: CCloud.app/Contents/Resources/ffmpeg-bin/ffmpeg
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("ffmpeg-bin/ffmpeg").path)
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ffmpeg-bin/ffmpeg").path)
        // Bare executable / test harness: <exec dir>/../Resources/ffmpeg-bin/ffmpeg
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let execDir = executable.deletingLastPathComponent()
        candidates.append(execDir.appendingPathComponent("../Resources/ffmpeg-bin/ffmpeg").standardizedFileURL.path)
        candidates.append(execDir.appendingPathComponent("Resources/ffmpeg-bin/ffmpeg").standardizedFileURL.path)
        // Homebrew (Apple Silicon + Intel) and PATH.
        candidates.append("/opt/homebrew/bin/ffmpeg")
        candidates.append("/usr/local/bin/ffmpeg")
        candidates.append("/usr/bin/ffmpeg")
        if let path = env["PATH"] {
            for dir in path.split(separator: ":") where !dir.isEmpty {
                candidates.append(String(dir) + "/ffmpeg")
            }
        }

        for candidate in candidates where fm.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }
}

// MARK: - duration probe

/// Best-effort total-duration probe using ffmpeg's own input dump (no ffprobe dependency).
enum FFmpegProbe {
    static func inputArgument(for url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    /// Parses `Duration: 00:01:23.45` from ffmpeg's input dump.
    static func parseDuration(in text: String) -> Double? {
        guard let range = text.range(of: #"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(text[range])
        let numbers = matched.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted)
            .filter { !$0.isEmpty }
        guard numbers.count >= 3,
              let hours = Double(numbers[0]),
              let minutes = Double(numbers[1]),
              let seconds = Double(numbers[2]) else { return nil }
        let total = hours * 3600 + minutes * 60 + seconds
        return total > 0 ? total : nil
    }

    /// One audio stream as the input dump describes it.
    struct AudioStream: Hashable {
        /// Position among the audio streams — what `-map 0:a:<index>` expects.
        let index: Int
        let language: String?
        let title: String?
        let isDefault: Bool
    }

    /// Reads the `Stream #0:1(eng): Audio: …` lines, plus the `title` metadata under each stream.
    static func parseAudioStreams(in text: String) -> [AudioStream] {
        let lines = text.components(separatedBy: "\n")
        var streams: [AudioStream] = []
        for (offset, line) in lines.enumerated() {
            guard let head = audioStreamHead(in: line) else { continue }
            var title: String?
            var probe = offset + 1
            while probe < lines.count, !lines[probe].contains("Stream #") {
                let trimmed = lines[probe].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("title"), let colon = trimmed.firstIndex(of: ":") {
                    let value = String(trimmed[trimmed.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { title = value }
                    break
                }
                probe += 1
            }
            streams.append(AudioStream(index: streams.count,
                                      language: head.language,
                                      title: title,
                                      isDefault: head.isDefault))
        }
        return streams
    }

    /// `(language, isDefault)` for an audio stream line, or nil when the line is some other stream.
    private static func audioStreamHead(in line: String) -> (language: String?, isDefault: Bool)? {
        guard let start = line.range(of: "Stream #0:") else { return nil }
        let rest = line[start.upperBound...]
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let descriptor = String(rest[..<colon])      // "1", "1(eng)", "2[0x2](spa)"
        let kind = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard kind.hasPrefix("Audio") else { return nil }
        var language: String?
        if let open = descriptor.firstIndex(of: "(") {
            let inner = descriptor[descriptor.index(after: open)...]
            if let close = inner.firstIndex(of: ")") {
                let code = String(inner[..<close]).lowercased()
                language = (code.isEmpty || code == "und") ? nil : code
            }
        }
        return (language, line.contains("(default)"))
    }
}

// MARK: - remux session

/// One ffmpeg → fMP4 HLS remux run plus the loopback HTTP server that feeds AVPlayer.
///
/// A session owns: temp directory, ffmpeg process, stderr monitoring, duration probe,
/// segment/playlist polling and the `HLSServer`. It reports events on an internal queue;
/// the controller hops them to the main actor. `stop()` is idempotent and safe to call
/// from any thread; it terminates ffmpeg, closes the server and deletes the temp directory.
final class RemuxSession {
    enum Event {
        /// Server is up and the event playlist has enough segments to start playback.
        case playlistReady(URL)
        /// Newly remuxed media duration (EXTINF sum) for this session window.
        case progress(available: Double)
        /// Total duration of the original media, as reported by ffmpeg's input dump.
        case probed(total: Double)
        /// ffmpeg finished successfully; `remaining` is the remuxed window length.
        case finished(remaining: Double)
        /// ffmpeg was launched; the full argument list (diagnostics / test evidence).
        case launched(arguments: [String])
        /// Every audio stream the input dump shows, so the UI can offer a choice.
        case audio(tracks: [FFmpegProbe.AudioStream])
        /// Fatal error with a user-displayable Persian message.
        case failed(String)
    }

    let sourceURL: URL
    let startAt: Double
    let ffmpegPath: String
    let directory: URL

    /// Which audio stream to keep (`0:a:<n>`); 0 keeps the first one.
    private let audioIndex: Int

    private let onEvent: (Event) -> Void
    private let probeDuration: Bool
    private let queue = DispatchQueue(label: "ir.ccloud.player.remux")
    private let lock = NSLock()
    private var stopped = false

    private var server: HLSServer?
    private var serverPort: UInt16 = 0
    private var process: Process?
    private var stderrText = ""
    private var ticker: DispatchSourceTimer?
    private var probeProcess: Process?
    private var probeTimeout: DispatchSourceTimer?

    private var playlistReadySent = false
    private var failureSent = false
    private var exitHandled = false
    private var startedAt = Date()
    private var lastAvailable: Double = 0
    private var lastInitExists = false

    /// - Parameters:
    ///   - probeDuration: run a separate `ffmpeg -i` probe to learn the real duration of
    ///     the source (only needed for the first session of a source; skips work on restarts).
    ///   - audioIndex: which audio stream to keep; nil takes the first one.
    init(sourceURL: URL, startAt: Double, ffmpegPath: String, probeDuration: Bool,
         audioIndex: Int? = nil, onEvent: @escaping (Event) -> Void) {
        self.sourceURL = sourceURL
        self.startAt = max(0, startAt)
        self.ffmpegPath = ffmpegPath
        self.probeDuration = probeDuration
        self.audioIndex = max(0, audioIndex ?? 0)
        self.onEvent = onEvent
        self.directory = RemuxSession.makeDirectory()
    }

    // MARK: Directory

    private static func tempBase() -> URL {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        for key in ["CCLOUD_TEMP_DIR", "TMPDIR"] {
            if let value = env[key], !value.isEmpty {
                let url = URL(fileURLWithPath: value, isDirectory: true)
                if (try? fm.createDirectory(at: url, withIntermediateDirectories: true)) != nil {
                    return url
                }
            }
        }
        return fm.temporaryDirectory
    }

    private static func makeDirectory() -> URL {
        let base = tempBase()
        return base.appendingPathComponent("CCloudRemux-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: Lifecycle

    func start() {
        queue.async { self.startLocked() }
    }

    /// Non-blocking teardown; guarantees no ffmpeg/server/temp dir survives.
    func stop() {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        stopped = true
        lock.unlock()
        queue.async { self.stopLocked() }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func startLocked() {
        guard !isStopped else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            emit(.failed("ساخت پوشه موقت برای تبدیل ویدئو ممکن نشد"))
            return
        }

        let server = HLSServer(root: directory)
        self.server = server
        server.onReady = { [weak self] port in
            guard let self else { return }
            self.queue.async { self.serverReady(port) }
        }
        server.onFailure = { [weak self] _ in
            self?.queue.async { self?.fail("راه‌اندازی سرور پخش محلی ممکن نشد") }
        }
        server.start()

        startFFmpeg()
        if probeDuration { startProbe() }
        startTicker()
    }

    private func stopLocked() {
        ticker?.cancel()
        ticker = nil
        probeTimeout?.cancel()
        probeTimeout = nil
        if let probe = probeProcess {
            if probe.isRunning { probe.terminate() }
            probeProcess = nil
        }
        if let process {
            process.terminationHandler = nil
            if process.isRunning { process.terminate() }
            self.process = nil
            // Escalate to SIGKILL if ffmpeg ignores SIGTERM (remote input blocking in open).
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        server?.stop()
        server = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func serverReady(_ port: UInt16) {
        serverPort = port
        maybeSendPlaylistReady()
    }

    // MARK: ffmpeg

    private func startFFmpeg() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        let segmentPattern = directory.appendingPathComponent("seg%05d.m4s").path
        let playlistPath = directory.appendingPathComponent("playlist.m3u8").path

        var arguments = ["-hide_banner", "-nostdin", "-loglevel", "warning"]
        // Fast input seek for far-seek restarts. ffmpeg converts timestamps back to zero,
        // the controller adds `startAt` back to everything it displays.
        if startAt > 0.05 {
            arguments += ["-ss", String(format: "%.3f", startAt)]
        }
        // Test-only hook (Tests/player/run.sh --farseek phase): read the input at native rate so
        // the remux window grows in real time, like a slow network source. This lets the harness
        // deterministically exercise the far-seek ffmpeg restart path.
        if RemuxSession.throttleInputForTesting {
            arguments += ["-re"]
        }
        arguments += [
            "-i", FFmpegProbe.inputArgument(for: sourceURL),
            "-map", "0:v:0", "-map", "0:a:\(audioIndex)?", "-c", "copy",
            "-f", "hls", "-hls_time", "4", "-hls_playlist_type", "event",
            "-hls_segment_type", "fmp4",
            "-hls_fmp4_init_filename", "init.mp4",
            "-hls_segment_filename", segmentPattern,
            playlistPath
        ]
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            self.queue.async { self.consumeStderr(data) }
        }
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            self.queue.async { self.ffmpegExited(status: finished.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            emit(.failed("اجرای ffmpeg ممکن نشد. لطفاً ویدئو را با VLC باز کنید."))
            return
        }
        self.process = process
        startedAt = Date()
        emit(.launched(arguments: arguments))
    }

    /// Test-only: `CCLOUD_REMUX_THROTTLE=1` makes ffmpeg read input at native rate (`-re`).
    private static let throttleInputForTesting: Bool = {
        ProcessInfo.processInfo.environment["CCLOUD_REMUX_THROTTLE"] == "1"
    }()

    private func consumeStderr(_ data: Data) {
        guard !isStopped else { return }
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
        stderrText += chunk
        if stderrText.count > 24_000 {
            stderrText = String(stderrText.suffix(12_000))
        }
        if !playlistReadySent, let message = fatalMessage(in: stderrText) {
            fail(message)
        }
    }

    private func fatalMessage(in text: String) -> String? {
        let lowered = text.lowercased()
        if lowered.contains("no such file or directory") {
            return "فایل ویدئو پیدا نشد یا دیگر در دسترس نیست."
        }
        if lowered.contains("permission denied") {
            return "دسترسی به این ویدئو ممکن نیست."
        }
        if lowered.contains("403") || lowered.contains("forbidden") || lowered.contains("401") || lowered.contains("unauthorized") {
            return "سرور اجازهٔ دسترسی به این ویدئو را نداد."
        }
        if lowered.contains("404") || lowered.contains("not found") {
            return "سورس ویدئو در سرور پیدا نشد."
        }
        if lowered.contains("connection refused") || lowered.contains("connection timed out")
            || lowered.contains("failed to resolve") || lowered.contains("network is unreachable")
            || lowered.contains("connection reset") || lowered.contains("server returned 5") {
            return "اتصال به سورس ویدئو برقرار نشد. اتصال شبکه را بررسی کنید."
        }
        if lowered.contains("invalid data found") || lowered.contains("could not find codec parameters")
            || lowered.contains("does not contain any stream") || lowered.contains("no video stream")
            || lowered.contains("unsupported codec") {
            return "محتوای این فایل ویدئویی قابل خواندن نیست."
        }
        if lowered.contains("protocol not found") || lowered.contains("protocol not supported") {
            return "فرمت آدرس این سورس پشتیبانی نمی‌شود."
        }
        if lowered.contains("conversion failed") {
            return "تبدیل فرمت ویدئو ناموفق بود."
        }
        return nil
    }

    private func ffmpegExited(status: Int32) {
        guard !isStopped, !exitHandled else { return }
        exitHandled = true
        process = nil
        let parsed = readPlaylist()
        if let parsed {
            lastAvailable = max(lastAvailable, parsed.available)
        }
        if status == 0 {
            if let parsed, parsed.segments > 0 {
                emit(.progress(available: lastAvailable))
                if !playlistReadySent { maybeSendPlaylistReady(force: true) }
                emit(.finished(remaining: lastAvailable))
            } else if !playlistReadySent {
                fail("این فایل ویدئو محتوای قابل پخشی ندارد.")
            }
            ticker?.cancel()
            ticker = nil
        } else {
            fail(fatalMessage(in: stderrText) ?? "تبدیل فرمت ویدئو ناموفق بود.")
        }
    }

    /// Emits a single failure event and stops producing output.
    private func fail(_ message: String) {
        guard !failureSent, !isStopped else { return }
        failureSent = true
        ticker?.cancel()
        ticker = nil
        emit(.failed(message))
    }

    // MARK: Playlist / segments polling

    private struct PlaylistInfo {
        var available: Double
        var segments: Int
        var endList: Bool
    }

    private func readPlaylist() -> PlaylistInfo? {
        let url = directory.appendingPathComponent("playlist.m3u8")
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        var available = 0.0
        var segments = 0
        var endList = false
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                let value = line.dropFirst("#EXTINF:".count)
                let number = value.split(separator: ",").first.map(String.init) ?? ""
                if let duration = Double(number.trimmingCharacters(in: .whitespaces)), duration.isFinite, duration >= 0 {
                    available += duration
                    segments += 1
                }
            } else if line.hasPrefix("#EXT-X-ENDLIST") {
                endList = true
            }
        }
        return PlaylistInfo(available: available, segments: segments, endList: endList)
    }

    private func startTicker() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.15, leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        ticker = timer
    }

    private func tick() {
        guard !isStopped, !failureSent else { return }
        if let info = readPlaylist() {
            if info.available - lastAvailable > 0.04 {
                lastAvailable = info.available
                emit(.progress(available: lastAvailable))
            }
            lastInitExists = FileManager.default.fileExists(atPath: directory.appendingPathComponent("init.mp4").path)
        }
        maybeSendPlaylistReady()
        if !playlistReadySent, Date().timeIntervalSince(startedAt) > 35 {
            fail("پخش ویدئو زمان زیادی طول کشید.")
        }
    }

    private func maybeSendPlaylistReady(force: Bool = false) {
        guard !playlistReadySent, !failureSent, serverPort != 0 else { return }
        guard let info = readPlaylist() else { return }
        lastInitExists = FileManager.default.fileExists(atPath: directory.appendingPathComponent("init.mp4").path)
        let enoughSegments = force ? info.segments >= 1 : info.segments >= 2
        guard enoughSegments else { return }
        // fMP4 playlists need the init segment on disk before AVPlayer can decode.
        guard lastInitExists || info.segments > 0 else { return }
        guard let url = URL(string: "http://127.0.0.1:\(serverPort)/playlist.m3u8") else { return }
        playlistReadySent = true
        emit(.progress(available: lastAvailable))
        emit(.playlistReady(url))
    }

    // MARK: Duration probe

    private func startProbe() {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: ffmpegPath)
        probe.arguments = ["-hide_banner", "-nostdin", "-loglevel", "info", "-i", FFmpegProbe.inputArgument(for: sourceURL)]
        probe.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        probe.standardError = pipe

        do {
            try probe.run()
        } catch {
            return
        }
        probeProcess = probe

        let timeout = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timeout.schedule(deadline: .now() + 15)
        timeout.setEventHandler {
            if probe.isRunning { probe.terminate() }
        }
        timeout.resume()
        probeTimeout = timeout

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            probe.waitUntilExit()
            timeout.cancel()
            let text = String(data: data, encoding: .utf8) ?? ""
            let total = FFmpegProbe.parseDuration(in: text)
            let tracks = FFmpegProbe.parseAudioStreams(in: text)
            self?.queue.async {
                guard let self, !self.isStopped else { return }
                if let total { self.emit(.probed(total: total)) }
                if tracks.count > 1 { self.emit(.audio(tracks: tracks)) }
            }
        }
    }

    // MARK: Events

    private func emit(_ event: Event) {
        guard !isStopped else { return }
        onEvent(event)
    }
}
