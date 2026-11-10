import AppKit
import AVFoundation
import Foundation

// Headless-ish harness for the CCloud playback engine.
// Uses NSApplication + NSWindow + a real AVPlayerLayer (no SwiftUI, no @State) and verifies
// playback with locally generated media served over loopback HTTP (faithful to the real catalog)
// and with file:// URLs (used by the app's local demo/QA hook).

// MARK: - Small utilities

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "inf" }
    let value = max(0, seconds)
    return String(format: "%.2f", value)
}

func portIsOpen(_ port: UInt16) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return result == 0
}

/// Runs a command, returns trimmed stdout lines.
@discardableResult
func runCommand(_ path: String, _ arguments: [String]) -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    return text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

struct CommandOutput {
    let status: Int32
    let stdout: String
    let stderr: String
}

func runCaptured(_ path: String, _ arguments: [String]) -> CommandOutput {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
    } catch {
        return CommandOutput(status: -1, stdout: "", stderr: "")
    }
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandOutput(status: process.terminationStatus,
                         stdout: String(data: outData, encoding: .utf8) ?? "",
                         stderr: String(data: errData, encoding: .utf8) ?? "")
}

func fetchHeaders(_ url: String) -> String {
    runCaptured("/usr/bin/curl", ["-sS", "--max-time", "5", "-D", "-", "-o", "/dev/null", url]).stdout
}

func ffmpegRemnants() -> [String] {
    runCommand("/usr/bin/pgrep", ["-fl", "ffmpeg.*CCloudRemux-"])
}

func listeningInfo(port: UInt16) -> String {
    let lines = runCommand("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
    return lines.joined(separator: " | ")
}

/// Remux temp dirs created by the harness's own sessions. `RemuxSession` honours `TMPDIR`
/// first, and run.sh points it at Tests/player/out/tmp; do not scan the system temp dir because
/// other CCloud processes (e.g. the app demo) legitimately create CCloudRemux-* dirs there.
func remuxTempDirs() -> [String] {
    let base: URL
    if let temp = ProcessInfo.processInfo.environment["TMPDIR"], !temp.isEmpty {
        base = URL(fileURLWithPath: temp, isDirectory: true)
    } else {
        base = FileManager.default.temporaryDirectory
    }
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
    return contents.filter { $0.hasPrefix("CCloudRemux-") }
}

func containsPersian(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        (0x0600...0x06FF).contains(scalar.value) || (0xFB50...0xFDFF).contains(scalar.value)
    }
}

// MARK: - Harness

struct HarnessOptions {
    var missingFFmpeg = false
    var phase = "full"
    var mediaDir: URL
    var outDir: URL
}

@MainActor
final class PlayerHarness {
    let options: HarnessOptions
    private var checks = 0
    private var failures = 0
    private var window: NSWindow?

    init(options: HarnessOptions) {
        self.options = options
    }

    // MARK: Reporting

    func section(_ title: String) {
        print("\n=== \(title) ===")
    }

