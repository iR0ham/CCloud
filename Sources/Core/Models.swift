import Foundation

// MARK: - API models (exact shapes of the live CCloud backend, tolerant to nulls/missing keys)

struct Genre: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
}

struct Country: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let image: String

    var imageURL: URL? { URL(string: image) }

    enum CodingKeys: String, CodingKey { case id, title, image }

    init(id: Int, title: String, image: String) {
        self.id = id
        self.title = title
        self.image = image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        image = (try? c.decodeIfPresent(String.self, forKey: .image)) ?? ""
    }
}

struct MediaSource: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let quality: String?
    let type: String
    let url: String

    /// Normalised type: "mkv", "mp4", "m3u8", "dash", …
    var kind: String {
        let t = type.lowercased()
        if t.contains("mkv") || t.contains("matroska") { return "mkv" }
        if t.contains("m3u8") || t.contains("hls") { return "hls" }
        if t.contains("mpd") || t.contains("dash") { return "dash" }
        if t.contains("mp4") || t.contains("m4v") { return "mp4" }
        return t
    }

    /// Can AVPlayer open this URL without a remux step?
    var isDirectPlayable: Bool { kind == "mp4" || kind == "hls" || kind == "dash" }

    /// Progressive file that can be saved as a single download (playlists like HLS/DASH cannot).
    var isFileDownloadable: Bool {
        ["mp4", "mkv", "webm", "avi", "mov"].contains(kind)
    }

    var downloadFileExtension: String {
        if isFileDownloadable { return kind }
        let ext = urlValue?.pathExtension.lowercased() ?? ""
        return ext.isEmpty ? "mp4" : ext
    }

    /// Persian-friendly label: quality string or the type when quality is null.
    var qualityLabel: String {
        if let q = quality?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty, q != "null" {
            return q
        }
        return kind.uppercased()
    }

    /// Short human label such as "720p" extracted from a quality string like "720 زیرنویس".
    var resolutionLabel: String? {
        guard let q = quality else { return nil }
        if let r = q.range(of: #"[0-9]{3,4}"#, options: .regularExpression) {
            let digits = String(q[r])
            if digits.count == 3 { return digits + "p" }
            if digits.count == 4 { return String(digits.prefix(3)) + "p" }
        }
        return nil
    }

    var kindLabel: String {
        switch kind {
        case "mkv": return "MKV"
        case "mp4": return "MP4"
        case "hls": return "HLS"
        case "dash": return "DASH"
        default: return kind.uppercased()
        }
    }

    var urlValue: URL? { URL(string: url) }

    enum CodingKeys: String, CodingKey { case id, quality, type, url }

    init(id: Int, quality: String?, type: String, url: String) {
        self.id = id
        self.quality = quality
        self.type = type
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        quality = (try? c.decodeIfPresent(String.self, forKey: .quality)) ?? nil
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
    }
}

struct Movie: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let type: String
    let title: String
    let description: String
    let year: Int
    let imdb: Double
    let rating: Double
    let duration: String?
    let image: String
    let cover: String
    let genres: [Genre]
    let sources: [MediaSource]
    let country: [Country]

    var isSeries: Bool { type.lowercased() == "serie" || type.lowercased() == "series" }

    var posterURL: URL? { URL(string: image) }
    var coverURL: URL? { URL(string: cover) }
    var bestBackdropURL: URL? { URL(string: cover) ?? URL(string: image) }

    var yearText: String { year > 0 ? String(year) : "" }
    var imdbText: String { imdb > 0 ? String(format: "%.1f", imdb) : "" }
    var durationText: String? {
        guard let d = duration, !d.isEmpty, d != "null" else { return nil }
        return d
    }
    var countryText: String { country.map(\.title).joined(separator: "، ") }
    var genreText: String { genres.map(\.title).joined(separator: " • ") }

    var playableSources: [MediaSource] {
        sources.filter { !$0.url.isEmpty && !$0.qualityLabel.contains("تیزر") }
    }
    var hasOnlyTrailer: Bool {
        sources.allSatisfy { $0.qualityLabel.contains("تیزر") } && !sources.isEmpty
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, type, title, description, year, imdb, rating, duration
        case image, cover, genres, sources, country
    }

    init(id: Int, type: String, title: String, description: String, year: Int,
         imdb: Double, rating: Double, duration: String?, image: String, cover: String,
         genres: [Genre], sources: [MediaSource], country: [Country]) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.year = year
        self.imdb = imdb
        self.rating = rating
        self.duration = duration
        self.image = image
        self.cover = cover
        self.genres = genres
        self.sources = sources
        self.country = country
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "movie"
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        year = (try? c.decodeIfPresent(Int.self, forKey: .year)) ?? 0
        imdb = (try? c.decodeIfPresent(Double.self, forKey: .imdb)) ?? 0
        rating = (try? c.decodeIfPresent(Double.self, forKey: .rating)) ?? 0
        duration = (try? c.decodeIfPresent(String.self, forKey: .duration)) ?? nil
        image = (try? c.decodeIfPresent(String.self, forKey: .image)) ?? ""
        cover = (try? c.decodeIfPresent(String.self, forKey: .cover)) ?? ""
        genres = (try? c.decodeIfPresent([Genre].self, forKey: .genres)) ?? []
        sources = (try? c.decodeIfPresent([MediaSource].self, forKey: .sources)) ?? []
        country = (try? c.decodeIfPresent([Country].self, forKey: .country)) ?? []
    }
}

