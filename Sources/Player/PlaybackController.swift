import Foundation
import AVKit
import SwiftUI
import AppKit
import Combine

// MARK: - Public state types

enum PlaybackStatus: Equatable {
    case idle
    case preparing(String)
    case ready
    case failed(String)

    var isPreparing: Bool {
        if case .preparing = self { return true }
        return false
    }
    var isReady: Bool { self == .ready }
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
    var message: String? {
        switch self {
        case .preparing(let m): return m
        case .failed(let m): return m
        default: return nil
        }
    }
}

/// One audio track the viewer can pick when the media carries more than one.
struct PlaybackAudioTrack: Identifiable, Hashable {
    let id: String
    let label: String
    let isDefault: Bool
}

/// Which pipeline currently feeds the player. Exposed so the UI can show a "converting" badge.
enum PlaybackPipeline: String, Equatable {
    case none
    case direct
    case remux

    var title: String {
        switch self {
        case .none: return ""
        case .direct: return "پخش مستقیم"
        case .remux: return "تبدیل زنده"
        }
    }
}

// MARK: - Controller

/// Playback engine for one `PlaybackRequest`.
///
/// - mp4 / m3u8 / mpd sources play directly in `AVPlayer`.
/// - mkv (and any source AVPlayer can not open) is remuxed by ffmpeg into fMP4 HLS inside a
///   temp directory and served to AVPlayer by a loopback-only `HLSServer`.
/// - Seeking inside the already-remuxed window is a zero-tolerance `AVPlayer.seek`; seeking
///   farther restarts ffmpeg at the target (`-ss`) in a fresh session while the displayed
///   timeline is offset by that base time.
/// - If a direct source is not ready within 8 seconds, the engine falls back to the remux pipeline.
/// - Sources are walked one after another: a link that errors moves straight to the next source,
///   a link that is merely slow is remuxed first, and links that already failed in earlier sessions
///   start at the back of the queue (`LinkHealth`).
/// - A stream that had begun playing and then stalls is reloaded on the same source before the walk
///   moves on, and a dropped connection re-joins by itself once the network is back.
///
/// `PlaybackController` is `@MainActor`; all published state is main-thread only.
@MainActor
final class PlaybackController: ObservableObject {
    let request: PlaybackRequest
    let player: AVPlayer

    @Published private(set) var status: PlaybackStatus = .idle
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isBuffering = false
    @Published private(set) var sources: [MediaSource]
    @Published private(set) var selectedSourceID: Int?
    /// Absolute timeline seconds covered by media that is already local/available.
    @Published private(set) var bufferedRanges: [ClosedRange<Double>] = []
    /// End of the last buffered range, absolute timeline seconds.
    @Published private(set) var bufferedEnd: Double = 0
    /// Active playback pipeline (`direct`, `remux` or `none`).
    @Published private(set) var pipeline: PlaybackPipeline = .none
    /// Set when the current item plays to its end (drives autoplay-next).
    @Published private(set) var didReachEnd = false
    /// Alternate audio of the title on screen; empty when there is only one track.
    @Published private(set) var audioTracks: [PlaybackAudioTrack] = []
    @Published private(set) var selectedAudioTrackID: String?

