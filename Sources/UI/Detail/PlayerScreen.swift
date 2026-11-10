import SwiftUI
import AppKit

// MARK: - Player UI state (owner: ui-detail). No @State anywhere (PROJECT.md §5.5).

@MainActor
final class PlayerUIModel: ObservableObject {
    @Published var controlsVisible = true
    @Published var isScrubbing = false
    @Published var scrubPosition: Double = 0
    @Published var speed: Double = 1.0
    @Published var lastAudibleVolume: Double = 0.85
    @Published var toast: String?
    @Published var isFullscreen = false
    /// Seconds left before the next episode starts automatically; nil when not counting down.
    @Published var autoNextCountdown: Int?

    /// Debug/QA hook: `--debug-player-controls` keeps the overlay visible for snapshots.
    var autoHideEnabled = true
    /// Set once playback actually starts, so a failed/never-started stream is not added to history.
    var didStartPlayback = false

    private var hideTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var autoNextTask: Task<Void, Never>?
    var keyMonitor: Any?

    var vlcAvailable: Bool { PlayerExternalApps.vlcURL != nil }

    // MARK: Auto-next countdown

    func startAutoNext(seconds: Int = 10, onFinish: @escaping () -> Void) {
        cancelAutoNext()
        autoNextCountdown = seconds
        autoNextTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
                await MainActor.run {
                    guard let self, self.autoNextCountdown != nil else { return }
                    self.autoNextCountdown = remaining
                }
                if remaining == 0 { break }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.autoNextCountdown = nil
                onFinish()
            }
        }
    }

    func cancelAutoNext() {
        autoNextTask?.cancel()
        autoNextTask = nil
        autoNextCountdown = nil
    }

    // MARK: Auto-hide

    func poke(playing: Bool) {
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.18)) { controlsVisible = true }
        }
        scheduleAutoHide(playing: playing)
    }

    func scheduleAutoHide(playing: Bool) {
        hideTask?.cancel()
        guard autoHideEnabled, playing, !isScrubbing else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.isScrubbing, self.autoHideEnabled else { return }
                withAnimation(.easeInOut(duration: 0.22)) { self.controlsVisible = false }
            }
        }
    }

    func ping(playing: Bool) {
        hideTask?.cancel()
        scheduleAutoHide(playing: playing)
    }

    func toggleControls(playing: Bool) {
        if controlsVisible {
            hideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        } else {
            poke(playing: playing)
        }
    }

    func cancelAutoHide() {
        hideTask?.cancel()
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) { self?.toast = nil }
            }
        }
    }
}

// MARK: - External player fallback