struct Series: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let type: String
    let title: String
    let description: String
    let year: Int
    let imdb: Double
    let rating: Double
    let duration: String?
    let image: String
    let cover: String
    let genres: [Genre]
    let country: [Country]

    var posterURL: URL? { URL(string: image) }
    var coverURL: URL? { URL(string: cover) }
    var bestBackdropURL: URL? { URL(string: cover) ?? URL(string: image) }
    var yearText: String { year > 0 ? String(year) : "" }
    var imdbText: String { imdb > 0 ? String(format: "%.1f", imdb) : "" }
    var durationText: String? {
        guard let d = duration, !d.isEmpty, d != "null" else { return nil }
        return d
    }
    var countryText: String { country.map(\.title).joined(separator: "، ") }
    var genreText: String { genres.map(\.title).joined(separator: " • ") }

    init(from movie: Movie) {
        self.init(id: movie.id, type: "serie", title: movie.title, description: movie.description,
                  year: movie.year, imdb: movie.imdb, rating: movie.rating, duration: movie.duration,
                  image: movie.image, cover: movie.cover, genres: movie.genres, country: movie.country)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, title, description, year, imdb, rating, duration
        case image, cover, genres, country
    }

    init(id: Int, type: String, title: String, description: String, year: Int,
         imdb: Double, rating: Double, duration: String?, image: String, cover: String,
         genres: [Genre], country: [Country]) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.year = year
        self.imdb = imdb
        self.rating = rating
        self.duration = duration
        self.image = image
        self.cover = cover
        self.genres = genres
        self.country = country
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "serie"
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        year = (try? c.decodeIfPresent(Int.self, forKey: .year)) ?? 0
        imdb = (try? c.decodeIfPresent(Double.self, forKey: .imdb)) ?? 0
        rating = (try? c.decodeIfPresent(Double.self, forKey: .rating)) ?? 0
        duration = (try? c.decodeIfPresent(String.self, forKey: .duration)) ?? nil
        image = (try? c.decodeIfPresent(String.self, forKey: .image)) ?? ""
        cover = (try? c.decodeIfPresent(String.self, forKey: .cover)) ?? ""
        genres = (try? c.decodeIfPresent([Genre].self, forKey: .genres)) ?? []
        country = (try? c.decodeIfPresent([Country].self, forKey: .country)) ?? []
    }
}

extension Movie {
    /// Screens that mix films and series (home rails, genre pages) share one poster model, so a
    /// series payload is converted into the poster-shaped `Movie` (type "serie", no sources).
    init(from series: Series) {
        self.init(id: series.id, type: "serie", title: series.title,
                  description: series.description, year: series.year, imdb: series.imdb,
                  rating: series.rating, duration: series.duration, image: series.image,
                  cover: series.cover, genres: series.genres, sources: [], country: series.country)
    }
}

struct Season: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let episodes: [Episode]

    enum CodingKeys: String, CodingKey { case id, title, episodes }

    init(id: Int, title: String, episodes: [Episode]) {
        self.id = id
        self.title = title
        self.episodes = episodes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        episodes = (try? c.decodeIfPresent([Episode].self, forKey: .episodes)) ?? []
    }
}

struct Episode: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let description: String?
    let duration: String?
    let image: String?
    let sources: [MediaSource]

    var episodeNumber: Int? {
        let digits = title.replacingOccurrences(of: #"[^0-9\u{06F0}-\u{06F9}]"#, with: "", options: .regularExpression)
        let latin = digits.applyingTransform(StringTransform("Arabic-->Latin"), reverse: false) ?? digits
        return Int(latin)
    }

    var playableSources: [MediaSource] {
        sources.filter { !$0.url.isEmpty && !$0.qualityLabel.contains("تیزر") }
    }

    enum CodingKeys: String, CodingKey { case id, title, description, duration, image, sources }

    init(id: Int, title: String, description: String?, duration: String?, image: String?,
         sources: [MediaSource]) {
        self.id = id
        self.title = title
        self.description = description
        self.duration = duration
        self.image = image
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? nil
        duration = (try? c.decodeIfPresent(String.self, forKey: .duration)) ?? nil
        image = (try? c.decodeIfPresent(String.self, forKey: .image)) ?? nil
        sources = (try? c.decodeIfPresent([MediaSource].self, forKey: .sources)) ?? []
    }
}

// MARK: - Shared helpers

enum MediaKind: String, Codable, Hashable, Sendable {
    case movie, series
}

enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case newest, year, imdb

    var id: String { rawValue }

    var apiPath: String {
        switch self {
        case .newest: return "created"
        case .year: return "year"
        case .imdb: return "imdb"
        }
    }

    var title: String {
        switch self {
        case .newest: return "جدیدترین"
        case .year: return "سال ساخت"
        case .imdb: return "امتیاز IMDb"
        }
    }

    var icon: String {
        switch self {
        case .newest: return "sparkles"
        case .year: return "calendar"
        case .imdb: return "star"
        }
    }
}

