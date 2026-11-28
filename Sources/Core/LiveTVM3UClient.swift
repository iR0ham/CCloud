import Foundation

// MARK: - iptv-org playlists (secondary Live TV source)
//
// Famelack lists 62 Iranian channels; iptv-org tracks about 183 for Iran plus a Persian-language
// playlist. LiveTVCatalog uses those playlists only for backup stream URLs on famelack's rows —
// iptv-org's extra channels are mostly diaspora or dead links, so they never reach the list.

@MainActor
final class LiveTVM3UClient {

    static let shared = LiveTVM3UClient()

    private let bases = [
        "https://iptv-org.github.io/iptv",
        "https://cdn.jsdelivr.net/gh/iptv-org/iptv@gh-pages"
    ]

    private let session: URLSession
    private var cache: [String: (items: [LiveTVM3U.Entry], at: Date)] = [:]
    private var inFlight: [String: Task<[LiveTVM3U.Entry], Error>] = [:]

    private let ttl: TimeInterval = 15 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "Accept": "audio/x-mpegurl",
            "User-Agent": "CCloudMac/2.0 (macOS)"
        ]
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }

    // MARK: Public API

    /// Channels registered under a country, e.g. "ir" → /countries/ir.m3u
    func countryChannels(_ code: String) async throws -> [LiveTVM3U.Entry] {
        try await playlist(path: "/countries/\(code.lowercased()).m3u")
    }

    /// Channels speaking a language, e.g. "fas" → /languages/fas.m3u
    func languageChannels(_ code: String) async throws -> [LiveTVM3U.Entry] {
        try await playlist(path: "/languages/\(code.lowercased()).m3u")
    }

    func clearCache() {
        cache.removeAll()
        inFlight.removeAll()
    }

    // MARK: Internals

    private func playlist(path: String) async throws -> [LiveTVM3U.Entry] {
        if let cached = cache[path], Date().timeIntervalSince(cached.at) < ttl, !cached.items.isEmpty {
            return cached.items
        }
        if let running = inFlight[path] { return try await running.value }

        let task = Task<[LiveTVM3U.Entry], Error> { [weak self] in
            guard let self else { throw APIError.offline("live") }
            let text = try await self.fetchText(path: path)
            let items = LiveTVM3U.parse(text)
            guard !items.isEmpty else { throw APIError.empty("live channels") }
            return items
        }
        inFlight[path] = task
        do {
            let items = try await task.value
            inFlight[path] = nil
            cache[path] = (items, Date())
            return items
        } catch {
            inFlight[path] = nil
            throw error
        }
    }

    private func fetchText(path: String) async throws -> String {
        var lastError: Error = APIError.offline("live")
        for base in bases {
            guard let url = URL(string: base + path) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = APIError.offline("live")
                    continue
                }
                if http.statusCode == 404 {
                    lastError = APIError.empty("live")
                    continue
                }
                guard (200..<300).contains(http.statusCode), !data.isEmpty else {
                    lastError = APIError.http(http.statusCode)
                    continue
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    throw APIError.decoding("m3u")
                }
                return text
            } catch {
                lastError = error is APIError ? error : APIError.offline("live")
            }
        }
        throw lastError
    }
}

// MARK: - Playlist parsing

enum LiveTVM3U {

    /// One channel, with every stream URL that shares its tvg-id (quality variants included).
    struct Entry: Sendable {
        let id: String
        let name: String
        let countryCode: String
        let group: String
        var streams: [String]

        func channel(languages: [String], country: String) -> LiveTVChannel {
            LiveTVChannel(nanoid: "iptvorg:" + id,
                          name: name,
                          sources: LiveTVStreams(streams: streams),
                          languages: languages,
                          country: country,
                          isGeoBlocked: false)
        }
    }

