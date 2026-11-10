import Foundation
import CryptoKit

// MARK: - HTTP client for the CCloud backend
//
// The Android app talks to three interchangeable API hosts (the "helper servers" only mirror the
// primary). Everything below is verified against the live backend:
//
// * Hosts are tried in fallback order (`server-hi-speed-iran.info` → `hostinnegar.com` →
//   `windowsdiba.info`); the URL path is identical for every host and the host is substituted.
//   A host that answers is remembered and used first from then on, and `onBackendChange` reports it.
// * `windowsdiba.info` currently has no DNS record at all (NXDOMAIN), so it is a last resort only.
// * The server always answers JSON but labels it `content-type: text/html`; never trust the header.
//   Occasionally it serves an HTML error page with a 2xx status — those are treated as transient.
// * Paths must keep their trailing slash; without it the server answers 301 (URLSession follows
//   redirects, but the trailing slash saves a round trip).
// * `Search` is a plain path segment: `URLEncoder`-style UTF-8 percent-encoding, spaces as `%20`.
//   A raw `/` inside the query breaks routing (404), and Arabic `ي`/`ك` must be normalised to
//   Persian `ی`/`ک` — the catalogue is stored with Persian letters only.
// * `page` is 0-based, 30 items per page; out-of-range pages return `[]` (200), so empty arrays
//   are legal for paginated endpoints (they are NOT for genres/countries).
// * Times: values arrive as either `int` or `double`; `duration` can be `null` or the string
//   `"null"`. Models.swift decodes all of that tolerantly and this client never re-shapes payloads.
//
// Resilience layers, from cheapest to most expensive:
//   1. in-memory TTL cache (75 s) so tab switches do not refetch the same page,
//   2. in-flight de-duplication — concurrent calls for the same path share one `Task`,
//   3. host fallback with one retry per host for transient failures (timeouts / 5xx / 408 / 429),
//   4. an overall deadline so a dead network cannot block the UI for minutes,
//   5. an on-disk copy of the last successful payload per path, served only when every host fails
//      (`onConnectivityChange` reports the transition so the UI can show an offline badge).

@MainActor
final class APIClient {

    static let shared = APIClient()

    // MARK: Public surface

    /// Called whenever the active backend host is known/changed (shown in the sidebar).
    var onBackendChange: ((String) -> Void)?

    /// Called when the API starts serving fresh data (`true`) or the on-disk fallback (`false`).
    var onConnectivityChange: ((Bool) -> Void)?

    let apiKey = "4F5A9C3D9A86FA54EACEDDD635185"
    let hosts = ["server-hi-speed-iran.info", "hostinnegar.com", "windowsdiba.info"]

    /// Host that produced the most recent successful response (diagnostics + QA).
    private(set) var activeHost: String

    /// Number of real network round-trips performed so far (diagnostics + verification harness).
    /// `resetMetrics()` clears this counter.
    private(set) var networkRequestCount = 0

    /// Cumulative network round-trips; never cleared by `resetMetrics()`.
    private(set) var totalNetworkRequestCount = 0

    // MARK: Tuning

    private static let requestTimeout: TimeInterval = 30
    private static let resourceTimeout: TimeInterval = 45
    private static let overallTimeout: TimeInterval = 120
    private static let retryDelay: TimeInterval = 0.35
    private static let cacheTTL: TimeInterval = 75
    private static let maxCacheEntries = 64
    private static let maxCacheEntryBytes = 4 * 1024 * 1024
    private static let maxSearchQueryLength = 120
    private static let maxOfflineEntries = 240

    /// Hosts whose `uploads/...` paths are mirrors of each other; poster URLs may be rewritten
    /// to whichever host is currently reachable.
    private static let knownAPIHosts: Set<String> = [
        "server-hi-speed-iran.info", "www.server-hi-speed-iran.info",
        "hostinnegar.com", "www.hostinnegar.com",
        "windowsdiba.info", "www.windowsdiba.info"
    ]

    // MARK: State

