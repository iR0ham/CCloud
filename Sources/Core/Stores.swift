import Foundation
import SwiftUI
import AppKit

// MARK: - Favorites

struct FavoriteEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, Hashable { case movie, series }

    let kind: Kind
    let movie: Movie?
    let series: Series?
    let addedAt: Date

    var id: String {
        switch kind {
        case .movie: return "movie-\(movie?.id ?? 0)"
        case .series: return "series-\(series?.id ?? 0)"
        }
    }
    var mediaID: Int { movie?.id ?? series?.id ?? 0 }
    var title: String { movie?.title ?? series?.title ?? "" }
    var posterURL: URL? { movie?.posterURL ?? series?.posterURL }
    var year: Int { movie?.year ?? series?.year ?? 0 }
    var imdb: Double { movie?.imdb ?? series?.imdb ?? 0 }
}

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var entries: [FavoriteEntry] = []

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("CCloudMac", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("favorites.json")
        load()
    }

    var movies: [FavoriteEntry] { entries.filter { $0.kind == .movie } }
    var series: [FavoriteEntry] { entries.filter { $0.kind == .series } }

    func isFavorite(id: Int, kind: MediaKind) -> Bool {
        switch kind {
        case .movie: return entries.contains { $0.kind == .movie && $0.mediaID == id }
        case .series: return entries.contains { $0.kind == .series && $0.mediaID == id }
        }
    }

    @discardableResult
    func toggle(movie: Movie) -> Bool {
        if let idx = entries.firstIndex(where: { $0.kind == .movie && $0.mediaID == movie.id }) {
            entries.remove(at: idx); save(); return false
        }
        entries.insert(FavoriteEntry(kind: .movie, movie: movie, series: nil, addedAt: Date()), at: 0)
        save(); return true
    }

    @discardableResult
    func toggle(series: Series) -> Bool {
        if let idx = entries.firstIndex(where: { $0.kind == .series && $0.mediaID == series.id }) {
            entries.remove(at: idx); save(); return false
        }
        entries.insert(FavoriteEntry(kind: .series, movie: nil, series: series, addedAt: Date()), at: 0)
        save(); return true
    }

    func remove(id: Int, kind: MediaKind) {
        entries.removeAll { entry in
            (kind == .movie && entry.kind == .movie && entry.mediaID == id) ||
            (kind == .series && entry.kind == .series && entry.mediaID == id)
        }
        save()
    }

    func clear() {
        entries.removeAll(); save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([FavoriteEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Watch history

struct WatchedEpisode: Codable, Hashable, Identifiable {
    let id: Int
    let seasonTitle: String
    let label: String
    var watchedAt: Date
    var progress: Double
    /// Exact seconds watched, so playback can continue where it stopped.
    var position: Double? = nil
    var duration: Double? = nil
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    let kind: MediaKind
    let movie: Movie?
    let series: Series?
    var lastWatchedAt: Date
    var progress: Double
    var episodes: [WatchedEpisode]
    /// Exact seconds of the movie (or of the last episode) for resume playback.
    var position: Double? = nil
    var duration: Double? = nil

    var id: String { "\(kind.rawValue)-\(mediaID)" }
    var mediaID: Int { movie?.id ?? series?.id ?? 0 }
    var title: String { movie?.title ?? series?.title ?? "" }
    var posterURL: URL? { movie?.posterURL ?? series?.posterURL }
    var year: Int { movie?.year ?? series?.year ?? 0 }
    var imdb: Double { movie?.imdb ?? series?.imdb ?? 0 }

    /// The most recent episode the user started, which is the "you are here" marker.
    var lastEpisode: WatchedEpisode? {
        episodes.max(by: { $0.watchedAt < $1.watchedAt })
    }
}

/// Persists what was played, newest first, and which episodes of a series were opened.
@MainActor
final class WatchHistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let maxEntries = 80
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("CCloudMac", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    /// Records a play start (`progress == nil`) or a progress update for an already recorded play.
    func record(_ request: PlaybackRequest,
                progress: Double? = nil,
                position: Double? = nil,
                duration: Double? = nil,
                at date: Date = Date()) {
        guard let media = request.media, media.mediaID != 0 else { return }
        let clamped = progress.map { min(max($0, 0), 1) }
        let safePosition = position.map { max(0, $0) }
        let safeDuration = duration.map { max(0, $0) }

        if let index = entries.firstIndex(where: { $0.kind == media.kind && $0.mediaID == media.mediaID }) {
            entries[index].lastWatchedAt = date
            if let clamped { entries[index].progress = clamped }
            if let safePosition { entries[index].position = safePosition }
            if let safeDuration, safeDuration > 0 { entries[index].duration = safeDuration }
            if media.kind == .series, let episodeID = media.episodeID {
                if let epIndex = entries[index].episodes.firstIndex(where: { $0.id == episodeID }) {
                    entries[index].episodes[epIndex].watchedAt = date
                    if let clamped { entries[index].episodes[epIndex].progress = clamped }
                    if let safePosition { entries[index].episodes[epIndex].position = safePosition }
                    if let safeDuration, safeDuration > 0 { entries[index].episodes[epIndex].duration = safeDuration }
                } else {
                    entries[index].episodes.append(
                        WatchedEpisode(id: episodeID,
                                       seasonTitle: media.seasonTitle ?? "",
                                       label: media.episodeLabel ?? "",
                                       watchedAt: date,
                                       progress: clamped ?? 0,
                                       position: safePosition,
                                       duration: safeDuration)
                    )
                }
            }
        } else {
            var episodes: [WatchedEpisode] = []
            if media.kind == .series, let episodeID = media.episodeID {
                episodes = [WatchedEpisode(id: episodeID,
                                           seasonTitle: media.seasonTitle ?? "",
                                           label: media.episodeLabel ?? "",
                                           watchedAt: date,
                                           progress: clamped ?? 0,
                                           position: safePosition,
                                           duration: safeDuration)]
            }
            entries.append(HistoryEntry(kind: media.kind,
                                        movie: media.movie,
                                        series: media.series,
                                        lastWatchedAt: date,
                                        progress: clamped ?? 0,
                                        episodes: episodes,
                                        position: safePosition,
                                        duration: safeDuration))
        }

        entries.sort { $0.lastWatchedAt > $1.lastWatchedAt }
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func entry(seriesID: Int) -> HistoryEntry? {
        entries.first { $0.kind == .series && $0.series?.id == seriesID }
    }

    func entry(mediaID: Int, kind: MediaKind) -> HistoryEntry? {
        entries.first { $0.kind == kind && $0.mediaID == mediaID }
    }

    /// Seconds to continue a partially watched movie from, or nil when there is nothing to resume.
    func resumePosition(movieID: Int) -> Double? {
        guard let entry = entry(mediaID: movieID, kind: .movie) else { return nil }
        return Self.resumePosition(position: entry.position, duration: entry.duration)
    }

    /// Seconds to continue a specific episode from, or nil when it was finished/never started.
    func resumePosition(seriesID: Int, episodeID: Int) -> Double? {
        guard let watched = watchedEpisode(seriesID: seriesID, episodeID: episodeID) else { return nil }
        return Self.resumePosition(position: watched.position, duration: watched.duration)
    }

    private static func resumePosition(position: Double?, duration: Double?) -> Double? {
        guard let position, let duration, duration > 60 else { return nil }
        guard position > 15, position < duration * 0.98 else { return nil }
        return position
    }

    func watchedEpisodeIDs(seriesID: Int) -> Set<Int> {
        Set(entry(seriesID: seriesID)?.episodes.map(\.id) ?? [])
    }

    func watchedEpisode(seriesID: Int, episodeID: Int) -> WatchedEpisode? {
        entry(seriesID: seriesID)?.episodes.first { $0.id == episodeID }
    }

    func lastWatchedEpisode(seriesID: Int) -> WatchedEpisode? {
        entry(seriesID: seriesID)?.lastEpisode
    }

    func remove(id: Int, kind: MediaKind) {
        entries.removeAll { $0.kind == kind && $0.mediaID == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([HistoryEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.lastWatchedAt > $1.lastWatchedAt }
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Settings

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "هماهنگ با سیستم"
        case .dark: return "تیره"
        case .light: return "روشن"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance); applyAppearance() }
    }
    @Published var fontScale: Double {
        didSet {
            defaults.set(fontScale, forKey: Keys.fontScale)
            AppFont.scale = fontScale
        }
    }
    @Published var preferredQuality: String {
        didSet { defaults.set(preferredQuality, forKey: Keys.quality) }
    }
    @Published var autoPlayBest: Bool {
        didSet { defaults.set(autoPlayBest, forKey: Keys.autoPlayBest) }
    }
    /// Starts the next episode when the current one reaches its end.
    @Published var autoPlayNextEpisode: Bool {
        didSet { defaults.set(autoPlayNextEpisode, forKey: Keys.autoPlayNextEpisode) }
    }
    /// Hides East/South Asian and Arab titles app-wide, except Live TV (see `ContentHiding`).
    @Published var hideRegionalOrigins: Bool {
        didSet { defaults.set(hideRegionalOrigins, forKey: Keys.hideRegionalOrigins) }
    }
    /// Hides Japanese animation app-wide, except Live TV.
    @Published var hideAnime: Bool {
        didSet { defaults.set(hideAnime, forKey: Keys.hideAnime) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let appearance = "ccloud.appearance"
        static let fontScale = "ccloud.fontScale"
        static let quality = "ccloud.preferredQuality"
        static let autoPlayBest = "ccloud.autoPlayBest"
        static let autoPlayNextEpisode = "ccloud.autoPlayNextEpisode"
        static let hideRegionalOrigins = "ccloud.hideRegionalOrigins"
        static let hideAnime = "ccloud.hideAnime"
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Keys.appearance) ?? AppAppearance.dark.rawValue
        appearance = AppAppearance(rawValue: raw) ?? .dark

        let scale = UserDefaults.standard.object(forKey: Keys.fontScale) as? Double ?? 1.0
        fontScale = min(max(scale, 0.85), 1.3)

        preferredQuality = UserDefaults.standard.string(forKey: Keys.quality) ?? "auto"
        autoPlayBest = UserDefaults.standard.object(forKey: Keys.autoPlayBest) as? Bool ?? true
        autoPlayNextEpisode =
            UserDefaults.standard.object(forKey: Keys.autoPlayNextEpisode) as? Bool ?? true
        hideRegionalOrigins =
            UserDefaults.standard.object(forKey: Keys.hideRegionalOrigins) as? Bool ?? false
        hideAnime = UserDefaults.standard.object(forKey: Keys.hideAnime) as? Bool ?? false

        AppFont.scale = fontScale
        applyAppearance()
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    var qualityOptions: [(value: String, title: String)] {
        [("auto", "خودکار (بهترین)"), ("1080", "۱۰۸۰p"), ("720", "۷۲۰p"), ("480", "۴۸۰p")]
    }

    func reset() {
        appearance = .dark
        fontScale = 1.0
        preferredQuality = "auto"
        autoPlayBest = true
        autoPlayNextEpisode = true
        hideRegionalOrigins = false
        hideAnime = false
    }
}