    static func parse(_ text: String) -> [Entry] {
        var order: [String] = []
        var entries: [String: Entry] = [:]
        var pending: Entry?

        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXTINF:") {
                pending = entry(from: trimmed)
                continue
            }
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), var channel = pending else { continue }
            pending = nil
            if !channel.streams.contains(trimmed) {
                channel.streams.append(trimmed)
            }
            if entries[channel.id] == nil { order.append(channel.id) }
            entries[channel.id] = channel
        }

        return order.compactMap { entries[$0] }.filter { !$0.streams.isEmpty }
    }

    /// `#EXTINF:-1 tvg-id="AbadanTV.ir@SD" tvg-logo="…" group-title="General",Abadan TV`
    private static func entry(from line: String) -> Entry? {
        guard let comma = line.lastIndex(of: ",") else { return nil }
        let name = LiveTVM3UText.displayName(String(line[line.index(after: comma)...]))
        guard !name.isEmpty else { return nil }

        let identifier = attribute("tvg-id", in: line)
        var base = identifier
        if let at = base.firstIndex(of: "@") { base = String(base[base.startIndex..<at]) }
        var countryCode = ""
        if let dot = base.lastIndex(of: ".") {
            countryCode = String(base[base.index(after: dot)...]).uppercased()
            base = String(base[base.startIndex..<dot])
        }
        let id = base.isEmpty ? "name:" + LiveTVNameKey.key(name) : base
        return Entry(id: id,
                     name: name,
                     countryCode: countryCode,
                     group: attribute("group-title", in: line),
                     streams: [])
    }

    private static func attribute(_ name: String, in line: String) -> String {
        guard let start = line.range(of: name + "=\"") else { return "" }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[rest.startIndex..<end])
    }

    // The display-name text rule (`displayName`/`isNoise`) now lives in `LiveTVM3UText.swift`,
    // unchanged: that file has no dependencies, so the headless contract harness can compile and pin
    // it together with the multi-source parser, and both Live TV paths then share one recipe instead
    // of two that could drift.
}

// MARK: - Name matching

enum LiveTVNameKey {

    /// The two datasets spell the same channel differently ("Press TV (720p)" vs "Press TV"), so
    /// matching ignores punctuation, case, diacritics and the Arabic/Persian letter variants.
    static func key(_ name: String) -> String {
        let cleaned = name.folding(options: [.diacriticInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        var scalars = String.UnicodeScalarView()
        for scalar in cleaned.unicodeScalars {
            switch scalar.value {
            case 0x064A, 0x0626, 0x0649: scalars.append(scalarValue(0x06CC))          // ي ئ ى → ی
            case 0x0643: scalars.append(scalarValue(0x06A9))                           // ك → ک
            case 0x0629: scalars.append(scalarValue(0x0647))                           // ة → ه
            case 0x0622, 0x0623, 0x0625, 0x0671: scalars.append(scalarValue(0x0627))   // آ أ إ ٱ → ا
            case 0x0624: scalars.append(scalarValue(0x0648))                           // ؤ → و
            case 0x200C, 0x200D, 0x00A0: scalars.append(" ")
            case 0x06F0...0x06F9: scalars.append(scalarValue(0x0030 + scalar.value - 0x06F0))
            case 0x0660...0x0669: scalars.append(scalarValue(0x0030 + scalar.value - 0x0660))
            default: scalars.append(scalar)
            }
        }

        var key = ""
        var pendingSpace = false
        for scalar in String(scalars).unicodeScalars {
            let value = scalar.value
            let isKept = (value >= 0x30 && value <= 0x39)
                || (value >= 0x61 && value <= 0x7A)
                || (value >= 0x0600 && value <= 0x06FF)
            if isKept {
                if pendingSpace, !key.isEmpty { key.append(" ") }
                key.unicodeScalars.append(scalar)
                pendingSpace = false
            } else {
                pendingSpace = true
            }
        }
        return key
    }

    private static func scalarValue(_ value: UInt32) -> UnicodeScalar { UnicodeScalar(value) ?? " " }
}