/// Identity of the title being played, so the player can feed the watch-history store.
/// Live TV and local-file demo playback have no info and are never recorded.
struct PlaybackInfo: Codable, Hashable, Sendable {
    let kind: MediaKind
    let movie: Movie?
    let series: Series?
    let episodeID: Int?
    let seasonTitle: String?
    let episodeLabel: String?

    init(kind: MediaKind, movie: Movie? = nil, series: Series? = nil,
         episodeID: Int? = nil, seasonTitle: String? = nil, episodeLabel: String? = nil) {
        self.kind = kind
        self.movie = movie
        self.series = series
        self.episodeID = episodeID
        self.seasonTitle = seasonTitle
        self.episodeLabel = episodeLabel
    }

    var mediaID: Int { movie?.id ?? series?.id ?? 0 }
}

/// One queued episode the player can advance to (series playback only).
struct PlaybackEpisode: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let subtitle: String
    let posterURL: String?
    let sources: [MediaSource]
    let preferredSourceID: Int?
    let episodeID: Int?
    let seasonTitle: String?
    let episodeLabel: String?

    init(id: Int, subtitle: String, posterURL: String? = nil,
         sources: [MediaSource], preferredSourceID: Int? = nil,
         episodeID: Int? = nil, seasonTitle: String? = nil, episodeLabel: String? = nil) {
        self.id = id
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.sources = sources
        self.preferredSourceID = preferredSourceID
        self.episodeID = episodeID
        self.seasonTitle = seasonTitle
        self.episodeLabel = episodeLabel
    }
}

struct PlaybackRequest: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let title: String
    let subtitle: String?
    let posterURL: String?
    let sources: [MediaSource]
    let preferredSourceID: Int?
    /// Title identity for the watch-history store.
    let media: PlaybackInfo?
    /// Episodes that follow the current one, in order (empty for movies and live TV).
    let upcomingEpisodes: [PlaybackEpisode]
    /// Seconds to start from, used when continuing a partially watched title.
    let startAt: Double

    init(title: String, subtitle: String? = nil, posterURL: String? = nil,
         sources: [MediaSource], preferredSourceID: Int? = nil,
         media: PlaybackInfo? = nil,
         upcomingEpisodes: [PlaybackEpisode] = [],
         startAt: Double = 0) {
        self.id = UUID()
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.sources = sources
        self.preferredSourceID = preferredSourceID
        self.media = media
        self.upcomingEpisodes = upcomingEpisodes
        self.startAt = max(0, startAt)
    }

    var nextEpisode: PlaybackEpisode? { upcomingEpisodes.first }

    /// The request that plays the next queued episode, or `nil` when the queue is empty.
    func advancingToNextEpisode() -> PlaybackRequest? {
        guard let next = upcomingEpisodes.first else { return nil }
        let nextMedia = media.map { info in
            PlaybackInfo(kind: info.kind,
                         movie: info.movie,
                         series: info.series,
                         episodeID: next.episodeID ?? next.id,
                         seasonTitle: next.seasonTitle ?? info.seasonTitle,
                         episodeLabel: next.episodeLabel ?? info.episodeLabel)
        }
        return PlaybackRequest(title: title,
                               subtitle: next.subtitle,
                               posterURL: next.posterURL ?? posterURL,
                               sources: next.sources,
                               preferredSourceID: next.preferredSourceID,
                               media: nextMedia,
                               upcomingEpisodes: Array(upcomingEpisodes.dropFirst()))
    }
}

enum APIError: LocalizedError {
    case offline(String)
    case http(Int)
    case decoding(String)
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .offline(let detail):
            return "اتصال به سرور برقرار نشد" + (detail.isEmpty ? "" : " (\(detail))")
        case .http(let code):
            return "خطای سرور (کد \(code))"
        case .decoding(let detail):
            return "داده‌های دریافتی نامعتبر بود" + (detail.isEmpty ? "" : " (\(detail))")
        case .empty(let what):
            return "محتوایی برای نمایش پیدا نشد" + (what.isEmpty ? "" : " (\(what))")
        }
    }
}

extension Array where Element == MediaSource {
    /// Sources worth showing to the user (no trailers), best quality first.
    var playable: [MediaSource] {
        filter { !$0.url.isEmpty && !$0.qualityLabel.contains("تیزر") }
    }

    /// Pick the preferred source by the user quality setting, falling back sensibly.
    func preferred(for qualityPreference: String) -> MediaSource? {
        let list = playable
        guard !list.isEmpty else { return nil }
        let pref = qualityPreference == "auto" ? "" : qualityPreference
        if !pref.isEmpty, let hit = list.first(where: { ($0.resolutionLabel ?? "").hasPrefix(pref) }) {
            return hit
        }
        // 1080 → 720 → 480 → first
        for want in ["1080p", "720p", "480p"] {
            if let hit = list.first(where: { ($0.resolutionLabel ?? "") == want }) { return hit }
        }
        return list.first
    }
}
