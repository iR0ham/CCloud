import Foundation
import SwiftUI

// MARK: - Shared app state (navigation, genres cache, playback, toasts)

@MainActor
final class AppState: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case home, movies, series, categories, live, search, favorites, history, countries, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "خانه"
            case .movies: return "فیلم‌ها"
            case .series: return "سریال‌ها"
            case .categories: return "دسته‌بندی‌ها"
            case .live: return "پخش زنده"
            case .search: return "جستجو"
            case .favorites: return "علاقه‌مندی‌ها"
            case .history: return "اخیراً دیده‌شده"
            case .countries: return "کشورها"
            case .settings: return "تنظیمات"
            }
        }

        var icon: String {
            switch self {
            case .home: return "house"
            case .movies: return "film"
            case .series: return "tv"
            case .categories: return "square.grid.2x2"
            case .live: return "dot.radiowaves.left.and.right"
            case .search: return "magnifyingglass"
            case .favorites: return "heart"
            case .history: return "clock.arrow.circlepath"
            case .countries: return "globe.europe.africa"
            case .settings: return "gearshape"
            }
        }
    }

    enum Route: Hashable {
        case movie(Movie)
        case series(Series)
        case country(Country)
        case category(Genre)
    }

    @Published var tab: Tab = .home
    @Published var path: [Route] = []
    @Published var playback: PlaybackRequest?
    @Published var showAbout = false
    @Published var showSplash = true
    @Published var searchQuery = ""
    @Published var liveSelectedCountry: LiveTVCountry?

    func openLiveCountry(_ country: LiveTVCountry) {
        liveSelectedCountry = country
    }

    func closeLiveCountry() {
        liveSelectedCountry = nil
    }
    @Published var genres: [Genre] = []
    @Published var genresError: String?
    @Published var genresLoading = false
    @Published var backendHost: String = "server-hi-speed-iran.info"
    @Published var toast: String?
    /// Bumped by ⌘R / the Home refresh button; every data-driven screen reloads on change.
    @Published var refreshTick = 0
    /// Bumped by ⌘F so the search screen can focus its field.
    @Published var searchFocusTick = 0
    /// True while the API is serving the on-disk fallback because every host failed.
    @Published var isOffline = false

    /// Injected by the app entry point (needed by the favorites/history demo hooks).
    weak var favoritesRef: FavoritesStore?
    weak var historyRef: WatchHistoryStore?

    private var toastTask: Task<Void, Never>?

    private var favorites: FavoritesStore { favoritesRef ?? FavoritesStore() }
    private var history: WatchHistoryStore { historyRef ?? WatchHistoryStore() }

    init() {
        // QA hook: CCloud --tab series|search|favorites|countries|settings (or UserDefaults QATab)
        if let idx = CommandLine.arguments.firstIndex(of: "--tab"), idx + 1 < CommandLine.arguments.count,
           let tab = Tab(rawValue: CommandLine.arguments[idx + 1]) {
            self.tab = tab
        } else if let qaTab = UserDefaults.standard.string(forKey: "QATab"), let tab = Tab(rawValue: qaTab) {
            self.tab = tab
            UserDefaults.standard.removeObject(forKey: "QATab")
        } else if let saved = UserDefaults.standard.string(forKey: Self.lastTabKey),
                  let tab = Tab(rawValue: saved) {
            self.tab = tab
        }
        APIClient.shared.onBackendChange = { [weak self] host in
            Task { @MainActor in
                self?.backendHost = host
                ImageCache.shared.preferredAPIHost = host
            }
        }
        APIClient.shared.onConnectivityChange = { [weak self] online in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = self.isOffline
                self.isOffline = !online
                if !online, !wasOffline {
                    self.showToast("اتصال به سرور برقرار نشد؛ محتوای ذخیره‌شده نمایش داده می‌شود")
                } else if online, wasOffline {
                    self.showToast("اتصال به سرور برقرار شد")
                }
            }
        }
        ImageCache.shared.preferredAPIHost = backendHost
    }

    // MARK: Navigation

    func openMovie(_ movie: Movie) {
        if movie.isSeries {
            openSeries(Series(from: movie))
        } else {
            path.append(.movie(movie))
        }
    }

    func openSeries(_ series: Series) {
        path.append(.series(series))
    }

    func openCountry(_ country: Country) {
        path.append(.country(country))
    }

    func openCategory(_ genre: Genre) {
        path.append(.category(genre))
    }

    func back() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func select(tab: Tab) {
        if self.tab == tab {
            path.removeAll()
        } else {
            self.tab = tab
            path.removeAll()
            UserDefaults.standard.set(tab.rawValue, forKey: Self.lastTabKey)
        }
    }

    private static let lastTabKey = "ccloud.lastTab"

    /// Global refresh (⌘R): drop the short-lived HTTP cache and tell every screen to reload.
    func refresh() {
        APIClient.shared.invalidateCache()
        refreshTick &+= 1
        showToast("در حال تازه‌سازی…")
    }

    func focusSearch() {
        if tab != .search {
            select(tab: .search)
        } else {
            path.removeAll()
        }
        searchFocusTick &+= 1
    }

    func play(_ request: PlaybackRequest) {
        playback = request
        playerWindowOpener?(request)
    }

    /// Installed by the root view, which is where `openWindow` is available.
    var playerWindowOpener: ((PlaybackRequest) -> Void)?

    // MARK: Data

    func loadGenresIfNeeded() async {
        guard genres.isEmpty, !genresLoading else { return }
        await loadGenres()
    }

    func loadGenres() async {
        genresLoading = true
        genresError = nil
        do {
            genres = try await APIClient.shared.genres()
            ImageCache.shared.preferredAPIHost = backendHost
            log("genres loaded: \(genres.count) items via \(backendHost)")
        } catch {
            genresError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        genresLoading = false
    }

    // MARK: Toast (small Persian confirmation, auto dismiss)

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toast = nil }
        }
    }

    /// QA/demo hook: `CCloud --demo movie|series|player|about|country|search|live-*`;
    /// `player-local`, `live-play` and `live-failover` take one extra argument (path or channel name).
    func runDemoIfRequested() async {
        let args = CommandLine.arguments
        let demo: String
        if let idx = args.firstIndex(of: "--demo"), idx + 1 < args.count {
            demo = args[idx + 1]
        } else if let qaDemo = UserDefaults.standard.string(forKey: "QADemo") {
            demo = qaDemo
            UserDefaults.standard.removeObject(forKey: "QADemo")
            UserDefaults.standard.synchronize()
        } else {
            return
        }
        try? await Task.sleep(nanoseconds: 1_800_000_000)

        switch demo {
        case "about":
            showAbout = true
        case "movie":
            if let movies = try? await APIClient.shared.movies(page: 0),
               let movie = movies.first(where: { !$0.sources.isEmpty }) ?? movies.first {
                openMovie(movie)
                log("demo: opened movie \(movie.id) \(movie.title)")
            }
        case "series":
            if let series = try? await APIClient.shared.series(page: 0), let first = series.first {
                openSeries(first)
                log("demo: opened series \(first.id) \(first.title)")
            }
        case "country":
            if let countries = try? await APIClient.shared.countries(), let first = countries.first {
                openCountry(first)
                log("demo: opened country \(first.title)")
            }
        case "category":
            if genres.isEmpty, let fetched = try? await APIClient.shared.genres() {
                genres = fetched
            }
            if let first = genres.first {
                openCategory(first)
                log("demo: opened category \(first.title)")
            }
        case "search":
            searchQuery = "housemaid"
            tab = .search
        case "live":
            tab = .live
        case "live-channels":
            tab = .live
            if let countries = try? await LiveTVClient.shared.countries() {
                let country = countries.first(where: { $0.code == "IR" }) ?? countries.first
                liveSelectedCountry = country
                log("demo: live country \(country?.persianName ?? "-")")
            }
        case "live-play":
            // args: --demo live-play [channel name] — QA has to be able to aim at one row,
            // e.g. the off-air HodHod, to watch the engine mark it dead.
            var liveNeedle = ""
            if let idx = args.firstIndex(of: "--demo"), idx + 2 < args.count { liveNeedle = args[idx + 2] }
            if let channels = try? await LiveTVClient.shared.channels(countryCode: "ir"),
               let channel = channels.first(where: {
                   $0.primaryStream != nil
                       && (liveNeedle.isEmpty || $0.name.localizedCaseInsensitiveContains(liveNeedle))
               }),
               let request = channel.playbackRequest(countryName: "ایران") {
                play(request)
                log("demo: live playing \(channel.name)")
            } else {
                log("demo: live play found no channel for \(liveNeedle)")
            }
        case "live-failover":
            // args: --demo live-failover [channel name]
            // QA: put an unreachable link in front of a real live channel and check that the
            // source walk skips it and plays the backup. The dead url is unique per run so the
            // dead-link memory cannot demote it to the back of the queue on a second pass.
            var needle = ""
            if let idx = args.firstIndex(of: "--demo"), idx + 2 < args.count { needle = args[idx + 2] }
            let countries = try? await LiveTVClient.shared.countries()
            if let iran = countries?.first(where: { $0.code == "IR" }),
               let channels = try? await LiveTVCatalog.shared.channels(for: iran),
               let channel = channels.first(where: {
                   $0.streams.count > 1
                       && (needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle))
               }),
               let base = channel.playbackRequest(countryName: iran.persianName) {
                let dead = MediaSource(id: 900, quality: "منبع آزمایشی", type: "m3u8",
                                       url: "http://127.0.0.1:9/qa-dead-\(UUID().uuidString).m3u8")
                play(PlaybackRequest(title: base.title,
                                     subtitle: base.subtitle,
                                     posterURL: base.posterURL,
                                     sources: [dead] + base.sources,
                                     preferredSourceID: dead.id))
                log("demo: live failover on \(channel.name) with \(channel.streams.count) real sources behind a dead link")
            } else {
                log("demo: live failover found no multi-source channel")
            }
        case "favorites":
            if let movies = try? await APIClient.shared.movies(page: 0),
               let movie = movies.first(where: { !$0.sources.isEmpty }) {
                favorites.toggle(movie: movie)
            }
            if let series = try? await APIClient.shared.series(page: 0), let first = series.first {
                favorites.toggle(series: first)
            }
            tab = .favorites
            log("demo: favorites now \(favorites.entries.count)")
        case "favorites-clear":
            favorites.clear()
            tab = .favorites
            log("demo: favorites cleared")
        case "history":
            await seedHistoryDemo()
            tab = .history
            log("demo: history seeded, \(history.entries.count) entries")
        case "home-history":
            await seedHistoryDemo()
            tab = .home
            log("demo: history seeded for home, \(history.entries.count) entries")
        case "history-series":
            if let series = await seedHistoryDemo() {
                openSeries(series)
                log("demo: opened series with watched episodes")
            }
        case "history-clear":
            history.clear()
            tab = .history
            log("demo: history cleared")
        case "player-local":
            // args: --demo player-local /path/to/file.mp4|mkv
            if let idx = args.firstIndex(of: "--demo"), idx + 2 < args.count {
                let path = args[idx + 2]
                let url = path.hasPrefix("file://") ? path : URL(fileURLWithPath: path).absoluteString
                let ext = (path as NSString).pathExtension.lowercased()
                let source = MediaSource(id: 1, quality: "1080p",
                                         type: ext.isEmpty ? "mp4" : ext, url: url)
                play(PlaybackRequest(title: "پخش آزمایشی", subtitle: "تست محلی",
                                     sources: [source], preferredSourceID: source.id))
                log("demo: playing local file \(path)")
            }
        case "player":
            if let movies = try? await APIClient.shared.movies(page: 0),
               let movie = movies.first(where: { !$0.sources.playable.isEmpty }) {
                let source = movie.sources.preferred(for: "720")
                play(PlaybackRequest(title: movie.title,
                                     subtitle: movie.genreText,
                                     posterURL: movie.image,
                                     sources: movie.sources,
                                     preferredSourceID: source?.id,
                                     media: PlaybackInfo(kind: .movie, movie: movie)))
                log("demo: playing \(movie.title)")
            }
        default:
            log("demo: unknown demo \(demo)")
        }
    }

    /// Fills the history tab with a few live titles plus a series whose first episodes are marked
    /// watched, so the tab and the episode markers can be snapshot-verified.
    @discardableResult
    private func seedHistoryDemo() async -> Series? {
        let now = Date()
        if let movies = try? await APIClient.shared.movies(page: 0) {
            let progressValues = [0.38, 0.72, 0.14, 0.95]
            for (index, movie) in movies.prefix(4).enumerated() {
                let request = PlaybackRequest(title: movie.title,
                                              posterURL: movie.image.isEmpty ? nil : movie.image,
                                              sources: movie.sources,
                                              media: PlaybackInfo(kind: .movie, movie: movie))
                history.record(request,
                               progress: progressValues[index],
                               at: now.addingTimeInterval(-Double(index + 1) * 2_400))
            }
        }

        guard let series = try? await APIClient.shared.series(page: 0), let first = series.first else {
            return nil
        }
        for (index, item) in series.prefix(2).enumerated() {
            if index == 0,
               let seasons = try? await APIClient.shared.seasons(seriesId: item.id),
               let season = seasons.first {
                for (episodeIndex, episode) in season.episodes.prefix(3).enumerated() {
                    let label = episode.episodeNumber.map { "قسمت \($0)" } ?? episode.title
                    let info = PlaybackInfo(kind: .series,
                                            series: item,
                                            episodeID: episode.id,
                                            seasonTitle: season.title,
                                            episodeLabel: label)
                    let request = PlaybackRequest(title: item.title,
                                                  posterURL: item.image.isEmpty ? nil : item.image,
                                                  sources: episode.sources,
                                                  media: info)
                    history.record(request,
                                   progress: episodeIndex == 2 ? 0.45 : 1.0,
                                   at: now.addingTimeInterval(-Double(3 - episodeIndex) * 3_600))
                }
            } else {
                let info = PlaybackInfo(kind: .series, series: item)
                let request = PlaybackRequest(title: item.title,
                                              posterURL: item.image.isEmpty ? nil : item.image,
                                              sources: [],
                                              media: info)
                history.record(request, at: now.addingTimeInterval(-Double(index + 2) * 7_200))
            }
        }
        return first
    }

    func log(_ message: String) {
        FileHandle.standardError.write("[ccloud] \(message)\n".data(using: .utf8)!)
    }

    func copyToPasteboard(_ string: String, toastMessage: String = "در کلیپ‌بورد کپی شد") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        showToast(toastMessage)
    }
}