    private var preferredHostIndex = 0
    private var reportedHost: String?
    private var reportedOnline: Bool?
    private let session: URLSession
    private let offlineDirectory: URL

    private struct CachedResponse {
        let data: Data
        let storedAt: Date
    }

    private var cache: [String: CachedResponse] = [:]
    private var inFlight: [String: Task<Data, Error>] = [:]

    // MARK: Init

    private init() {
        activeHost = hosts[0]

        // Ephemeral configuration: no HTTP cache on disk or in memory, no cookies, no credentials.
        // Combined with `Cache-Control: no-cache` this guarantees stale API payloads are never used.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = Self.resourceTimeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "CCloudMac/2.0 (macOS)"
        ]
        session = URLSession(configuration: config)

        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("CCloudMac", isDirectory: true)
            .appendingPathComponent("offline-cache", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        offlineDirectory = dir
    }

    // MARK: - Endpoints

    func genres() async throws -> [Genre] {
        let items: [Genre] = try await fetchList(path: genresPath, endpoint: "genres")
        guard !items.isEmpty else { throw APIError.empty("ژانرها") }
        return Self.dedupe(items, key: { "\($0.id)" })
    }

    func movies(page: Int, genreId: Int = 0, sort: SortOption = .newest) async throws -> [Movie] {
        let safePage = max(0, page)
        let safeGenre = max(0, genreId)
        let path = "/api/movie/by/filtres/\(safeGenre)/\(sort.apiPath)/\(safePage)/\(apiKey)/"
        let items: [Movie] = try await fetchList(path: path, endpoint: "movies")
        return Self.dedupe(items, key: { "\($0.type.lowercased()):\($0.id)" })
    }

    func series(page: Int, genreId: Int = 0, sort: SortOption = .newest) async throws -> [Series] {
        let safePage = max(0, page)
        let safeGenre = max(0, genreId)
        let path = "/api/serie/by/filtres/\(safeGenre)/\(sort.apiPath)/\(safePage)/\(apiKey)/"
        let items: [Series] = try await fetchList(path: path, endpoint: "series")
        return Self.dedupe(items, key: { "\($0.type.lowercased()):\($0.id)" })
    }

    func seasons(seriesId: Int) async throws -> [Season] {
        guard seriesId > 0 else { throw APIError.empty("شناسه سریال نامعتبر") }
        let path = "/api/season/by/serie/\(seriesId)/\(apiKey)/"
        let items: [Season] = try await fetchList(path: path, endpoint: "seasons")
        return Self.dedupe(items, key: { "\($0.id)" })
    }

    /// Search returns poster-shaped payloads (movie *and* serie). The UI converts serie items with
    /// `Series(from:)`. `channels` in the envelope is ignored.
    func search(query: String) async throws -> [Movie] {
        let normalized = Self.normalizedSearchQuery(query)
        guard !normalized.isEmpty else { return [] }
        let encoded = Self.urlEncodedPathComponent(normalized)
        let path = "/api/search/\(encoded)/\(apiKey)/"
        let items: [Movie] = try await fetchList(path: path, endpoint: "search")
        return Self.dedupe(items, key: { "\($0.type.lowercased()):\($0.id)" })
    }

    func countries() async throws -> [Country] {
        let items: [Country] = try await fetchList(path: countriesPath, endpoint: "countries")
        guard !items.isEmpty else { throw APIError.empty("کشورها") }
        return Self.dedupe(items, key: { "\($0.id)" })
    }

    func countryPosters(countryId: Int, page: Int, sort: SortOption = .newest) async throws -> [Movie] {
        guard countryId > 0 else { throw APIError.empty("شناسه کشور نامعتبر") }
        let safePage = max(0, page)
        let path = "/api/poster/by/filtres/0/\(countryId)/\(sort.apiPath)/\(safePage)/\(apiKey)/"
        let items: [Movie] = try await fetchList(path: path, endpoint: "country posters")
        return Self.dedupe(items, key: { "\($0.type.lowercased()):\($0.id)" })
    }