enum PlayerExternalApps {
    static var vlcURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.videolan.vlc") {
            return url
        }
        let candidates = ["/Applications/VLC.app", "\(NSHomeDirectory())/Applications/VLC.app"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    static func open(urlString: String, preferVLC: Bool) {
        guard let url = URL(string: urlString), !urlString.isEmpty else { return }
        if preferVLC, let vlc = vlcURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: vlc, configuration: configuration) { _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Time formatting

enum PlayerTime {
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Timeline (custom: buffered range + scrubbing)

struct PlayerTimeline: View {
    @ObservedObject var controller: PlaybackController
    @ObservedObject var model: PlayerUIModel

    private var duration: Double { max(controller.duration, 0.001) }

    /// Live HLS streams report no finite duration: show a live bar instead of a seek bar.
    private var isLive: Bool { controller.duration <= 1 }

    private var displayedTime: Double {
        model.isScrubbing ? model.scrubPosition : controller.currentTime
    }

    var body: some View {
        GeometryReader { geometry in
            if isLive {
                liveBar
            } else {
            let width = max(geometry.size.width, 1)
            let progress = min(max(displayedTime / duration, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 5)

                ForEach(Array(controller.bufferedRanges.enumerated()), id: \.offset) { pair in
                    let lower = min(max(pair.element.lowerBound / duration, 0), 1)
                    let upper = min(max(pair.element.upperBound / duration, 0), 1)
                    Capsule()
                        .fill(Color.white.opacity(0.34))
                        .frame(width: max(width * (upper - lower), 2), height: 5)
                        .offset(x: width * lower)
                }

                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(width * progress, 2), height: 5)

                Circle()
                    .fill(Color.white)
                    .frame(width: model.isScrubbing ? 14 : 11, height: model.isScrubbing ? 14 : 11)
                    .shadow(color: .black.opacity(0.45), radius: 3)
                    .offset(x: min(max(width * progress - 5.5, 0), max(width - 11, 0)))
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !model.isScrubbing {
                            model.scrubPosition = controller.currentTime
                            model.isScrubbing = true
                            model.cancelAutoHide()
                        }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        model.scrubPosition = fraction * duration
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        let target = fraction * duration
                        model.isScrubbing = false
                        controller.seek(to: target)
                        model.poke(playing: controller.isPlaying)
                    }
            )
            }
        }
        .frame(height: 18)
    }

    private var liveBar: some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                Circle().fill(Color.white).frame(width: 5, height: 5)
                Text("زنده")
                    .font(.ccloud(9.5, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.red))

            Capsule()
                .fill(Theme.red.opacity(0.75))
                .frame(height: 4)

            Text("پخش زنده")
                .font(.ccloud(10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize()
        }
        .frame(height: 18)
    }
}

// MARK: - Player screen

/// Holds the active request of a series queue. Pressing «قسمت بعد» swaps the request, which
/// gives `PlayerSessionView` a new identity and therefore a fresh playback controller.
@MainActor
final class PlayerQueueModel: ObservableObject {
    @Published private(set) var request: PlaybackRequest

    init(request: PlaybackRequest) {
        self.request = request
    }

    func advanceToNextEpisode() {
        guard let next = request.advancingToNextEpisode() else { return }
        request = next
    }
}

struct PlayerScreen: View {
    @StateObject private var queue: PlayerQueueModel

    init(request: PlaybackRequest) {
        _queue = StateObject(wrappedValue: PlayerQueueModel(request: request))
    }

    var body: some View {
        PlayerSessionView(request: queue.request, onNextEpisode: { queue.advanceToNextEpisode() })
            .id(queue.request.id)
    }
}

struct PlayerSessionView: View {
    let request: PlaybackRequest
    let onNextEpisode: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: WatchHistoryStore
    @StateObject private var controller: PlaybackController
    @StateObject private var model = PlayerUIModel()

    init(request: PlaybackRequest, onNextEpisode: @escaping () -> Void) {
        self.request = request
        self.onNextEpisode = onNextEpisode
        _controller = StateObject(wrappedValue: PlaybackController(request: request))
    }

    // MARK: Derived state

    private var isPreparing: Bool { controller.status.isPreparing }
    private var isFailed: Bool { controller.status.isFailed }
    private var statusMessage: String? { controller.status.message }

    private var currentSource: MediaSource? {
        controller.selectedSource ?? controller.sources.first
    }

    private var qualityLabel: String {
        guard let source = currentSource else { return "—" }
        return "\(source.qualityLabel) • \(source.kindLabel)"
    }

    private var volumeIcon: String {
        if controller.volume <= 0.001 { return "speaker.slash.fill" }
        if controller.volume < 0.35 { return "speaker.wave.1.fill" }
        if controller.volume < 0.7 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var posterURL: URL? {
        guard let raw = request.posterURL, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black

            if isPreparing || isFailed {
                posterBackdrop
            }

            PlayerSurface(controller: controller)

            // Click / double-click surface (behind the controls)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleFullscreen() }
                .onTapGesture { model.toggleControls(playing: controller.isPlaying) }
                .onContinuousHover { phase in
                    if case .active = phase {
                        model.poke(playing: controller.isPlaying)
                    }
                }

            if controller.isBuffering && !isPreparing && controller.status.isReady {
                bufferingBadge
            }

            overlay

            toastOverlay

            autoNextOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
        .onReceive(NotificationCenter.default.publisher(for: .ccloudTogglePlayback)) { _ in
            togglePlayback()
        }
        .onChange(of: controller.isPlaying) { _, playing in
            model.ping(playing: playing)
            if playing {
                model.didStartPlayback = true
                saveProgress()
            }
        }
        .onChange(of: controller.status) { _, _ in
            model.poke(playing: controller.isPlaying)
        }
        .onChange(of: controller.didReachEnd) { _, ended in
            guard ended else { return }
            guard settings.autoPlayNextEpisode, request.nextEpisode != nil else { return }
            model.startAutoNext { onNextEpisode() }
        }
        .task(id: request.id) {
            // Save every 10s so an unexpected quit still resumes near the right spot.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                guard model.didStartPlayback, controller.isPlaying, controller.duration > 1 else { continue }
                saveProgress()
            }
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlay: some View {
        if isPreparing {
            preparingOverlay
        } else if isFailed {
            failedOverlay
        } else {
            controlsOverlay
                .opacity(model.controlsVisible ? 1 : 0)
                .allowsHitTesting(model.controlsVisible)
        }
    }

    private var posterBackdrop: some View {
        ZStack {
            CachedAsyncImage(url: posterURL, placeholderIcon: "play.rectangle")
                .opacity(0.30)
                .blur(radius: 26)
            Color.black.opacity(0.45)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var bufferingBadge: some View {
        VStack {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("در حال بارگیری…")
                    .font(.ccloud(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(.top, 54)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: Preparing / failed states

    private var preparingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(statusMessage ?? "در حال آماده‌سازی پخش…")
                    .font(.ccloud(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                if controller.pipeline == .remux {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                        Text("در حال تبدیل MKV به HLS برای پخش")
                    }
                    .font(.ccloud(10.5))
                    .foregroundStyle(.white.opacity(0.55))
                }
                Text("این ممکن است چند ثانیه طول بکشد")
                    .font(.ccloud(9.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )

            VStack {
                HStack {
                    circleButton("xmark", help: "بستن") { close() }
                    Spacer(minLength: 0)
                }
                .padding(18)
                Spacer(minLength: 0)
            }
        }
    }

    private var failedOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 15) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.red)
                Text("پخش ناموفق بود")
                    .font(.ccloud(17, weight: .bold))
                    .foregroundStyle(.white)
                Text(statusMessage ?? "خطای نامشخص در پخش این سورس")
                    .font(.ccloud(11.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 440)

                HStack(spacing: 10) {
                    Button(action: retryPlayback) { Text("تلاش دوباره") }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                    Button(action: openInVLC) {
                        HStack(spacing: 5) {
                            Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 10))
                            Text("باز کردن در VLC")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    Button(action: copySourceLink) { Text("کپی لینک") }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                    Button(action: close) { Text("بستن") }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }

                if !model.vlcAvailable {
                    Text("VLC روی این مک نصب نیست؛ در این حالت لینک با برنامه پیش‌فرض باز می‌شود.")
                        .font(.ccloud(9.5))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(28)
            .frame(maxWidth: 580)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0x14161F))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 26, y: 10)
        }
    }

    // MARK: Controls

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            centerControls
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.78), location: 0.0),
                    .init(color: Color.black.opacity(0.18), location: 0.28),
                    .init(color: Color.black.opacity(0.02), location: 0.52),
                    .init(color: Color.black.opacity(0.72), location: 0.82),
                    .init(color: Color.black.opacity(0.92), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            circleButton("xmark", help: "بستن پخش‌کننده") { close() }

            VStack(alignment: .leading, spacing: 2) {
                Text(request.title)
                    .font(.ccloud(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle = request.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.ccloud(10.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            if controller.pipeline == .remux {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .bold))
                    Text("HLS")
                        .font(.ccloud(9.5, weight: .bold))
                }
                .foregroundStyle(Theme.accentSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
                .help("این سورس با تبدیل فرمت پخش می‌شود")
            }

            sourceMenu
            audioMenu
            speedMenu
            circleButton(
                model.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                help: model.isFullscreen ? "خروج از تمام‌صفحه" : "تمام‌صفحه"
            ) { toggleFullscreen() }
        }
    }

    private var centerControls: some View {
        HStack(spacing: 46) {
            seekButton(systemName: "gobackward.10", help: "۱۰ ثانیه عقب", seconds: -10)
            playPauseButton
            seekButton(systemName: "goforward.10", help: "۱۰ ثانیه جلو", seconds: 10)
        }
    }

    private var playPauseButton: some View {
        Button(action: togglePlayback) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
                    .frame(width: 74, height: 74)
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .offset(x: controller.isPlaying ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
        .help(controller.isPlaying ? "توقف" : "پخش")
    }

    private func seekButton(systemName: String, help: String, seconds: Double) -> some View {
        Button {
            controller.seek(to: controller.currentTime + seconds)
            model.poke(playing: controller.isPlaying)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func nextEpisodeButton(_ next: PlaybackEpisode) -> some View {
        Button(action: onNextEpisode) {
            HStack(spacing: 6) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("قسمت بعد")
                    .font(.ccloud(11, weight: .semibold))
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.accent))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("پخش قسمت بعد • \(next.subtitle)")
    }

    private var bottomBar: some View {
        VStack(spacing: 7) {
            PlayerTimeline(controller: controller, model: model)

            HStack(spacing: 14) {
                volumeControl

                Spacer(minLength: 12)

                PlayerTimelineLabels(controller: controller, model: model)

                Spacer(minLength: 12)

                Text(qualityLabel)
                    .font(.ccloud(10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                if let next = request.nextEpisode {
                    nextEpisodeButton(next)
                }
            }
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button(action: toggleMute) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(controller.volume > 0 ? "بی‌صدا" : "باصدا")

            Slider(
                value: Binding(
                    get: { controller.volume },
                    set: { controller.volume = min(max($0, 0), 1) }
                ),
                in: 0...1
            )
            .frame(width: 104)
            .tint(Theme.accentBright)

            Text("\(Int((controller.volume * 100).rounded()))٪")
                .font(.ccloud(10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, alignment: .leading)
        }
        .frame(width: 210, alignment: .leading)
    }

    // MARK: Menus

    @ViewBuilder
    private var sourceMenu: some View {
        if controller.sources.count > 1 {
            Menu {
                ForEach(controller.sources) { source in
                    Button {
                        controller.selectSource(source)
                        model.poke(playing: true)
                    } label: {
                        if source.id == controller.selectedSourceID {
                            Label("\(source.qualityLabel) — \(source.kindLabel)", systemImage: "checkmark")
                        } else {
                            Text("\(source.qualityLabel) — \(source.kindLabel)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "4k.tv")
                        .font(.system(size: 11, weight: .semibold))
                    Text(qualityLabel)
                        .font(.ccloud(10.5, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("انتخاب کیفیت / سورس")
        }
    }

    /// Shown only when the media really carries more than one audio track.
    @ViewBuilder
    private var audioMenu: some View {
        if controller.audioTracks.count > 1 {
            Menu {
                ForEach(controller.audioTracks) { track in
                    Button {
                        controller.selectAudioTrack(track.id)
                        model.poke(playing: true)
                    } label: {
                        if track.id == controller.selectedAudioTrackID {
                            Label(track.label, systemImage: "checkmark")
                        } else {
                            Text(track.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                    Text(currentAudioLabel)
                        .font(.ccloud(10.5, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("انتخاب صدای ویدئو")
        }
    }

    private var currentAudioLabel: String {
        controller.audioTracks.first { $0.id == controller.selectedAudioTrackID }?.label ?? "صدا"
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                Button {
                    setSpeed(value)
                } label: {
                    if abs(model.speed - value) < 0.001 {
                        Label(speedLabel(value), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(value))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "speedometer")
                    .font(.system(size: 11, weight: .semibold))
                Text(speedLabel(model.speed))
                    .font(.ccloud(10.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("سرعت پخش")
    }

    private func speedLabel(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 { return "\(Int(value))x" }
        return String(format: "%.2gx", value)
    }

    // MARK: Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = model.toast {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green)
                    Text(message)
                        .font(.ccloud(11.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .padding(.bottom, 104)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private var autoNextOverlay: some View {
        VStack {
            Spacer()
            if let remaining = model.autoNextCountdown, let next = request.nextEpisode {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accentBright)
                            Text(verbatim: "قسمت بعد در \(browseNumber(remaining)) ثانیه")
                                .font(.ccloud(13, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        Text(next.subtitle)
                            .font(.ccloud(11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button {
                        model.cancelAutoNext()
                        onNextEpisode()
                    } label: {
                        Text("پخش حالا")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    Button {
                        model.cancelAutoNext()
                    } label: {
                        Text("لغو")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                }
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: 520)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: 0x14161F).opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 22, y: 8)
                .padding(.bottom, 130)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.autoNextCountdown)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Small helpers

    private func circleButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.5)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Lifecycle

    private func handleAppear() {
        model.autoHideEnabled = !CommandLine.arguments.contains("--debug-player-controls")
        model.speed = Double(controller.rate)
        model.lastAudibleVolume = controller.volume > 0.01 ? controller.volume : 0.85
        installKeyMonitor()
        model.poke(playing: controller.isPlaying)
    }

    private func handleDisappear() {
        if let monitor = model.keyMonitor {
            NSEvent.removeMonitor(monitor)
            model.keyMonitor = nil
        }
        model.cancelAutoHide()
        model.cancelAutoNext()
        if model.didStartPlayback {
            saveProgress()
        }
        controller.stop()
    }

    private func saveProgress() {
        let duration = controller.duration
        guard duration > 1 else { return }
        let fraction = min(max(controller.currentTime / duration, 0), 1)
        history.record(request,
                       progress: fraction,
                       position: controller.currentTime,
                       duration: duration)
    }

    private func installKeyMonitor() {
        guard model.keyMonitor == nil else { return }
        model.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                return event
            }
            switch event.keyCode {
            case 49, 123, 124, 53, 3, 46, 126, 125, 45:
                Task { @MainActor in
                    handleKey(keyCode: event.keyCode)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func handleKey(keyCode: UInt16) {
        switch keyCode {
        case 49: togglePlayback()        // space
        case 123: seek(by: -10)          // ←
        case 124: seek(by: 10)           // →
        case 53: handleEscape()          // esc
        case 3: toggleFullscreen()       // f
        case 46: toggleMute()            // m
        case 126: changeVolume(by: 0.05) // ↑
        case 125: changeVolume(by: -0.05) // ↓
        case 45: playNextEpisode()       // n
        default: break
        }
    }

    // MARK: Actions

    private func togglePlayback() {
        if !controller.isPlaying {
            model.cancelAutoNext()
            if controller.didReachEnd {
                controller.seek(to: 0)
            }
        }
        controller.togglePlay()
        if controller.isPlaying {
            controller.rate = Float(model.speed)
        }
        model.poke(playing: controller.isPlaying)
    }

    private func playNextEpisode() {
        guard request.nextEpisode != nil else { return }
        model.cancelAutoNext()
        onNextEpisode()
    }

    private func changeVolume(by delta: Double) {
        let value = min(max(controller.volume + delta, 0), 1)
        controller.volume = value
        model.showToast("صدا: ٪\(browseNumber(Int((value * 100).rounded())))")
        model.poke(playing: controller.isPlaying)
    }

    private func seek(by seconds: Double) {
        guard controller.duration > 0 else { return }
        controller.seek(to: controller.currentTime + seconds)
        model.poke(playing: controller.isPlaying)
    }

    private func setSpeed(_ value: Double) {
        model.speed = value
        controller.rate = Float(value)
        if controller.isPlaying {
            controller.rate = Float(value)
        }
        model.poke(playing: controller.isPlaying)
    }

    private func toggleMute() {
        if controller.volume > 0.01 {
            model.lastAudibleVolume = controller.volume
            controller.volume = 0
        } else {
            controller.volume = max(model.lastAudibleVolume, 0.05)
        }
        model.showToast(controller.volume > 0.01 ? "صدا روشن شد" : "صدا قطع شد")
        model.poke(playing: controller.isPlaying)
    }

    private func retryPlayback() {
        controller.retry()
        model.poke(playing: true)
    }

    private func openInVLC() {
        guard let source = currentSource else { return }
        PlayerExternalApps.open(urlString: source.url, preferVLC: true)
        if !model.vlcAvailable {
            model.showToast("VLC نصب نیست؛ لینک در برنامه پیش‌فرض باز شد")
        }
    }

    private func copySourceLink() {
        guard let source = currentSource, !source.url.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source.url, forType: .string)
        model.showToast("لینک سورس کپی شد")
    }

    private func toggleFullscreen() {
        model.isFullscreen.toggle()
        NSApp.keyWindow?.toggleFullScreen(nil)
        model.poke(playing: controller.isPlaying)
    }

    private func handleEscape() {
        if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            model.isFullscreen = false
        } else {
            close()
        }
    }

    private func close() {
        controller.stop()
        dismiss()
    }
}

// MARK: - Timeline labels (separate view so only it re-renders with the time)

struct PlayerTimelineLabels: View {
    @ObservedObject var controller: PlaybackController
    @ObservedObject var model: PlayerUIModel

    private var displayedTime: Double {
        model.isScrubbing ? model.scrubPosition : controller.currentTime
    }

    var body: some View {
        HStack(spacing: 6) {
            if controller.duration <= 1 {
                Circle().fill(Theme.red).frame(width: 6, height: 6)
                Text("پخش زنده")
                    .foregroundStyle(Color.white.opacity(0.9))
            } else {
                Text(PlayerTime.string(displayedTime))
                Text("/")
                    .foregroundStyle(Color.white.opacity(0.35))
                Text(PlayerTime.string(controller.duration))
            }
            if controller.pipeline == .remux {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("تبدیل فرمت")
                }
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.leading, 6)
            }
        }
        .font(.ccloud(10.5, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.85))
    }
}