    @Published var volume: Double = 0.85 {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume {
                volume = clamped
                return
            }
            player.volume = Float(clamped)
        }
    }

    @Published var rate: Float = 1.0 {
        didSet {
            let clamped = min(max(rate, 0.5), 2.0)
            if clamped != rate {
                rate = clamped
                return
            }
            if isPlaying {
                player.rate = clamped
            }
        }
    }

    // MARK: Internals

    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var timeControlObservation: NSKeyValueObservation?
    private var directTimeoutTask: Task<Void, Never>?
    private var remuxSession: RemuxSession?
    private var sessionGeneration = 0
    private var currentSourceURL: URL?
    private var baseOffset: Double = 0
    private var remuxAvailable: Double = 0
    private var knownTotalDuration: Double = 0
    private var directFallbackTried = false
    private var playbackIntent = true
    private var didStartPlaying = false
    /// Start offset of the active direct item; remux consumes it through `baseOffset` instead.
    private var pendingStartAt: Double = 0
    /// Sources in attempt order for this playback: preferred quality first, burned links last.
    private var attemptOrder: [MediaSource] = []
    /// Which entry of `attemptOrder` is being attempted right now.
    private var attemptIndex = 0
    /// Reloads spent on the current source without it playing again in between.
    private var reloadTries = 0
    private var stallTask: Task<Void, Never>?
    private var connectionCancellable: AnyCancellable?
    private var networkDropped = false
    /// Audio tracks of the media selection group when AVPlayer itself picks them.
    private var directAudioGroup: AVMediaSelectionGroup?
    /// The audio stream ffmpeg should map, kept across source rotation and remux restarts.
    private var preferredAudioIndex: Int?

    /// Diagnostics (internal, used by Tests/player): the loopback HLS URL currently handed to
    /// AVPlayer while remuxing. `nil` in direct mode.
    private(set) var debugPlaylistURL: URL?
    /// Diagnostics (internal, used by Tests/player): latest ffmpeg argument list.
    private(set) var debugFFmpegArguments: [String]?
    /// Diagnostics (internal, used by Tests/player): temp directory of the active remux session.
    private(set) var debugSessionDirectory: URL?

    /// Currently selected source, if any.
    var selectedSource: MediaSource? {
        sources.first { $0.id == selectedSourceID }
    }

    /// The player surface can always be presented full screen by the UI.
    var isFullscreenCapable: Bool { true }

    // MARK: Init

    init(request: PlaybackRequest) {
        self.request = request
        self.sources = request.sources.playable
        self.player = AVPlayer()
        self.player.volume = 0.85
        self.player.actionAtItemEnd = .pause
        self.player.automaticallyWaitsToMinimizeStalling = true

        addPeriodicTimeObserver()
        observeTimeControlStatus()
        ConnectionWatch.shared.start()
        observeConnection()

        beginSession()
    }

    deinit {
        directTimeoutTask?.cancel()
        stallTask?.cancel()
        remuxSession?.stop()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    // MARK: Source walk

    /// Start (or restart) the walk through every source of this request.
    private func beginSession() {
        attemptOrder = orderedAttempts()
        attemptIndex = 0
        reloadTries = 0
        guard let first = attemptOrder.first else {
            status = .failed("سورسی برای پخش پیدا نشد")
            return
        }
        load(source: first, startAt: request.startAt)
    }

    /// Preferred quality first, then the API order, then links that failed in earlier sessions.
    private func orderedAttempts() -> [MediaSource] {
        var list = sources
        if let preferred = request.preferredSourceID,
           let index = list.firstIndex(where: { $0.id == preferred }), index != 0 {
            list.insert(list.remove(at: index), at: 0)
        }
        let fresh = list.filter { !LinkHealth.isDeprioritized($0.url) }
        let burned = list.filter { LinkHealth.isDeprioritized($0.url) }
        return fresh + burned
    }

    private var canRotate: Bool { attemptIndex + 1 < attemptOrder.count }

    private var currentAttempt: MediaSource? {
        attemptIndex < attemptOrder.count ? attemptOrder[attemptIndex] : nil
    }

    /// The current source is finished with: remember it failed, then move on when one is left.
    @discardableResult
    private func advanceAfterFailure() -> Bool {
        guard let failed = currentAttempt else { return false }
        LinkHealth.recordFailure(failed.url)
        guard canRotate else { return false }
        attemptIndex += 1
        reloadTries = 0
        let note = attemptOrder.count > 1
            ? "منبع \(PersianNumber.string(attemptIndex + 1)) از \(PersianNumber.string(attemptOrder.count)) در حال امتحان…"
            : nil
        load(source: attemptOrder[attemptIndex], startAt: resumeOffset(), note: note)
        return true
    }

    /// Live streams drop on a momentary glitch far more often than links really die, so the same
    /// source gets a couple of fresh attempts before the walk moves on.
    @discardableResult
    private func reloadInPlace() -> Bool {
        guard reloadTries < 2, let source = currentAttempt else { return false }
        reloadTries += 1
        load(source: source, startAt: resumeOffset(), note: "در حال ازسرگیری پخش…")
        return true
    }

    /// A title that had started resumes a few seconds back; a live stream restarts at the edge.
    private func resumeOffset() -> Double {
        if didStartPlaying, duration.isFinite, duration > 1 {
            return max(0, currentTime - 5)
        }
        return request.startAt
    }

    private func finalFailureMessage() -> String {
        if networkDropped || !ConnectionWatch.shared.isConnected {
            return "اتصال اینترنت قطع است؛ با برگشتن آن پخش خودکار ازسرگیری می‌شود."
        }
        if attemptOrder.count > 1 {
            return "هیچ‌کدام از \(PersianNumber.string(attemptOrder.count)) منبع این عنوان پخش نشد. "
                 + "احتمالاً لینک‌ها خراب‌اند یا به این سرورها وصل نمی‌شوید."
        }
        return "این لینک پخش نشد؛ ممکن است خراب باشد یا اتصال اینترنت قطع باشد."
    }

    // MARK: Public controls

    func play() {
        playbackIntent = true
        if player.currentItem == nil {
            if let source = currentAttempt ?? selectedSource {
                load(source: source, startAt: resumeOffset())
            } else {
                beginSession()
            }
            return
        }
        if status.isFailed {
            retry()
            return
        }
        if status.isReady || status.isPreparing {
            startPlaying()
        }
    }

    /// The failure overlay's retry: walk every source again instead of the one that just failed.
    func retry() {
        stop()
        playbackIntent = true
        beginSession()
    }

    func pause() {
        playbackIntent = false
        player.pause()
        isPlaying = false
        isBuffering = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        var target = max(0, seconds)
        if duration > 0.2 {
            target = min(target, duration - 0.05)
        }

        switch pipeline {
        case .direct:
            guard player.currentItem != nil else { return }
            currentTime = target
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        case .remux:
            let relative = target - baseOffset
            let playable = max(0, remuxAvailable - 1.0)
            if relative >= 0, relative <= playable {
                currentTime = target
                player.seek(to: CMTime(seconds: relative, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                // Already heading there (or a duplicate drag event)? Don't restart twice.
                guard abs(target - currentTime) > 0.5 else { return }
                if status.isPreparing, abs(target - baseOffset) < 1.0 { return }
                restartRemux(at: target)
            }
        case .none:
            break
        }
    }

    func selectSource(_ source: MediaSource) {
        selectedSourceID = source.id
        if source.url == currentSourceURL?.absoluteString, player.currentItem != nil {
            // Re-selecting the active source should not interrupt playback.
            if !isPlaying { play() }
            return
        }
        // A hand-picked source owns the walk: rotate onward from here, not from the automatic order.
        attemptOrder = [source] + attemptOrder.filter { $0.id != source.id }
        attemptIndex = 0
        reloadTries = 0
        load(source: source)
    }

    // MARK: Audio tracks

    /// Switch the audio the viewer hears. AVPlayer does this live; a remux has to restart ffmpeg
    /// with a different map, so the picture blinks out for a moment at the same position.
    func selectAudioTrack(_ trackID: String) {
        guard trackID != selectedAudioTrackID else { return }
        if let index = remuxAudioIndex(for: trackID) {
            preferredAudioIndex = index
            selectedAudioTrackID = trackID
            if pipeline == .remux { restartRemux(at: currentTime) }
            return
        }
        guard pipeline == .direct,
              let group = directAudioGroup,
              let number = Int(trackID.dropFirst()),
              group.options.indices.contains(number) else { return }
        player.currentItem?.select(group.options[number], in: group)
        selectedAudioTrackID = trackID
    }

    /// Lists the audible options AVPlayer offers for the item that just became ready.
    private func refreshDirectAudioTracks(_ item: AVPlayerItem) {
        guard pipeline == .direct else { return }
        audioTracks = []
        selectedAudioTrackID = nil
        directAudioGroup = nil
        Task { @MainActor [weak self] in
            guard let self, self.pipeline == .direct, item === self.player.currentItem else { return }
            let group = try? await item.asset.loadMediaSelectionGroup(for: .audible)
            guard let group, group.options.count > 1,
                  item === self.player.currentItem else { return }
            self.directAudioGroup = group
            self.audioTracks = group.options.enumerated().map { offset, option in
                PlaybackAudioTrack(id: "d\(offset)",
                                   label: Self.audioLabel(name: option.displayName,
                                                          language: Self.languageCode(of: option.locale),
                                                          ordinal: offset),
                                   isDefault: option == group.defaultOption)
            }
            let selected = item.currentMediaSelection.selectedMediaOption(in: group)
            if let selected, let index = group.options.firstIndex(of: selected) {
                self.selectedAudioTrackID = "d\(index)"
            } else {
                self.selectedAudioTrackID = self.audioTracks.first?.id
            }
        }
    }

    /// Audio streams found in ffmpeg's input dump for the remux pipeline.
    private func refreshRemuxAudioTracks(_ streams: [FFmpegProbe.AudioStream]) {
        guard streams.count > 1 else { return }
        audioTracks = streams.map { stream in
            PlaybackAudioTrack(id: "r\(stream.index)",
                               label: Self.audioLabel(name: stream.title,
                                                      language: stream.language,
                                                      ordinal: stream.index),
                               isDefault: stream.isDefault)
        }
        // ffmpeg already muxed its way here; the mark must match what the viewer actually hears,
        // not whatever the container calls its favourite stream.
        let wanted = preferredAudioIndex ?? 0
        selectedAudioTrackID = audioTracks.contains { $0.id == "r\(wanted)" } ? "r\(wanted)" : audioTracks.first?.id
    }

    private func remuxAudioIndex(for trackID: String) -> Int? {
        guard trackID.hasPrefix("r"), let index = Int(trackID.dropFirst()) else { return nil }
        return audioTracks.contains { $0.id == trackID } ? index : nil
    }

    /// Persian where the media tells us a language, its own label otherwise.
    private static func audioLabel(name: String?, language: String?, ordinal: Int) -> String {
        if let language {
            // "fa-IR" and "fas" both mean Persian to the catalogue's table.
            let code = language.lowercased().split(whereSeparator: { "-_ ".contains($0) }).first.map(String.init) ?? ""
            let persian = LiveTVLanguage.persian(code)
            if !code.isEmpty, persian != code { return persian }
        }
        if let name, !name.isEmpty { return name }
        return "صدای " + PersianNumber.string(ordinal + 1)
    }

    private static func languageCode(of locale: Locale?) -> String? {
        locale?.language.languageCode?.identifier
    }

    func stop() {
        playbackIntent = false
        directTimeoutTask?.cancel()
        directTimeoutTask = nil
        cancelStallCheck()
        teardownPipeline()
        sessionGeneration += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentSourceURL = nil
        baseOffset = 0
        remuxAvailable = 0
        knownTotalDuration = 0
        didStartPlaying = false
        directFallbackTried = false
        pendingStartAt = 0
        didReachEnd = false
        status = .idle
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
        bufferedRanges = []
        bufferedEnd = 0
        pipeline = .none
    }

    // MARK: Source loading

    private func load(source: MediaSource, startAt: Double = 0, note: String? = nil) {
        teardownPipeline()
        selectedSourceID = source.id
        player.replaceCurrentItem(with: nil)
        directFallbackTried = false
        didStartPlaying = false
        didReachEnd = false
        playbackIntent = true
        baseOffset = 0
        remuxAvailable = 0
        knownTotalDuration = 0
        pendingStartAt = max(0, startAt)
        currentTime = pendingStartAt
        duration = 0
        bufferedRanges = []
        bufferedEnd = 0
        pipeline = .none
        currentSourceURL = nil
        audioTracks = []
        selectedAudioTrackID = nil
        directAudioGroup = nil

        guard let url = URL(string: source.url), !source.url.isEmpty else {
            status = .failed("آدرس سورس نامعتبر است")
            return
        }
        currentSourceURL = url

        if source.isDirectPlayable {
            status = .preparing(note ?? (pendingStartAt > 0.5
                                ? "در حال شروع پخش از \(Self.timeText(pendingStartAt))…"
                                : "در حال آماده‌سازی پخش…"))
            startDirect(url: url)
        } else {
            // Remux consumes the offset up front; the item it produces always starts at 0.
            let resume = pendingStartAt
            pendingStartAt = 0
            startRemux(url: url, startAt: resume, note: note)
        }
    }

    private func startDirect(url: URL) {
        pipeline = .direct
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 0
        installItemObservers(for: item)
        player.replaceCurrentItem(with: item)
        scheduleDirectTimeout()
    }

    private func scheduleDirectTimeout() {
        directTimeoutTask?.cancel()
        directTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.directPathTimedOut()
        }
    }

    private func directPathTimedOut() {
        guard pipeline == .direct, status.isPreparing, !directFallbackTried, let url = currentSourceURL else { return }
        directFallbackTried = true
        fallbackToRemux(url: url)
    }

    private func fallbackToRemux(url: URL) {
        clearItemObservers()
        player.replaceCurrentItem(with: nil)
        pipeline = .none
        pendingStartAt = 0
        status = .preparing("در حال تلاش با روش جایگزین…")
        startRemux(url: url, startAt: max(0, currentTime))
    }

    private func startRemux(url: URL, startAt: Double, note: String? = nil) {
        teardownPipeline()
        player.replaceCurrentItem(with: nil)
        directTimeoutTask?.cancel()
        directTimeoutTask = nil
        pipeline = .remux
        debugFFmpegArguments = nil
        baseOffset = max(0, startAt)
        remuxAvailable = 0
        currentTime = baseOffset
        bufferedRanges = []
        bufferedEnd = 0
        sessionGeneration += 1
        let generation = sessionGeneration

        guard let ffmpeg = FFmpegLocator.locate() else {
            pipeline = .none
            status = .failed("موتور پخش (ffmpeg) روی این سیستم پیدا نشد. لطفاً ویدئو را با VLC باز کنید یا آدرس آن را کپی کنید.")
            return
        }

        if let note {
            status = .preparing(note)
        } else if baseOffset > 0.5 {
            status = .preparing("در حال شروع پخش از \(Self.timeText(baseOffset))…")
        } else {
            status = .preparing("در حال تبدیل فرمت ویدئو…")
        }

        let session = RemuxSession(sourceURL: url,
                                   startAt: baseOffset,
                                   ffmpegPath: ffmpeg,
                                   probeDuration: baseOffset < 0.5,
                                   audioIndex: preferredAudioIndex ?? 0) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleRemuxEvent(event, generation: generation)
            }
        }
        remuxSession = session
        debugSessionDirectory = session.directory
        session.start()
    }

    private func restartRemux(at target: Double) {
        guard let url = currentSourceURL else { return }
        currentTime = target
        startRemux(url: url, startAt: target)
    }

    // MARK: Remux events

    private func handleRemuxEvent(_ event: RemuxSession.Event, generation: Int) {
        guard generation == sessionGeneration, pipeline == .remux else { return }

        switch event {
        case .launched(let arguments):
            debugFFmpegArguments = arguments

        case .audio(let tracks):
            refreshRemuxAudioTracks(tracks)

        case .playlistReady(let playlistURL):
            guard player.currentItem == nil else { return }
            debugPlaylistURL = playlistURL
            let item = AVPlayerItem(url: playlistURL)
            item.preferredForwardBufferDuration = 0
            installItemObservers(for: item)
            player.replaceCurrentItem(with: item)

        case .progress(let available):
            remuxAvailable = max(remuxAvailable, available)
            recomputeDuration()

        case .probed(let total):
            knownTotalDuration = max(knownTotalDuration, total)
            recomputeDuration()

        case .finished(let remaining):
            remuxAvailable = max(remuxAvailable, remaining)
            knownTotalDuration = max(knownTotalDuration, baseOffset + remaining)
            recomputeDuration()

        case .failed(let message):
            sessionGeneration += 1
            remuxSession?.stop()
            remuxSession = nil
            pipeline = .none
            isPlaying = false
            isBuffering = false
            player.pause()
            // A session that dies with the title already on screen is a glitch, not a dead link.
            if didStartPlaying, reloadInPlace() { return }
            if advanceAfterFailure() { return }
            status = .failed(attemptOrder.count > 1 ? finalFailureMessage() : message)
        }
    }

    private func recomputeDuration() {
        guard pipeline == .remux else { return }
        let available = baseOffset + remuxAvailable
        let total = max(knownTotalDuration, available)
        if total > 0 {
            duration = total
        }
    }

    // MARK: Item observers

    private func installItemObservers(for item: AVPlayerItem) {
        clearItemObservers()
        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] observed, _ in
            let status = observed.status
            let error = observed.error
            Task { @MainActor [weak self] in
                self?.itemStatusChanged(status, error: error, item: observed)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.itemDidEnd() }
        }
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in self?.itemFailed(error) }
        }
    }

    private func clearItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
    }

    private func itemStatusChanged(_ itemStatus: AVPlayerItem.Status, error: Error?, item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch itemStatus {
        case .readyToPlay:
            directTimeoutTask?.cancel()
            directTimeoutTask = nil
            status = .ready
            refreshDirectAudioTracks(item)
            let itemDuration = item.duration.seconds
            if itemDuration.isFinite, itemDuration > 0 {
                if pipeline == .remux {
                    knownTotalDuration = max(knownTotalDuration, baseOffset + itemDuration)
                    recomputeDuration()
                } else {
                    duration = itemDuration
                }
            }
            startAtPendingPositionIfNeeded()
        case .failed:
            itemFailed(error)
        default:
            break
        }
    }

    /// Direct items ignore `load(startAt:)`, so the offset is applied once AVPlayer reports ready.
    private func startAtPendingPositionIfNeeded() {
        let target = pendingStartAt
        pendingStartAt = 0
        guard target > 0.5 else {
            if playbackIntent { startPlaying() }
            return
        }
        var clamped = target
        if duration > 1 { clamped = min(target, duration - 0.5) }
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = clamped
                if self.playbackIntent { self.startPlaying() }
            }
        }
    }

    private func itemFailed(_ error: Error?) {
        directTimeoutTask?.cancel()
        directTimeoutTask = nil
        cancelStallCheck()
        isPlaying = false
        isBuffering = false
        player.pause()

        // A stream that had already played is a glitch, not a dead link.
        if didStartPlaying, reloadInPlace() { return }

        // Nothing of this link ever arrived: the next source is cheaper than remuxing a dead URL.
        if pipeline == .direct, canRotate, advanceAfterFailure() { return }

        if pipeline == .direct, !directFallbackTried, let url = currentSourceURL {
            directFallbackTried = true
            fallbackToRemux(url: url)
            return
        }
        if pipeline == .remux {
            sessionGeneration += 1
            remuxSession?.stop()
            remuxSession = nil
        }
        if advanceAfterFailure() { return }
        pipeline = .none
        status = .failed(finalFailureMessage())
    }

    private func itemDidEnd() {
        isPlaying = false
        isBuffering = false
        didStartPlaying = false
        didReachEnd = true
        if duration > 0 {
            currentTime = duration
        }
        updateBuffered()
    }

    private func startPlaying() {
        guard player.currentItem != nil else { return }
        didReachEnd = false
        player.play()
        if rate != 1.0 {
            player.rate = rate
        }
        isPlaying = true
        didStartPlaying = true
        if let currentSourceURL {
            LinkHealth.recordSuccess(currentSourceURL.absoluteString)
        }
    }

    // MARK: Ticking

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.updateTicking(time: time) }
        }
    }

    private func observeTimeControlStatus() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshBufferingFlag() }
        }
    }

    private func refreshBufferingFlag() {
        let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        isBuffering = isPlaying && waiting
        if isPlaying, didStartPlaying, waiting {
            scheduleStallCheck()
        } else {
            cancelStallCheck()
        }
    }

    // MARK: Stall and connection recovery

    /// A stream that had begun playing and then sits waiting for data is stuck, not buffering.
    private func scheduleStallCheck() {
        guard stallTask == nil else { return }
        stallTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.stallTask = nil
            self.recoverFromStall()
        }
    }

    private func cancelStallCheck() {
        stallTask?.cancel()
        stallTask = nil
    }

    private func recoverFromStall() {
        guard isPlaying, didStartPlaying,
              player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
        guard ConnectionWatch.shared.isConnected else {
            networkDropped = true
            status = .preparing("اتصال اینترنت قطع شده؛ منتظر بازگشت آن…")
            return
        }
        if reloadInPlace() { return }
        advanceAfterFailure()
    }

    private func observeConnection() {
        connectionCancellable = ConnectionWatch.shared.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                Task { @MainActor [weak self] in self?.connectionChanged(connected) }
            }
    }

    private func connectionChanged(_ connected: Bool) {
        if connected {
            guard networkDropped else { return }
            networkDropped = false
            guard playbackIntent, let source = currentAttempt else { return }
            reloadTries = 0
            load(source: source, startAt: resumeOffset(),
                 note: "اتصال برگشت؛ در حال ازسرگیری پخش…")
            return
        }
        networkDropped = true
        guard isPlaying || status.isPreparing else { return }
        status = .preparing("اتصال اینترنت قطع شده؛ منتظر بازگشت آن…")
    }

    private func updateTicking(time: CMTime) {
        let raw = time.seconds
        if raw.isFinite, player.currentItem != nil {
            let offset = pipeline == .remux ? baseOffset : 0
            let value = max(0, raw + offset)
            if abs(value - currentTime) > 0.001 {
                currentTime = value
            }
        }
        if pipeline == .direct, let item = player.currentItem {
            let itemDuration = item.duration.seconds
            if itemDuration.isFinite, itemDuration > 0, itemDuration > duration {
                duration = itemDuration
            }
        }
        updateBuffered()
        refreshBufferingFlag()
    }

    private func updateBuffered() {
        guard let item = player.currentItem else {
            if !bufferedRanges.isEmpty { bufferedRanges = [] }
            if bufferedEnd != 0 { bufferedEnd = 0 }
            return
        }
        let offset = pipeline == .remux ? baseOffset : 0
        var rawRanges: [ClosedRange<Double>] = []
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let length = range.duration.seconds
            guard start.isFinite, length.isFinite, length > 0 else { continue }
            rawRanges.append((offset + start)...(offset + start + length))
        }

        if pipeline == .remux {
            // Every remuxed segment is instantly available from the local server. `rawRanges`
            // already carries the base offset, so clamp/merge instead of offsetting again.
            let loadedEnd = rawRanges.map(\.upperBound).max() ?? 0
            let availableEnd = max(offset + remuxAvailable, loadedEnd)
            let ranges: [ClosedRange<Double>] = availableEnd > offset ? [offset...availableEnd] : []
            if ranges != bufferedRanges { bufferedRanges = ranges }
            let end = ranges.last?.upperBound ?? 0
            if abs(end - bufferedEnd) > 0.01 { bufferedEnd = end }
            return
        }

        rawRanges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for range in rawRanges {
            if let last = merged.last, range.lowerBound <= last.upperBound + 0.05 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        if merged != bufferedRanges { bufferedRanges = merged }
        let end = merged.last?.upperBound ?? 0
        if abs(end - bufferedEnd) > 0.01 { bufferedEnd = end }
    }

    // MARK: Cleanup

    private func teardownPipeline() {
        directTimeoutTask?.cancel()
        directTimeoutTask = nil
        cancelStallCheck()
        clearItemObservers()
        remuxSession?.stop()
        remuxSession = nil
        debugPlaylistURL = nil
        debugFFmpegArguments = nil
        debugSessionDirectory = nil
        player.pause()
        pipeline = .none
    }

    private static func timeText(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