    /// Lightweight backend probe (genres request, cache bypassed). Never throws.
    func healthCheck() async -> Bool {
        do {
            let items: [Genre] = try await fetchList(path: genresPath,
                                                     endpoint: "health",
                                                     allowCache: false)
            return !items.isEmpty
        } catch {
            return false
        }
    }

    /// Resolve a poster/cover/country-image field to a usable URL:
    /// * `""`, `"null"`, `"N/A"` → `nil` (never hand the UI an empty URL),
    /// * relative paths (`/uploads/…`) are resolved against the active host,
    /// * absolute URLs on any known API host are rewritten to the active host, because every
    ///   helper host mirrors `/uploads` and the primary may be unreachable,
    /// * non-HTTP values (e.g. `data:` or junk) → `nil`.
    func posterImageURL(_ path: String) -> URL? {
        var raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.lowercased() == "null" || raw.lowercased() == "n/a" { return nil }

        // Defensive: JSON escapes are already decoded by JSONDecoder, but tolerate paste-ins.
        raw = raw.replacingOccurrences(of: "\\/", with: "/")
        raw = raw.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")

        // Reject non-HTTP schemes (data:, file:, mailto:, Windows drive letters, …) before the
        // relative-path heuristics below can turn them into a bogus https URL.
        if let scheme = URLComponents(string: raw)?.scheme?.lowercased(),
           scheme != "http", scheme != "https" {
            return nil
        }

        let lower = raw.lowercased()
        if lower.hasPrefix("//") {
            raw = "https:" + raw
        } else if raw.hasPrefix("/") {
            raw = "https://\(activeHost)\(raw)"
        } else if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            raw = "https://\(activeHost)/\(raw)"
        }