    func check(_ condition: Bool, _ label: String) {
        checks += 1
        if condition {
            print("PASS  \(label)")
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    func info(_ text: String) {
        print("      \(text)")
    }

    /// The text the player is showing while it works (failover note, reconnect message…).
    func preparingMessage(_ controller: PlaybackController) -> String {
        if case .preparing(let text) = controller.status { return text }
        return ""
    }

    func describe(_ controller: PlaybackController) -> String {
        let statusText: String
        switch controller.status {
        case .idle: statusText = "idle"
        case .preparing(let message): statusText = "preparing(\(message))"
        case .ready: statusText = "ready"
        case .failed(let message): statusText = "failed(\(message))"
        }
        let ranges = controller.bufferedRanges
            .map { "\(formatTime($0.lowerBound))-\(formatTime($0.upperBound))" }
            .joined(separator: ",")
        return "status=\(statusText) t=\(formatTime(controller.currentTime)) dur=\(formatTime(controller.duration)) "
            + "playing=\(controller.isPlaying) buf=\(controller.isBuffering) pipeline=\(controller.pipeline.rawValue) "
            + "ranges=[\(ranges)]"
    }

    // MARK: Async helpers

    @discardableResult
    func waitUntil(_ timeout: Double, interval: Double = 0.05, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return condition()
    }

    func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Samples the controller once per second for `seconds` and prints the state (evidence in the log).
    func monitor(_ controller: PlaybackController, seconds: Double, label: String) async {
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            let elapsed = Date().timeIntervalSince(start)
            print("      [\(label) +\(formatTime(elapsed))s] \(describe(controller))")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func waitForReady(_ controller: PlaybackController, timeout: Double) async -> Bool {
        await waitUntil(timeout) {
            switch controller.status {
            case .ready, .failed: return true
            case .idle, .preparing: return false
            }
        }
    }

    func makeWindow() -> NSWindow {
        let frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "CCloud player engine harness"
        let view = PlayerLayerView(frame: frame)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.orderFront(nil)
        return window
    }

    func attach(_ controller: PlaybackController) {
        guard let view = window?.contentView as? PlayerLayerView else { return }
        view.playerLayer.player = controller.player
    }

    // MARK: Entry point

    func run() async -> Int32 {
        print("== CCloud playback engine harness ==")
        print("ffmpeg located: \(FFmpegLocator.locate() ?? "<none>")")
        print("media dir: \(options.mediaDir.path)")
        print("temp dir: \(ProcessInfo.processInfo.environment["TMPDIR"] ?? FileManager.default.temporaryDirectory.path)")

        if options.missingFFmpeg {
            return await missingFFmpegScenario()
        }
        if options.phase == "farseek" {
            return await farseekPhaseRun()
        }
        if options.phase == "stall" {
            return await stallPhaseRun()
        }

        let mp4 = options.mediaDir.appendingPathComponent("sample.mp4")
        let mkv = options.mediaDir.appendingPathComponent("sample.mkv")
        guard FileManager.default.fileExists(atPath: mp4.path), FileManager.default.fileExists(atPath: mkv.path) else {
            print("FATAL: test media missing in \(options.mediaDir.path); run Tests/player/run.sh")
            return 1
        }

        window = makeWindow()
        NSApp.activate(ignoringOtherApps: true)

        let mediaServer = HLSServer(root: options.mediaDir) { line in
            print("[media-server] \(line)")
        }
        mediaServer.start()
        guard await waitUntil(8, { mediaServer.port != 0 }) else {
            print("FATAL: media HTTP server did not start")
            return 1
        }
        let mediaPort = mediaServer.port
        print("\nmedia server: http://127.0.0.1:\(mediaPort)/")
        print("media server lsof: \(listeningInfo(port: mediaPort))")
        check(listeningInfo(port: mediaPort).contains("127.0.0.1"),
              "media server listens on 127.0.0.1 only")
        check(options.mediaDir.path.contains("Tests/player/out"), "test media lives inside the project")

        await directMP4Tests(port: mediaPort)
        await remuxMKVTests(port: mediaPort)
        await fallbackTests(port: mediaPort)
        await errorTests(port: mediaPort)
        await sourceSwitchingTests(port: mediaPort)
        await failoverTests(port: mediaPort)
        await networkRecoveryTests(port: mediaPort)
        await audioTrackTests()
        await fileURLTests()
        await deinitCleanupTests()

        // Global cleanup: stop the media server, make sure nothing we started survives.
        mediaServer.stop()
        await waitUntil(5) { !portIsOpen(mediaPort) }
        check(!portIsOpen(mediaPort), "media server port closed after stop")
        await cleanupCheck(label: "after all tests")

        print("\n== Result: \(checks - failures)/\(checks) checks passed, \(failures) failed ==")
        return failures == 0 ? 0 : 1
    }

    // MARK: Direct mp4

    func directMP4Tests(port: UInt16) async {
        section("1) direct AVPlayer playback: mp4 over HTTP")
        let source = MediaSource(id: 101, quality: "720p", type: "mp4",
                                 url: "http://127.0.0.1:\(port)/sample.mp4")
        let controller = PlaybackController(request: PlaybackRequest(title: "تست مستقیم", sources: [source]))
        attach(controller)

        let ready = await waitForReady(controller, timeout: 20)
        check(ready && controller.status == .ready, "status == .ready (got \(describe(controller)))")
        check(controller.pipeline == .direct, "pipeline == direct")
        await monitor(controller, seconds: 3, label: "mp4")
        check(controller.isPlaying, "isPlaying == true")

        let t0 = controller.currentTime
        await sleep(2.0)
        let t1 = controller.currentTime
        check(t1 > t0 + 1.2, "currentTime advances over 2s: \(formatTime(t0)) -> \(formatTime(t1))")
        check(controller.duration > 30, "duration detected (~40s, got \(formatTime(controller.duration)))")

        // Seek inside the buffered/available range (zero-tolerance seek).
        controller.seek(to: 15)
        await waitUntil(6) { abs(controller.currentTime - 15) < 1.5 }
        check(abs(controller.currentTime - 15) < 1.5,
              "seek(to: 15) landed at \(formatTime(controller.currentTime))")
        controller.seek(to: 25)
        await waitUntil(6) { abs(controller.currentTime - 25) < 1.5 }
        check(abs(controller.currentTime - 25) < 1.5,
              "second seek(to: 25) landed at \(formatTime(controller.currentTime))")
        check(!controller.bufferedRanges.isEmpty,
              "bufferedRanges populated: \(describe(controller))")

        // Pause / resume.
        controller.pause()
        let pausedAt = controller.currentTime
        await sleep(1.2)
        let stillPaused = controller.currentTime
        check(abs(stillPaused - pausedAt) < 0.35,
              "paused: currentTime frozen at \(formatTime(pausedAt)) (now \(formatTime(stillPaused)))")
        check(!controller.isPlaying, "isPlaying == false while paused")
        controller.play()
        await sleep(1.5)
        check(controller.currentTime > stillPaused + 0.5,
              "resumed: \(formatTime(stillPaused)) -> \(formatTime(controller.currentTime))")
        check(controller.isPlaying, "isPlaying == true after resume")

        // Rate + volume.
        controller.rate = 1.5
        let r0 = controller.currentTime
        await sleep(2.0)
        let r1 = controller.currentTime
        check(r1 - r0 > 2.1, "rate 1.5x advances faster over 2s: \(formatTime(r0)) -> \(formatTime(r1))")
        controller.rate = 2.5
        check(controller.rate == 2.0, "rate clamped to 2.0 (got \(controller.rate))")
        controller.rate = 0.1
        check(controller.rate == 0.5, "rate clamped to 0.5 (got \(controller.rate))")
        controller.rate = 1.0
        controller.volume = 2.0
        check(controller.volume == 1.0, "volume clamped to 1.0 (got \(controller.volume))")
        check(abs(controller.player.volume - 1.0) < 0.01, "AVPlayer volume applied (\(controller.player.volume))")
        controller.volume = 0.5
        check(abs(controller.player.volume - 0.5) < 0.01, "AVPlayer volume updated to 0.5")

        // togglePlay
        controller.rate = 1.0
        controller.seek(to: 5)
        await waitUntil(6) { abs(controller.currentTime - 5) < 1.5 }
        controller.togglePlay()
        await sleep(0.8)
        check(!controller.isPlaying, "togglePlay() pauses")
        controller.togglePlay()
        await sleep(1.0)
        check(controller.isPlaying, "togglePlay() resumes")

        // End of item → isPlaying == false, timeline at the end.
        controller.seek(to: 39.0)
        await waitUntil(12) { !controller.isPlaying }
        check(!controller.isPlaying,
              "end of item sets isPlaying=false (t=\(formatTime(controller.currentTime)), dur=\(formatTime(controller.duration)))")
        check(controller.currentTime >= controller.duration - 1.2,
              "currentTime parked at end (\(formatTime(controller.currentTime)) / \(formatTime(controller.duration)))")

        controller.stop()
        check(controller.status == .idle && controller.currentTime == 0 && !controller.isPlaying,
              "stop() resets status/time: \(describe(controller))")
        check(controller.player.currentItem == nil, "stop() detaches AVPlayerItem")
        await cleanupCheck(label: "after direct mp4")
    }

    // MARK: Remux mkv

    func remuxMKVTests(port: UInt16) async {
        section("2) ffmpeg → fMP4 HLS remux: mkv over HTTP")
        let source = MediaSource(id: 201, quality: "1080p", type: "mkv",
                                 url: "http://127.0.0.1:\(port)/sample.mkv")
        let controller = PlaybackController(request: PlaybackRequest(title: "تست MKV", sources: [source]))
        attach(controller)

        check(controller.status.isPreparing, "starts in .preparing (got \(describe(controller)))")
        let ready = await waitForReady(controller, timeout: 35)
        check(ready && controller.status == .ready, "status == .ready (got \(describe(controller)))")
        check(controller.pipeline == .remux, "pipeline == remux")
        if let playlistURL = controller.debugPlaylistURL {
            info("AVPlayer HLS URL: \(playlistURL.absoluteString)")
            check(playlistURL.absoluteString.hasPrefix("http://127.0.0.1:"),
                  "HLS playlist served from loopback HTTP")
            if let playlistPort = playlistURL.port.flatMap({ UInt16($0) }) {
                let lsof = listeningInfo(port: playlistPort)
                check(lsof.contains("127.0.0.1"), "HLS server listens on loopback only: \(lsof)")
            }
        } else {
            check(false, "debugPlaylistURL available")
        }
        if let playlist = controller.debugPlaylistURL?.absoluteString {
            let headers = fetchHeaders(playlist).lowercased()
            info("playlist headers: \(headers.replacingOccurrences(of: "\r\n", with: " | "))")
            check(headers.contains("200 ok"), "HLS playlist responds 200")
            check(headers.contains("content-type: application/vnd.apple.mpegurl"),
                  "playlist Content-Type is application/vnd.apple.mpegurl")
            check(headers.contains("cache-control: no-cache"), "playlist Cache-Control: no-cache")
            check(headers.contains("accept-ranges: bytes"), "server advertises byte ranges")

            let body = runCaptured("/usr/bin/curl", ["-sS", "--max-time", "5", playlist]).stdout
            let segmentNames = body.split(separator: "\n").map(String.init)
                .filter { !$0.hasPrefix("#") && $0.hasSuffix(".m4s") }
            check(!segmentNames.isEmpty, "playlist lists fMP4 segments (\(segmentNames.count))")
            if let firstSegment = segmentNames.first, let base = URL(string: playlist),
               let segmentURL = URL(string: firstSegment, relativeTo: base)?.absoluteString {
                let segmentHeaders = fetchHeaders(segmentURL).lowercased()
                check(segmentHeaders.contains("content-type: video/iso.segment"),
                      "segment Content-Type is video/iso.segment")
            }
            if let base = URL(string: playlist),
               let initURL = URL(string: "init.mp4", relativeTo: base)?.absoluteString {
                let initHeaders = fetchHeaders(initURL).lowercased()
                check(initHeaders.contains("content-type: video/mp4"),
                      "init segment Content-Type is video/mp4")
            }
            let verbose = runCaptured("/usr/bin/curl", ["-sS", "-v", "--http1.1", "--max-time", "5",
                                                        "-o", "/dev/null", "-o", "/dev/null",
                                                        playlist, playlist]).stderr.lowercased()
            check(verbose.contains("re-using existing connection"),
                  "HTTP keep-alive: one connection reused for two requests")
        }
        await monitor(controller, seconds: 4, label: "mkv")

        let advanced = await waitUntil(15) { controller.currentTime > 2.0 }
        check(advanced, "currentTime advanced to \(formatTime(controller.currentTime))")
        let t0 = controller.currentTime
        await sleep(2.0)
        let t1 = controller.currentTime
        check(t1 > t0 + 1.2, "remux currentTime advances over 2s: \(formatTime(t0)) -> \(formatTime(t1))")
        check(controller.isPlaying, "remux isPlaying == true")
        let durationKnown = await waitUntil(10) { controller.duration > 30 }
        check(durationKnown, "full duration probed (~40s, got \(formatTime(controller.duration)))")
        check(!controller.bufferedRanges.isEmpty, "remux bufferedRanges populated: \(describe(controller))")

        // Seek inside the already-remuxed window: plain AVPlayer seek, no restart.
        let beforeSeekStatus = controller.status
        controller.seek(to: 2)
        await waitUntil(6) { abs(controller.currentTime - 2) < 1.5 }
        check(abs(controller.currentTime - 2) < 1.5,
              "in-window seek(to: 2) landed at \(formatTime(controller.currentTime))")
        check(controller.status == beforeSeekStatus && controller.pipeline == .remux,
              "in-window seek kept the session (status=\(controller.status), pipeline=\(controller.pipeline.rawValue))")

        // Seek far into the timeline. A local file is remuxed almost instantly, so at this point
        // the whole window is already available and AVPlayer serves the seek; the ffmpeg-restart
        // path for a window that is still being produced is exercised in Tests/player/run.sh's
        // deterministic "farseek" phase (throttled remux).
        controller.seek(to: 30)
        await waitUntil(10) { abs(controller.currentTime - 30) < 3 }
        check(abs(controller.currentTime - 30) < 3,
              "far seek(to: 30) landed at \(formatTime(controller.currentTime))")
        check(controller.pipeline == .remux, "still on the remux pipeline after far seek")
        let s0 = controller.currentTime
        await sleep(2.0)
        let s1 = controller.currentTime
        check(s1 > s0 + 0.8, "playback continues after far seek: \(formatTime(s0)) -> \(formatTime(s1))")
        await monitor(controller, seconds: 2, label: "mkv-farseek")

        let playlistPort = controller.debugPlaylistURL?.port.flatMap { UInt16($0) }
        let sessionDirectory = controller.debugSessionDirectory
        controller.stop()
        check(sessionDirectory != nil, "remux session directory tracked for cleanup")
        await cleanupCheck(label: "after mkv stop", sessionDirectory: sessionDirectory)
        if let playlistPort {
            await waitUntil(5) { !portIsOpen(playlistPort) }
            check(!portIsOpen(playlistPort), "remux HLS server port \(playlistPort) closed after stop")
        }
    }

    // MARK: Automatic fallback

    func fallbackTests(port: UInt16) async {
        section("3) auto-fallback: source labelled mp4 but Matroska → remux pipeline")
        // AVPlayer can not open this; the engine must fall back to the remux pipeline automatically.
        let source = MediaSource(id: 301, quality: "720p", type: "mp4",
                                 url: "http://127.0.0.1:\(port)/sample.mkv")
        let controller = PlaybackController(request: PlaybackRequest(title: "تست بازگشتی", sources: [source]))
        attach(controller)
        check(controller.pipeline == .direct, "starts on the direct pipeline")
        let switched = await waitUntil(14) { controller.pipeline == .remux }
        check(switched, "fell back to remux pipeline (got \(describe(controller)))")
        let ready = await waitForReady(controller, timeout: 40)
        check(ready && controller.status == .ready, "fallback playback ready (got \(describe(controller)))")
        let advanced = await waitUntil(12) { controller.currentTime > 2.0 }
        check(advanced, "fallback playback advances: \(formatTime(controller.currentTime))")
        let sessionDirectory = controller.debugSessionDirectory
        controller.stop()
        await cleanupCheck(label: "after fallback", sessionDirectory: sessionDirectory)
    }

    // MARK: Error states

    func errorTests(port: UInt16) async {
        section("4) error path: missing mkv source → Persian error state")
        let source = MediaSource(id: 401, quality: nil, type: "mkv",
                                 url: "http://127.0.0.1:\(port)/does-not-exist.mkv")
        let controller = PlaybackController(request: PlaybackRequest(title: "تست خطا", sources: [source]))
        attach(controller)
        let failed = await waitUntil(30) {
            if case .failed = controller.status { return true }
            return false
        }
        let message: String
        if case .failed(let text) = controller.status { message = text } else { message = "" }
        check(failed, "status == .failed (got \(describe(controller)))")
        check(!message.isEmpty && containsPersian(message),
              "failure message is Persian: \"\(message)\"")
        check(!controller.isPlaying, "not playing after failure")
        if let failedSessionDirectory = controller.debugSessionDirectory {
            await waitUntil(6) { !FileManager.default.fileExists(atPath: failedSessionDirectory.path) }
            check(!FileManager.default.fileExists(atPath: failedSessionDirectory.path),
                  "error path deleted its remux temp dir promptly")
        }
        check(ffmpegRemnants().isEmpty, "error path stopped ffmpeg promptly")
        controller.stop()
        await cleanupCheck(label: "after error path")
    }

    // MARK: Source switching

    func sourceSwitchingTests(port: UInt16) async {
        section("5) source switching (mp4 → mkv)")
        let directSource = MediaSource(id: 701, quality: "720p", type: "mp4",
                                       url: "http://127.0.0.1:\(port)/sample.mp4")
        let remuxSource = MediaSource(id: 702, quality: "1080p", type: "mkv",
                                      url: "http://127.0.0.1:\(port)/sample.mkv")
        let controller = PlaybackController(request: PlaybackRequest(title: "تست سورس", sources: [directSource, remuxSource]))
        attach(controller)
        check(controller.selectedSourceID == 701, "initial selectedSourceID == 701")
        check(controller.sources.count == 2, "both sources exposed to the UI")
        let firstReady = await waitForReady(controller, timeout: 20)
        check(firstReady && controller.status == .ready && controller.pipeline == .direct,
              "first source (mp4) ready directly (got \(describe(controller)))")

        controller.selectSource(remuxSource)
        check(controller.selectedSourceID == 702, "selectedSourceID updated to 702")
        let switched = await waitUntil(10) { controller.pipeline == .remux }
        check(switched, "selectSource(mkv) switched to remux pipeline (got \(describe(controller)))")
        let remuxReady = await waitForReady(controller, timeout: 35)
        check(remuxReady && controller.status == .ready, "switched source ready (got \(describe(controller)))")
        let advanced = await waitUntil(12) { controller.currentTime > 1.5 }
        check(advanced, "switched source advances: \(formatTime(controller.currentTime))")
        let sessionDirectory = controller.debugSessionDirectory
        controller.stop()
        await cleanupCheck(label: "after source switch", sessionDirectory: sessionDirectory)
    }

    // MARK: Automatic source failover

    func failoverTests(port: UInt16) async {
        section("8) auto-failover: a dead source moves on to the next one")
        let request = PlaybackRequest(title: "تست جابه‌جایی", sources: [
            MediaSource(id: 901, quality: "1080p", type: "mp4", url: "http://127.0.0.1:\(port)/missing-1.mp4"),
            MediaSource(id: 902, quality: "720p", type: "mp4", url: "http://127.0.0.1:\(port)/missing-2.mp4"),
            MediaSource(id: 903, quality: "480p", type: "mp4", url: "http://127.0.0.1:\(port)/sample.mp4"),
        ])
        let bad1 = request.sources[0].url
        let bad2 = request.sources[1].url

        let first = PlaybackController(request: request)
        attach(first)
        check(first.selectedSourceID == 901, "the walk starts at the preferred source")
        let rotated = await waitUntil(90) { first.selectedSourceID == 903 }
        check(rotated, "rotated to the third source (selected=\(String(describing: first.selectedSourceID)))")
        let ready = await waitForReady(first, timeout: 30)
        check(ready && first.status == .ready, "failover playback ready (got \(describe(first)))")
        let advanced = await waitUntil(12) { first.currentTime > 1.5 }
        check(advanced, "failover playback advances: \(formatTime(first.currentTime))")
        check(LinkHealth.failureCount(for: bad1) >= 1, "the dead 1080p link is counted as failed")
        check(LinkHealth.failureCount(for: bad2) >= 1, "the dead 720p link is counted as failed")
        check(LinkHealth.failureCount(for: request.sources[2].url) == 0, "the link that played stays clean")
        first.stop()
        await cleanupCheck(label: "after failover")

        // A second session fails the same two links again, which is enough to deprioritize them.
        let second = PlaybackController(request: request)
        attach(second)
        _ = await waitUntil(90) { second.selectedSourceID == 903 }
        check(LinkHealth.failureCount(for: bad1) >= 2, "repeat failures raise the dead-link count")
        check(LinkHealth.isDeprioritized(bad1), "the twice-dead link is now tried last")
        second.stop()
        await cleanupCheck(label: "after the second failover run")

        // Third session: the known-dead links sit at the back, so the good source plays at once.
        let third = PlaybackController(request: request)
        attach(third)
        check(third.selectedSourceID == 903, "a new session starts on the remembered-good source")
        let quick = await waitForReady(third, timeout: 25)
        check(quick && third.status == .ready, "the remembered-good source plays directly")
        third.stop()
        await cleanupCheck(label: "after the third failover run")

        // Nothing works: the exhausted walk ends in one Persian failure instead of a silent stop.
        let hopeless = PlaybackController(request: PlaybackRequest(title: "تست بن‌بست", sources: Array(request.sources.dropLast())))
        attach(hopeless)
        let failed = await waitUntil(120) {
            if case .failed = hopeless.status { return true }
            return false
        }
        let message: String
        if case .failed(let text) = hopeless.status { message = text } else { message = "" }
        check(failed, "exhausted sources end in .failed (got \(describe(hopeless)))")
        check(!message.isEmpty && containsPersian(message),
              "exhaustion message is Persian: \"\(message)\"")
        check(!hopeless.isPlaying, "not playing after every source failed")
        hopeless.stop()
        await cleanupCheck(label: "after exhausted sources")
    }

    // MARK: Network and stall recovery

    func networkRecoveryTests(port: UInt16) async {
        section("9) network drop → waits, and rejoins by itself when the connection returns")
        let source = MediaSource(id: 911, quality: "720p", type: "mp4",
                                 url: "http://127.0.0.1:\(port)/sample.mp4")
        let controller = PlaybackController(request: PlaybackRequest(title: "قطع و وصل شبکه",
                                                                     sources: [source]))
        attach(controller)
        let readyBefore = await waitForReady(controller, timeout: 35)
        check(readyBefore && controller.status == .ready,
              "playing before the drop (got \(describe(controller)))")
        _ = await waitUntil(10) { controller.currentTime > 2 }

        ConnectionWatch.shared.simulate(connected: false)
        let marked = await waitUntil(5, { preparingMessage(controller).contains("قطع") })
        check(marked, "a drop is reported as a wait, not a dead link: \"\(preparingMessage(controller))\"")

        ConnectionWatch.shared.simulate(connected: true)
        let rejoined = await waitUntil(8) {
            preparingMessage(controller).contains("ازسرگیری") || controller.status == .ready
        }
        check(rejoined, "the player reloads on its own once the connection is back")
        let readyAgain = await waitForReady(controller, timeout: 35)
        check(readyAgain && controller.status == .ready,
              "playback is ready after the reconnect (got \(describe(controller)))")
        let running = await waitUntil(15) { controller.currentTime > 4 }
        check(running, "time advances after the reconnect: \(formatTime(controller.currentTime))")
        check(LinkHealth.failureCount(for: source.url) == 0,
              "a network blip is not blamed on the link itself")
        controller.stop()
        await cleanupCheck(label: "after the network test")
    }

    // MARK: Stall watchdog

    /// A progressive download is buffered whole by AVPlayer (it asks for the entire byte range), so
    /// only a throttled remux leaves the player at the live edge — the one setup where killing
    /// ffmpeg genuinely runs the buffer dry and the stall watchdog has to act.
    func stallRecoveryTests() async {
        section("11) ffmpeg killed at the live edge → stall watchdog reloads, playback resumes")
        guard ProcessInfo.processInfo.environment["CCLOUD_REMUX_THROTTLE"] == "1" else {
            check(false, "the stall phase needs CCLOUD_REMUX_THROTTLE=1")
            return
        }
        let mkv = options.mediaDir.appendingPathComponent("sample.mkv")
        let source = MediaSource(id: 931, quality: "1080p", type: "mkv", url: mkv.absoluteString)
        let controller = PlaybackController(request: PlaybackRequest(title: "قطع موتور تبدیل",
                                                                     sources: [source]))
        attach(controller)
        let ready = await waitForReady(controller, timeout: 60)
        check(ready && controller.status == .ready,
              "throttled remux is playing (got \(describe(controller)))")
        let rolling = await waitUntil(40) { controller.pipeline == .remux && controller.currentTime > 4 }
        check(rolling, "playback advances before the kill: \(formatTime(controller.currentTime))")
        let beforeKill = controller.currentTime

        let kill = runCaptured("/usr/bin/pkill", ["-9", "-f", "ffmpeg.*CCloudRemux-"])
        check(kill.status == 0, "ffmpeg was terminated mid-playback")

        // Both signs are transient: the reload note lasts only until the first segment lands, and the
        // clip runs out 40s later, so one tight loop has to catch the restart and the resumed clock.
        var sawReload = false
        var reloadNote = ""
        var resumed = false
        _ = await waitUntil(70) {
            let note = preparingMessage(controller)
            if note.contains("ازسرگیری") { sawReload = true; reloadNote = note }
            if controller.isPlaying && controller.currentTime > beforeKill + 2 { resumed = true }
            return sawReload && resumed
        }
        check(sawReload, "a stream that dies mid-play reloads the same source: \"\(reloadNote)\"")
        check(controller.selectedSourceID == 931, "the reload stays on the same source instead of giving up")
        check(resumed, "playback continues past the stall point: \(formatTime(controller.currentTime)) after \(formatTime(beforeKill))")
        let recovered = await waitUntil(15) { controller.status == .ready }
        check(recovered, "the recovered session reports ready (\(describe(controller)))")
        await monitor(controller, seconds: 5, label: "stall-recovered")
        controller.stop()
        await cleanupCheck(label: "after the stall test")
    }

    func stallPhaseRun() async -> Int32 {
        print("== CCloud playback engine harness (stall phase) ==")
        print("ffmpeg located: \(FFmpegLocator.locate() ?? "<none>")")
        print("media dir: \(options.mediaDir.path)")
        window = makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        await stallRecoveryTests()
        print("\n== Result: \(checks - failures)/\(checks) checks passed, \(failures) failed ==")
        return failures == 0 ? 0 : 1
    }

    // MARK: Audio tracks

    func audioTrackTests() async {
        section("10) multi-audio media: every track is offered, and switching keeps playback")
        let dump = """
          Duration: 00:00:40.00, start: 0.000000, bitrate: 220 kb/s
          Stream #0:0(eng): Video: h264 (High) (avc1 / 0x31637661), yuv420p, 640x360, 90 kb/s
          Stream #0:1(eng): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 96 kb/s (default)
          Stream #0:2[0x3](spa): Audio: aac (LC), 48000 Hz, stereo, fltp, 96 kb/s
            Metadata:
              title           : Commentario
        """
        let parsed = FFmpegProbe.parseAudioStreams(in: dump)
        check(parsed.count == 2, "the input dump yields both audio streams (got \(parsed.count))")
        check(parsed.map { $0.index } == [0, 1], "audio indices are ordinals for -map 0:a:N")
        check(parsed.first?.isDefault == true, "the default marker is read")
        check(parsed.last?.language == "spa", "the second stream's language tag is read")
        check(parsed.last?.title == "Commentario", "a stream title is read from its metadata block")
        check(FFmpegProbe.parseAudioStreams(in: "Stream #0:0(eng): Video: h264").isEmpty,
              "video-only dumps list no audio")

        let dual = options.mediaDir.appendingPathComponent("dual.mkv")
        guard FileManager.default.fileExists(atPath: dual.path) else {
            check(false, "dual.mkv test media exists")
            return
        }
        let source = MediaSource(id: 941, quality: "1080p", type: "mkv", url: dual.absoluteString)
        let controller = PlaybackController(request: PlaybackRequest(title: "دو صدایی", sources: [source]))
        attach(controller)
        let ready = await waitForReady(controller, timeout: 40)
        check(ready && controller.status == .ready, "dual-audio mkv plays (got \(describe(controller)))")

        let listed = await waitUntil(25) { controller.audioTracks.count == 2 }
        check(listed, "both audio tracks are offered: \(controller.audioTracks.map { $0.label })")
        let labels = controller.audioTracks.map { $0.label }
        check(labels.contains("انگلیسی") && labels.contains("اسپانیایی"),
              "track names are Persian: \(labels)")
        check(controller.selectedAudioTrackID != nil, "one track is marked current")
        _ = await waitUntil(15) { controller.currentTime > 2 }

        let other = controller.audioTracks.first { $0.id != controller.selectedAudioTrackID }
        // Leave the whole clip ahead of the switch: a remux restart needs runway to prove it continued.
        controller.seek(to: 3)
        _ = await waitUntil(8) { abs(controller.currentTime - 3) < 2 }
        let beforeSwitch = controller.currentTime
        controller.selectAudioTrack(other?.id ?? "")
        check(controller.selectedAudioTrackID == other?.id, "the new pick is the current track")
        let index = Int(other?.id.dropFirst() ?? "") ?? -1
        let remapped = await waitUntil(30) {
            controller.debugFFmpegArguments?.contains { $0.hasPrefix("0:a:\(index)") } == true
        }
        check(remapped, "ffmpeg restarted with -map 0:a:\(index): \(controller.debugFFmpegArguments ?? [])")
        let continued = await waitUntil(60) { controller.isPlaying && controller.currentTime > beforeSwitch + 1 }
        check(continued, "playback continues on the other track: \(formatTime(controller.currentTime)) after \(formatTime(beforeSwitch))")
        let stillReady = await waitUntil(20) { controller.status == .ready }
        check(stillReady, "the controller returns to ready after the switch")
        controller.stop()
        await cleanupCheck(label: "after the audio switch")

        // The direct AVPlayer path selects in place, without touching ffmpeg.
        let dualMP4 = MediaSource(id: 945, quality: "720p", type: "mp4",
                                  url: options.mediaDir.appendingPathComponent("dual.mp4").absoluteString)
        let direct = PlaybackController(request: PlaybackRequest(title: "دو صدایی مستقیم", sources: [dualMP4]))
        attach(direct)
        let directReady = await waitForReady(direct, timeout: 25)
        check(directReady && direct.pipeline == .direct, "dual-audio mp4 plays directly")
        let directListed = await waitUntil(20) { direct.audioTracks.count == 2 }
        check(directListed, "AVPlayer's own options are listed: \(direct.audioTracks.map { $0.label })")
        let directOther = direct.audioTracks.first { $0.id != direct.selectedAudioTrackID }
        direct.selectAudioTrack(directOther?.id ?? "")
        check(direct.selectedAudioTrackID == directOther?.id, "the direct pick is applied")
        _ = await waitUntil(15) { direct.isPlaying && direct.currentTime > 2 }
        check(direct.debugFFmpegArguments == nil, "switching audio directly never starts ffmpeg")
        direct.stop()
        await cleanupCheck(label: "after the direct audio switch")

        // Single-track media must not grow a menu.
        let single = MediaSource(id: 951, quality: "720p", type: "mp4",
                                 url: options.mediaDir.appendingPathComponent("sample.mp4").absoluteString)
        let plain = PlaybackController(request: PlaybackRequest(title: "تک‌صدایی", sources: [single]))
        attach(plain)
        let plainReady = await waitForReady(plain, timeout: 25)
        check(plainReady && plain.status == .ready, "single-audio mp4 plays")
        await sleep(2)
        check(plain.audioTracks.isEmpty, "a one-track title offers no audio menu (got \(plain.audioTracks.map { $0.label }))")
        plain.stop()
        await cleanupCheck(label: "after the single-audio check")
    }

    // MARK: file:// (used by the app's local QA demo hook)

    func fileURLTests() async {
        section("6) local file:// sources (QA demo hook)")
        let mp4 = options.mediaDir.appendingPathComponent("sample.mp4")
        let mkv = options.mediaDir.appendingPathComponent("sample.mkv")

        let directSource = MediaSource(id: 501, quality: "720p", type: "mp4", url: mp4.absoluteString)
        let direct = PlaybackController(request: PlaybackRequest(title: "فایل MP4", sources: [directSource]))
        attach(direct)
        let directReady = await waitForReady(direct, timeout: 15)
        check(directReady && direct.status == .ready, "file:// mp4 ready (got \(describe(direct)))")
        let directAdvanced = await waitUntil(10) { direct.currentTime > 1.5 }
        check(directAdvanced, "file:// mp4 currentTime advances: \(formatTime(direct.currentTime))")
        check(direct.pipeline == .direct, "file:// mp4 uses direct pipeline")
        direct.stop()
        await cleanupCheck(label: "after file:// mp4")

        let remuxSource = MediaSource(id: 502, quality: "1080p", type: "mkv", url: mkv.absoluteString)
        let remux = PlaybackController(request: PlaybackRequest(title: "فایل MKV", sources: [remuxSource]))
        attach(remux)
        let remuxReady = await waitForReady(remux, timeout: 35)
        check(remuxReady && remux.status == .ready, "file:// mkv ready via remux (got \(describe(remux)))")
        check(remux.pipeline == .remux, "file:// mkv uses remux pipeline")
        let remuxAdvanced = await waitUntil(15) { remux.currentTime > 1.5 }
        check(remuxAdvanced, "file:// mkv currentTime advances: \(formatTime(remux.currentTime))")
        let sessionDirectory = remux.debugSessionDirectory
        remux.stop()
        await cleanupCheck(label: "after file:// mkv", sessionDirectory: sessionDirectory)
    }

    // MARK: Far-seek restart phase (throttled remux, CCLOUD_REMUX_THROTTLE=1)

    /// Deterministically exercises far-seek restart: `-re` makes ffmpeg produce segments in real
    /// time (like a slow network CDN), so a seek beyond the produced window must restart ffmpeg.
    func farseekPhaseRun() async -> Int32 {
        section("7) far seek beyond the produced remux window → ffmpeg restart")
        window = makeWindow()
        NSApp.activate(ignoringOtherApps: true)

        let mediaServer = HLSServer(root: options.mediaDir) { line in
            print("[media-server] \(line)")
        }
        mediaServer.start()
        guard await waitUntil(8, { mediaServer.port != 0 }) else {
            print("FATAL: media HTTP server did not start")
            return 1
        }
        let port = mediaServer.port
        info("media server: http://127.0.0.1:\(port)/")
        info("throttled remux: \(ProcessInfo.processInfo.environment["CCLOUD_REMUX_THROTTLE"] ?? "0")")

        let source = MediaSource(id: 701, quality: "1080p", type: "mkv",
                                 url: "http://127.0.0.1:\(port)/sample.mkv")
        let controller = PlaybackController(request: PlaybackRequest(title: "تست پرش دور", sources: [source]))
        attach(controller)

        let ready = await waitForReady(controller, timeout: 40)
        check(ready && controller.status == .ready, "throttled remux ready (got \(describe(controller)))")
        check(controller.pipeline == .remux, "pipeline == remux")
        info("initial ffmpeg args: \((controller.debugFFmpegArguments ?? []).joined(separator: " "))")
        check((controller.debugFFmpegArguments ?? []).contains("-re"),
              "test session uses -re throttling")

        let advanced = await waitUntil(15) { controller.currentTime > 1.5 }
        check(advanced, "throttled playback advancing: \(formatTime(controller.currentTime))")

        // The produced window is at most ~2 segments behind real time; 3s is inside it.
        controller.seek(to: 3)
        await waitUntil(6) { abs(controller.currentTime - 3) < 1.5 }
        check(abs(controller.currentTime - 3) < 1.5,
              "in-window seek(to: 3) landed at \(formatTime(controller.currentTime))")
        check(!controller.status.isPreparing, "in-window seek did not restart ffmpeg")

        // The event playlist is written incrementally (ffmpeg at 1x due to -re). AVPlayer must
        // reload it and keep playing past the two segments that existed when the item was created.
        let grew = await waitUntil(30) { controller.currentTime > 12 }
        check(grew, "AVPlayer plays past the initial 2-segment window (playlist growth): t=\(formatTime(controller.currentTime))")
        check(controller.bufferedEnd > 15,
              "progressive timeline: bufferedEnd=\(formatTime(controller.bufferedEnd)) dur=\(formatTime(controller.duration))")
        check(!controller.status.isPreparing, "no restart while consuming appended segments")

        controller.seek(to: 30)
        let restarting = await waitUntil(6) { controller.status.isPreparing }
        check(restarting, "far seek(to: 30) enters .preparing restart (got \(describe(controller)))")
        let sawSeek = await waitUntil(10) { (controller.debugFFmpegArguments ?? []).contains("30.000") }
        let arguments = controller.debugFFmpegArguments ?? []
        info("restart ffmpeg args: \(arguments.joined(separator: " "))")
        check(sawSeek, "restart command seeks to 30.000s")
        check(arguments.contains("-ss"), "restart uses input seek (-ss)")
        check(arguments.contains("-i"), "restart still reads the same source")

        let readyAgain = await waitForReady(controller, timeout: 40)
        check(readyAgain && controller.status == .ready, "restart ready again (got \(describe(controller)))")
        let atTarget = await waitUntil(12) { controller.currentTime > 29.0 }
        check(atTarget, "displayed timeline offset after restart: \(formatTime(controller.currentTime)) ≈ 30s")
        let s0 = controller.currentTime
        await sleep(2.0)
        let s1 = controller.currentTime
        check(s1 > s0 + 0.8, "playback continues after restart: \(formatTime(s0)) -> \(formatTime(s1))")
        await monitor(controller, seconds: 2, label: "farseek")

        let playlistPort = controller.debugPlaylistURL?.port.flatMap { UInt16($0) }
        let sessionDirectory = controller.debugSessionDirectory
        controller.stop()
        await cleanupCheck(label: "after far-seek stop", sessionDirectory: sessionDirectory)
        if let playlistPort {
            await waitUntil(5) { !portIsOpen(playlistPort) }
            check(!portIsOpen(playlistPort), "restarted HLS server port \(playlistPort) closed after stop")
        }
        mediaServer.stop()
        await waitUntil(5) { !portIsOpen(port) }
        check(!portIsOpen(port), "media server port closed after stop")

        print("\n== Result: \(checks - failures)/\(checks) checks passed, \(failures) failed ==")
        return failures == 0 ? 0 : 1
    }

    // MARK: Deinit cleanup

    func deinitCleanupTests() async {
        section("7) deinit cleanup (no explicit stop())")
        let source = MediaSource(id: 801, quality: "1080p", type: "mkv",
                                 url: "file://\(options.mediaDir.appendingPathComponent("sample.mkv").path)")
        var controller: PlaybackController? = PlaybackController(
            request: PlaybackRequest(title: "تست آزادسازی", sources: [source]))
        attach(controller!)
        let ready = await waitForReady(controller!, timeout: 35)
        check(ready && controller!.status == .ready, "controller ready for deinit test (got \(describe(controller!)))")
        let sessionDirectory = controller?.debugSessionDirectory
        check(sessionDirectory != nil, "remux session tracked before deinit")
        controller = nil // deinit must terminate ffmpeg, close the server and delete the temp dir
        await waitUntil(8) {
            ffmpegRemnants().isEmpty && (sessionDirectory.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false)
        }
        check(ffmpegRemnants().isEmpty, "deinit terminated ffmpeg")
        if let sessionDirectory {
            check(!FileManager.default.fileExists(atPath: sessionDirectory.path),
                  "deinit deleted remux temp dir")
        }
        await cleanupCheck(label: "after deinit")
    }

    // MARK: Missing ffmpeg

    func missingFFmpegScenario() async -> Int32 {
        section("6) ffmpeg missing → clear Persian error")
        let source = MediaSource(id: 601, quality: "1080p", type: "mkv",
                                 url: "file:///nonexistent/sample.mkv")
        let controller = PlaybackController(request: PlaybackRequest(title: "بدون ffmpeg", sources: [source]))
        let failed = await waitUntil(10) {
            if case .failed = controller.status { return true }
            return false
        }
        let message: String
        if case .failed(let text) = controller.status { message = text } else { message = "" }
        check(failed, "status == .failed without ffmpeg (got \(describe(controller)))")
        check(message.contains("ffmpeg") && containsPersian(message),
              "message mentions ffmpeg and is Persian: \"\(message)\"")
        check(ffmpegRemnants().isEmpty, "no ffmpeg process started without ffmpeg")
        controller.stop()
        print("\n== Result: \(checks - failures)/\(checks) checks passed, \(failures) failed ==")
        return failures == 0 ? 0 : 1
    }

    // MARK: Cleanup assertions

    @discardableResult
    func cleanupCheck(label: String, sessionDirectory: URL? = nil) async -> Bool {
        section("cleanup: \(label)")
        if let sessionDirectory {
            await waitUntil(6) {
                ffmpegRemnants().isEmpty && !FileManager.default.fileExists(atPath: sessionDirectory.path)
            }
            let processes = ffmpegRemnants()
            let dirGone = !FileManager.default.fileExists(atPath: sessionDirectory.path)
            check(processes.isEmpty, "no ffmpeg remux process left (\(processes.joined(separator: " ; ")))")
            check(dirGone, "remux temp dir deleted: \(sessionDirectory.lastPathComponent)")
            return processes.isEmpty && dirGone
        }
        await waitUntil(6) { ffmpegRemnants().isEmpty && remuxTempDirs().isEmpty }
        let processes = ffmpegRemnants()
        let dirs = remuxTempDirs()
        check(processes.isEmpty, "no ffmpeg remux process left (\(processes.joined(separator: " ; ")))")
        check(dirs.isEmpty, "no harness remux temp dir left (\(dirs.joined(separator: " ; ")))")
        return processes.isEmpty && dirs.isEmpty
    }
}

// MARK: - App bootstrap

final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
    let options: HarnessOptions

    init(options: HarnessOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let harness = PlayerHarness(options: options)
            let code = await harness.run()
            print("\nharness exit code: \(code)")
            fflush(stdout)
            exit(code)
        }
    }
}

// MARK: - Main

let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
var options = HarnessOptions(missingFFmpeg: false,
                             mediaDir: workingDirectory.appendingPathComponent("Tests/player/out/media"),
                             outDir: workingDirectory.appendingPathComponent("Tests/player/out"))
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let argument = iterator.next() {
    switch argument {
    case "--missing-ffmpeg":
        options.missingFFmpeg = true
    case "--phase":
        if let value = iterator.next() { options.phase = value }
    case "--media-dir":
        if let value = iterator.next() { options.mediaDir = URL(fileURLWithPath: value, isDirectory: true) }
    case "--out-dir":
        if let value = iterator.next() { options.outDir = URL(fileURLWithPath: value, isDirectory: true) }
    default:
        break
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = HarnessAppDelegate(options: options)
application.delegate = delegate
application.run()
