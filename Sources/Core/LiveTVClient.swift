import Foundation

// MARK: - Live TV data client (Famelack channel dataset, formerly TV Garden)
//
// Data source used by the Flutter "CCloud GUI" live section (livetv_screen.dart / tv_repository.dart).
// The original TV Garden repository was archived in 2026 and its data moved to Famelack; the JSON
// schema also changed (iptv_urls/youtube_urls → sources.streams), so this client speaks the current
// schema with the same two-step flow: countries metadata → per-country channel list.

@MainActor
final class LiveTVClient {

    static let shared = LiveTVClient()

    private let bases = [
        "https://raw.githubusercontent.com/famelack/famelack-data/main/tv",
        "https://cdn.jsdelivr.net/gh/famelack/famelack-data@main/tv"
    ]

    private let session: URLSession
    private var metaCache: (items: [LiveTVCountry], at: Date)?
    private var channelCache: [String: (items: [LiveTVChannel], at: Date)] = [:]
    private var metaInFlight: Task<[LiveTVCountry], Error>?
    private var channelsInFlight: [String: Task<[LiveTVChannel], Error>] = [:]

    private let metaTTL: TimeInterval = 10 * 60
    private let channelsTTL: TimeInterval = 5 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "CCloudMac/2.0 (macOS)"
        ]
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    // MARK: Public API

    func countries() async throws -> [LiveTVCountry] {
        if let cached = metaCache, Date().timeIntervalSince(cached.at) < metaTTL, !cached.items.isEmpty {
            return cached.items
        }
        if let running = metaInFlight { return try await running.value }

        let task = Task<[LiveTVCountry], Error> { [weak self] in
            guard let self else { throw APIError.offline("live") }
            let data = try await self.fetch(path: "/countries_metadata.json")
            let decoded: [String: LiveTVCountryMeta]
            do {
                decoded = try JSONDecoder().decode([String: LiveTVCountryMeta].self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error).prefix(160).description)
            }
            let items = decoded.compactMap { code, meta -> LiveTVCountry? in
                guard meta.hasChannels, meta.channelCount > 0, meta.country.count > 1 else { return nil }
                return LiveTVCountry(code: code.uppercased(),
                                     englishName: meta.country,
                                     channelCount: meta.channelCount)
            }
            guard !items.isEmpty else { throw APIError.empty("live countries") }
            return Self.sortCountries(items)
        }
        metaInFlight = task
        do {
            let items = try await task.value
            metaInFlight = nil
            metaCache = (items, Date())
            return items
        } catch {
            metaInFlight = nil
            throw error
        }
    }

    func channels(countryCode: String) async throws -> [LiveTVChannel] {
        let code = countryCode.lowercased()
        if let cached = channelCache[code], Date().timeIntervalSince(cached.at) < channelsTTL, !cached.items.isEmpty {
            return cached.items
        }
        if let running = channelsInFlight[code] { return try await running.value }

        let task = Task<[LiveTVChannel], Error> { [weak self] in
            guard let self else { throw APIError.offline("live") }
            let data = try await self.fetch(path: "/countries/\(code).json")
            let decoded: [LiveTVChannel]
            do {
                decoded = try JSONDecoder().decode([LiveTVChannel].self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error).prefix(160).description)
            }
            let items = decoded
                .filter { !$0.streams.isEmpty }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard !items.isEmpty else { throw APIError.empty("live channels") }
            return items
        }
        channelsInFlight[code] = task
        do {
            let items = try await task.value
            channelsInFlight[code] = nil
            channelCache[code] = (items, Date())
            return items
        } catch {
            channelsInFlight[code] = nil
            throw error
        }
    }

    func clearCache() {
        metaCache = nil
        channelCache.removeAll()
    }

    // MARK: Internals

    /// Iran first, then Persian-speaking neighbours, then by number of channels.
    static func sortCountries(_ items: [LiveTVCountry]) -> [LiveTVCountry] {
        func rank(_ code: String) -> Int {
            switch code {
            case "IR": return 0
            case "AF": return 1
            case "TJ": return 2
            default: return 3
            }
        }
        return items.sorted { lhs, rhs in
            let l = rank(lhs.code), r = rank(rhs.code)
            if l != r { return l < r }
            if lhs.channelCount != rhs.channelCount { return lhs.channelCount > rhs.channelCount }
            return lhs.persianName.localizedCaseInsensitiveCompare(rhs.persianName) == .orderedAscending
        }
    }

    private func fetch(path: String) async throws -> Data {
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
                return data
            } catch {
                lastError = APIError.offline("live")
            }
        }
        throw lastError
    }
}