        // Percent-encode spaces / non-ASCII (some image fields contain Persian file names).
        let sanitized = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? raw
        guard var components = URLComponents(string: sanitized) else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        if let host = components.host?.lowercased(), Self.knownAPIHosts.contains(host) {
            components.host = activeHost
            components.scheme = "https"
        }
        return components.url
    }

    // MARK: - Harness / diagnostics hooks (internal, not part of the app-facing API)

    /// Drop every cached response (used after switching the preferred host in tests).
    func invalidateCache() {
        cache.removeAll(keepingCapacity: false)
    }

    /// Force the first host used for the next request (the fallback order still applies afterwards).
    func preferHost(_ host: String) {
        guard let index = hosts.firstIndex(where: { $0.caseInsensitiveCompare(host) == .orderedSame })
        else { return }
        preferredHostIndex = index
    }

    /// Reset the round-trip counter (diagnostics).
    func resetMetrics() {
        networkRequestCount = 0
    }

    // MARK: - Paths

    private var genresPath: String { "/api/genre/all/\(apiKey)/" }
    private var countriesPath: String { "/api/country/all/\(apiKey)/" }

    // MARK: - Fetch pipeline (cache → in-flight → hosts)

    private func fetchList<T: Decodable>(path: String,
                                         endpoint: String,
                                         allowCache: Bool = true) async throws -> [T] {
        let data = try await fetchData(path: path, allowCache: allowCache)
        return try Self.decodeList(data, endpoint: endpoint)
    }

    private func fetchData(path: String, allowCache: Bool) async throws -> Data {
        try Task.checkCancellation()

        if allowCache, let cached = cachedData(for: path) {
            return cached
        }
        if let running = inFlight[path] {
            // In-flight de-duplication: one network request serves every concurrent caller.
            return try await running.value
        }

        let task = Task<Data, Error> { [weak self] in
            guard let self else { throw APIError.offline("") }
            do {
                let data = try await self.performFetch(path: path)
                self.storeCached(data, for: path)
                if allowCache { self.storeOfflineCopy(data, for: path) }
                self.inFlight[path] = nil
                return data
            } catch {
                self.inFlight[path] = nil
                guard !(error is CancellationError) else { throw error }
                if allowCache, let fallback = self.offlineCopy(for: path) {
                    self.reportConnectivity(online: false)
                    return fallback
                }
                throw error
            }
        }
        inFlight[path] = task
        return try await task.value
    }

    private func performFetch(path: String) async throws -> Data {
        let deadline = Date().addingTimeInterval(Self.overallTimeout)
        var retryHosts: [Int] = []
        var lastTransient: APIError?
        var lastPermanent: APIError?

        // Pass 0 walks every host in fallback order; pass 1 retries (once) the hosts that failed
        // transiently. This keeps availability first: a dead primary costs one timeout, not two.
        for pass in 0..<2 {
            if pass == 1 {
                guard !retryHosts.isEmpty else { break }
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.retryDelay * 1_000_000_000))
                } catch {
                    throw CancellationError()
                }
            }

            let order: [Int] = pass == 0
                ? (0..<hosts.count).map { (preferredHostIndex + $0) % hosts.count }
                : retryHosts

            for index in order {
                if Task.isCancelled { throw CancellationError() }
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 1 { break }

                let timeout = min(Self.requestTimeout, max(3, remaining))
                do {
                    let data = try await fetchOnce(host: hosts[index], path: path, timeout: timeout)
                    noteSuccess(hostIndex: index)
                    return data
                } catch let failure as AttemptFailure {
                    switch failure {
                    case .transient(let error):
                        lastTransient = error
                        if pass == 0, !retryHosts.contains(index) { retryHosts.append(index) }
                    case .permanent(let error):
                        lastPermanent = error
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastTransient = APIError.offline("خطای نامشخص شبکه")
                }
            }
        }

        if let error = lastPermanent { throw error }
        if let error = lastTransient { throw error }
        throw APIError.offline("هیچ‌کدام از سرورها پاسخ ندادند")
    }

    /// One HTTP round-trip. Throws `AttemptFailure` so the caller knows whether the host is worth
    /// retrying; cancellation is re-thrown as `CancellationError`.
    private func fetchOnce(host: String, path: String, timeout: TimeInterval) async throws -> Data {
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw AttemptFailure.permanent(.offline("آدرس نامعتبر"))
        }

        var request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        networkRequestCount += 1
        totalNetworkRequestCount += 1

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw AttemptFailure.transient(.offline(Self.persianDetail(for: error)))
        } catch {
            throw AttemptFailure.transient(.offline("خطای شبکه"))
        }

        guard let http = response as? HTTPURLResponse else {
            throw AttemptFailure.transient(.offline("پاسخ نامعتبر از سرور"))
        }

        let status = http.statusCode
        if status == 408 || status == 429 || status >= 500 {
            throw AttemptFailure.transient(.http(status))
        }
        guard (200..<300).contains(status) else {
            throw AttemptFailure.permanent(.http(status))
        }
        guard !data.isEmpty else {
            throw AttemptFailure.transient(.empty(host))
        }
        // Some backend failures are served as an HTML page with a 2xx status.
        if Self.firstSignificantByte(in: data) == UInt8(ascii: "<") {
            throw AttemptFailure.transient(.http(502))
        }
        return data
    }

    private func noteSuccess(hostIndex index: Int) {
        preferredHostIndex = index
        let host = hosts[index]
        activeHost = host
        if reportedHost != host {
            reportedHost = host
            onBackendChange?(host)
        }
        reportConnectivity(online: true)
    }

    private func reportConnectivity(online: Bool) {
        guard reportedOnline != online else { return }
        reportedOnline = online
        onConnectivityChange?(online)
    }

    // MARK: - Memory cache

    private func cachedData(for path: String) -> Data? {
        guard let entry = cache[path] else { return nil }
        if Date().timeIntervalSince(entry.storedAt) <= Self.cacheTTL {
            return entry.data
        }
        cache[path] = nil
        return nil
    }

    private func storeCached(_ data: Data, for path: String) {
        guard data.count <= Self.maxCacheEntryBytes else { return }
        cache[path] = CachedResponse(data: data, storedAt: Date())
        guard cache.count > Self.maxCacheEntries else { return }
        if let oldest = cache.min(by: { $0.value.storedAt < $1.value.storedAt }) {
            cache[oldest.key] = nil
        }
    }

    // MARK: - Disk fallback (last successful payload per path)

    private func offlineCopy(for path: String) -> Data? {
        guard let data = try? Data(contentsOf: offlineFileURL(for: path)), !data.isEmpty else {
            return nil
        }
        return data
    }

    private func storeOfflineCopy(_ data: Data, for path: String) {
        guard data.count <= Self.maxCacheEntryBytes else { return }
        let url = offlineFileURL(for: path)
        let directory = offlineDirectory
        let limit = Self.maxOfflineEntries
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
            Self.pruneOfflineDirectory(directory, limit: limit)
        }
    }

    private func offlineFileURL(for path: String) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return offlineDirectory.appendingPathComponent(name + ".json")
    }

    private nonisolated static func pruneOfflineDirectory(_ directory: URL, limit: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: .skipsHiddenFiles),
              files.count > limit else { return }
        let sorted = files.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs < rhs
        }
        for file in sorted.prefix(files.count - limit) {
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - List decoding

    /// Decodes a JSON list. The backend returns plain arrays, except search which wraps the list in
    /// `{"channels": [], "posters": [...]}`. Wrapper keys are tolerated defensively; HTML bodies and
    /// non-JSON payloads surface as Persian `APIError`s.
    private static func decodeList<T: Decodable>(_ data: Data, endpoint: String) throws -> [T] {
        let payload = strippingBOM(data)
        guard !payload.isEmpty else { throw APIError.empty(endpoint) }
        guard let first = firstSignificantByte(in: payload) else { throw APIError.empty(endpoint) }
        guard first != UInt8(ascii: "<") else { throw APIError.http(502) }

        let decoder = JSONDecoder()

        if first == UInt8(ascii: "[") {
            do {
                return try decoder.decode([T].self, from: payload)
            } catch {
                throw decodingFailure(error, endpoint: endpoint)
            }
        }

        if first == UInt8(ascii: "{") {
            if let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                for key in ["posters", "data", "items", "results"] {
                    guard let value = object[key],
                          JSONSerialization.isValidJSONObject(value),
                          let arrayData = try? JSONSerialization.data(withJSONObject: value) else {
                        continue
                    }
                    if let decoded = try? decoder.decode([T].self, from: arrayData) {
                        return decoded
                    }
                }
                throw APIError.decoding("ساختار پاسخ نامعتبر (\(endpoint))")
            }
            throw decodingFailure(APIError.decoding("آبجکت نامعتبر"), endpoint: endpoint)
        }

        // A bare `null` (or non-JSON text) means "nothing here".
        if let text = String(data: payload.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), text == "null" {
            throw APIError.empty(endpoint)
        }
        throw APIError.decoding("پاسخ JSON نبود (\(endpoint))")
    }

    private static func decodingFailure(_ error: Error, endpoint: String) -> APIError {
        let detail: String
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, _): detail = "کلید \(key.stringValue) یافت نشد"
            case .typeMismatch(_, let context): detail = "نوع داده نامعتبر در \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(_, let context): detail = "مقدار خالی در \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .dataCorrupted(let context): detail = "داده خراب: \(context.debugDescription)"
            @unknown default: detail = "خطای رمزگشایی"
            }
        } else {
            detail = String(describing: error)
        }
        return .decoding("\(endpoint): \(detail.prefix(160))")
    }

    // MARK: - Search normalisation

    /// Mirrors Android's `URLEncoder.encode(query, UTF_8).replace("+", "%20")`, with two fixes the
    /// Android app does not have: Arabic `ي`/`ك` are normalised to Persian `ی`/`ک` (the catalogue
    /// only contains Persian letters — a query with Arabic letters otherwise finds nothing) and
    /// `/` is replaced by a space because a raw slash inside the path breaks routing (404).
    static func normalizedSearchQuery(_ raw: String) -> String {
        var text = raw.precomposedStringWithCanonicalMapping
        text = text.replacingOccurrences(of: "\u{064A}", with: "\u{06CC}") // ي → ی
        text = text.replacingOccurrences(of: "\u{0643}", with: "\u{06A9}") // ك → ک
        text = text.replacingOccurrences(of: "\u{200E}", with: "")          // LRM
        text = text.replacingOccurrences(of: "\u{200F}", with: "")          // RLM
        text = text.replacingOccurrences(of: "/", with: " ")
        text = text.replacingOccurrences(of: "\\", with: " ")
        text = text.replacingOccurrences(of: "\u{0000}", with: "")

        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if collapsed.count > maxSearchQueryLength {
            return String(collapsed.prefix(maxSearchQueryLength))
        }
        return collapsed
    }

    /// UTF-8 percent-encoding for one URL path component: unreserved characters
    /// (`A–Z a–z 0–9 - . _ ~`) stay, everything else becomes an uppercase `%XX` escape,
    /// spaces included (`%20`, never `+`).
    static func urlEncodedPathComponent(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count * 3)
        for byte in value.utf8 {
            let isUnreserved = (byte >= 0x30 && byte <= 0x39)   // 0-9
                || (byte >= 0x41 && byte <= 0x5A)               // A-Z
                || (byte >= 0x61 && byte <= 0x7A)               // a-z
                || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E // - . _ ~
            if isUnreserved {
                result.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    // MARK: - Small helpers

    private static func dedupe<T>(_ items: [T], key: (T) -> String) -> [T] {
        var seen = Set<String>()
        var result: [T] = []
        result.reserveCapacity(items.count)
        for item in items {
            let itemKey = key(item)
            guard !seen.contains(itemKey) else { continue }
            seen.insert(itemKey)
            result.append(item)
        }
        return result
    }

    private static func strippingBOM(_ data: Data) -> Data {
        guard data.count >= 3,
              data[data.startIndex] == 0xEF,
              data[data.index(after: data.startIndex)] == 0xBB,
              data[data.index(after: data.index(after: data.startIndex))] == 0xBF else {
            return data
        }
        return data.dropFirst(3)
    }

    private static func firstSignificantByte(in data: Data) -> UInt8? {
        var index = data.startIndex
        // Skip a UTF-8 BOM if present.
        if data.count >= 3,
           data[index] == 0xEF,
           data[data.index(after: index)] == 0xBB,
           data[data.index(after: data.index(after: index))] == 0xBF {
            index = data.index(index, offsetBy: 3)
        }
        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x00 {
                index = data.index(after: index)
                continue
            }
            return byte
        }
        return nil
    }

    private static func persianDetail(for error: URLError) -> String {
        switch error.code {
        case .timedOut: return "پاسخ سرور دیر رسید"
        case .cannotFindHost, .dnsLookupFailed: return "سرور پیدا نشد"
        case .cannotConnectToHost: return "اتصال به سرور برقرار نشد"
        case .networkConnectionLost: return "اتصال شبکه قطع شد"
        case .notConnectedToInternet: return "اینترنت در دسترس نیست"
        case .secureConnectionFailed, .serverCertificateUntrusted: return "اتصال امن برقرار نشد"
        case .badURL, .unsupportedURL: return "آدرس نامعتبر"
        case .callIsActive, .dataNotAllowed, .internationalRoamingOff: return "شبکه در دسترس نیست"
        case .cancelled: return "درخواست لغو شد"
        default: return "خطای شبکه"
        }
    }
}

// MARK: - Attempt classification

/// A single host attempt either failed in a way another host/retry can fix (`transient`) or in a
/// way that is endpoint-level and will repeat everywhere (`permanent`, e.g. 404/400).
private enum AttemptFailure: Error {
    case transient(APIError)
    case permanent(APIError)
}
