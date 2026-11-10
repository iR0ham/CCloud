import Foundation

// MARK: - Live API verification harness for the CCloud backend
//
// Compiles together with the real `Models.swift` + `APIClient.swift` (see run.sh), so the harness
// exercises exactly the code the app ships. It hits every endpoint against the live backend,
// checks shapes/counts/samples, proves the resilience layers (host fallback, TTL cache, in-flight
// de-duplication), fetches real poster bytes, prints a summary table and exits non-zero on failure.
//
// Media (video) CDNs are deliberately NOT contacted: they are unreachable from this machine.

@main
struct VerifyAPI {
    static func main() async {
        let code = await Verification.runAll()
        exit(code)
    }
}

@MainActor
final class Verification {

    // MARK: Setup

    private let client = APIClient.shared
    private let httpSession: URLSession
    private let startedAt = Date()

    private var rows: [Row] = []
    private var failures: [String] = []

    private var firstGenre: Genre?
    private var firstMovie: Movie?
    private var firstCountry: Country?
    private var verifiedCountryId: Int?
    private var sampleSeries: Series?

    private struct Row {
        let endpoint: String
        let host: String
        let status: String
        let count: String
        let sample: String
    }

    private struct CheckFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        httpSession = URLSession(configuration: config)
    }

    @MainActor
    static func runAll() async -> Int32 {
        let verification = Verification()
        return await verification.run()
    }

    // MARK: Run

    private func run() async -> Int32 {
        printHeader()

        await checkGenres()
        await checkMovies()
        await checkSeries()
        await checkSeasons()
        await checkSearch()
        await checkSearchEncoding()
        await checkCountries()
        await checkCountryPosters()
        await checkPosterURLs()
        await checkPosterImages()
        await checkCacheAndDedupe()
        await checkHostFallback()
        await checkHealth()

        printSummary()
        return failures.isEmpty ? 0 : 1
    }

    // MARK: Individual checks

    private func checkGenres() async {
        await perform("genres") {
            let genres = try await client.genres()
            try require(genres.count >= 10, "expected the full genre list, got \(genres.count)")
            try require(genres.allSatisfy { !$0.title.isEmpty }, "a genre decoded with an empty title")
            firstGenre = genres.first
            return (genres.count, genres.first?.title ?? "")
        }
    }

    private func checkMovies() async {
        for page in 0...2 {
            await perform("movies page \(page)") {
                let movies = try await client.movies(page: page)
                try require(movies.count >= 20, "page \(page) returned \(movies.count) items")
                try require(movies.allSatisfy { !$0.title.isEmpty }, "a movie decoded with an empty title")
                try require(movies.allSatisfy { $0.id > 0 }, "a movie decoded with id 0")
                if page == 0 { firstMovie = movies.first }
                return (movies.count, movies.first?.title ?? "")
            }
        }

        await perform("movies genre filter / imdb") {
            guard let genre = firstGenre else { throw CheckFailure(message: "genre list unavailable") }
            let movies = try await client.movies(page: 0, genreId: genre.id, sort: .imdb)
            try require(!movies.isEmpty, "genre \(genre.id) returned no movies")
            return (movies.count, "\(genre.title) — \(movies.first?.title ?? "")")
        }

        await perform("movies sort year page 0") {
            let movies = try await client.movies(page: 0, sort: .year)
            try require(!movies.isEmpty, "year sort returned no movies")
            return (movies.count, movies.first?.title ?? "")
        }

        await perform("movies page 9999 (past end)") {
            let movies = try await client.movies(page: 9999)
            try require(movies.isEmpty, "expected an empty page past the end, got \(movies.count)")
            return (movies.count, "empty page as expected")
        }
    }

    private func checkSeries() async {
        for page in 0...2 {
            await perform("series page \(page)") {
                let series = try await client.series(page: page)
                try require(series.count >= 20, "page \(page) returned \(series.count) items")
                try require(series.allSatisfy { !$0.title.isEmpty }, "a series decoded with an empty title")
                try require(series.allSatisfy { $0.id > 0 }, "a series decoded with id 0")
                if page == 0 { sampleSeries = series.first }
                return (series.count, series.first?.title ?? "")
            }
        }

        await perform("series genre filter / imdb") {
            guard let genre = firstGenre else { throw CheckFailure(message: "genre list unavailable") }
            let series = try await client.series(page: 0, genreId: genre.id, sort: .imdb)
            try require(!series.isEmpty, "genre \(genre.id) returned no series")
            return (series.count, "\(genre.title) — \(series.first?.title ?? "")")
        }
    }

    private func checkSeasons() async {
        await perform("seasons (id from series list)") {
            guard let series = sampleSeries else { throw CheckFailure(message: "series list unavailable") }
            let seasons = try await client.seasons(seriesId: series.id)
            try require(!seasons.isEmpty, "no seasons for series \(series.id)")
            let episodes = seasons.reduce(0) { $0 + $1.episodes.count }
            try require(episodes > 0, "seasons decoded without any episodes")
            try require(seasons.allSatisfy { !$0.title.isEmpty }, "a season decoded with an empty title")
            return (episodes, "\(seasons.count) فصل / \(episodes) قسمت — \(seasons[0].title)")
        }
    }

    private func checkSearch() async {
        await perform("search en \"housemaid\"") {
            let items = try await client.search(query: "housemaid")
            try require(!items.isEmpty, "English search returned nothing")
            try require(items.contains { $0.title.localizedCaseInsensitiveContains("housemaid") },
                        "results do not match \"housemaid\": \(items.prefix(3).map(\.title))")
            try require(items.allSatisfy { !$0.title.isEmpty }, "a search result decoded with an empty title")
            return (items.count, items.first?.title ?? "")
        }

        await perform("search fa \"فرید\"") {
            let items = try await client.search(query: "فرید")
            try require(items.count >= 10, "Persian search returned only \(items.count) results")
            return (items.count, items.first?.title ?? "")
        }

        await perform("search ar \"فريد\" (normalised+trimmed)") {
            // Arabic letters + padding spaces: without normalisation the backend answers 0–1 items.
            let items = try await client.search(query: "  فريد  ")
            try require(items.count >= 10, "Arabic letters were not normalised (only \(items.count) results)")
            return (items.count, items.first?.title ?? "")
        }

        await perform("search \"the godfather\" (space→%20)") {
            let items = try await client.search(query: "the godfather")
            try require(!items.isEmpty, "space-separated search returned nothing")
            try require(items.contains { $0.title.localizedCaseInsensitiveContains("godfather") },
                        "results do not match \"godfather\"")
            return (items.count, items.first?.title ?? "")
        }

        await perform("search edge cases (empty, slash)") {
            let empty = try await client.search(query: "   ")
            try require(empty.isEmpty, "blank query should return []")
            let slash = try await client.search(query: "a/b")
            // A raw slash in the path makes the backend answer 404; the client replaces it.
            return (slash.count, "blank→[], \"a/b\" did not 404")
        }
    }

    private func checkSearchEncoding() async {
        await perform("search encoding (unit)") {
            let encoded = APIClient.urlEncodedPathComponent("فرید")
            try require(encoded == "%D9%81%D8%B1%DB%8C%D8%AF", "unexpected Persian encoding: \(encoded)")
            let spaced = APIClient.urlEncodedPathComponent("the godfather")
            try require(spaced == "the%20godfather", "unexpected space encoding: \(spaced)")
            try require(APIClient.urlEncodedPathComponent("a/b") == "a%2Fb", "/ must be escaped")
            try require(APIClient.normalizedSearchQuery("  فريد  ") == "فرید", "Arabic→Persian normalisation failed")
            try require(APIClient.normalizedSearchQuery("a/b") == "a b", "slash sanitisation failed")
            return (nil, "ي→ی، ك→ک، space→%20، /→space")
        }
    }

    private func checkCountries() async {
        await perform("countries") {
            let countries = try await client.countries()
            try require(countries.count >= 10, "expected many countries, got \(countries.count)")
            try require(countries.allSatisfy { !$0.title.isEmpty }, "a country decoded with an empty title")
            firstCountry = countries.first(where: { $0.id == 1 }) ?? countries.first
            try require(firstCountry?.image.isEmpty == false, "country entry has no image field")
            return (countries.count, firstCountry?.title ?? "")
        }
    }

    private func checkCountryPosters() async {
        await perform("country posters page 0") {
            guard let country = firstCountry else { throw CheckFailure(message: "country list unavailable") }
            var posters = try await client.countryPosters(countryId: country.id, page: 0)
            var usedId = country.id

            if posters.isEmpty {
                // A country can legitimately have no posters; find one that has.
                let all = try await client.countries()
                for candidate in all.prefix(8) where candidate.id != country.id {
                    let page = try await client.countryPosters(countryId: candidate.id, page: 0)
                    if !page.isEmpty {
                        posters = page
                        usedId = candidate.id
                        break
                    }
                }
            }

            try require(!posters.isEmpty, "no country returned any posters")
            try require(posters.allSatisfy { !$0.title.isEmpty }, "a country poster decoded with an empty title")
            verifiedCountryId = usedId
            return (posters.count, posters.first?.title ?? "")
        }

        await perform("country posters page 1") {
            guard let countryId = verifiedCountryId else { throw CheckFailure(message: "country posters unavailable") }
            let posters = try await client.countryPosters(countryId: countryId, page: 1)
            try require(!posters.isEmpty, "country \(countryId) page 1 is empty")
            return (posters.count, posters.first?.title ?? "")
        }
    }

    private func checkPosterURLs() async {
        await perform("posterImageURL (unit)") {
            try require(client.posterImageURL("") == nil, "empty string must be nil")
            try require(client.posterImageURL("null") == nil, "\"null\" must be nil")
            try require(client.posterImageURL("data:image/png;base64,AAAA") == nil, "data: URL must be nil")
            try require(client.posterImageURL("https://tracker.example/x.png") != nil, "external https URL dropped")

            guard let relative = client.posterImageURL("/uploads/cache/poster_thumb/x.jpg") else {
                throw CheckFailure(message: "relative path was not resolved")
            }
            try require(relative.host == client.activeHost, "relative path host \(relative.host ?? "nil")")
            try require(relative.path == "/uploads/cache/poster_thumb/x.jpg", "relative path lost its path")

            guard let primary = client.posterImageURL("https://server-hi-speed-iran.info/uploads/x.jpg") else {
                throw CheckFailure(message: "known-host URL rejected")
            }
            try require(primary.scheme == "https", "rewritten URL lost https")
            try require(primary.host == client.activeHost, "known host was not rewritten to the active host")

            guard let padded = client.posterImageURL("  https://server-hi-speed-iran.info/uploads/y.jpg?w=1  ") else {
                throw CheckFailure(message: "padded absolute URL rejected")
            }
            try require(padded.query == "w=1", "query string was lost during rewrite")
            return (nil, "relative + known-host URLs resolved to \(client.activeHost)")
        }
    }

    private func checkPosterImages() async {
        await perform("poster image GET") {
            guard let movie = firstMovie else { throw CheckFailure(message: "movie list unavailable") }
            return try await fetchImage(movie.image, label: "movie poster")
        }

        await perform("country image GET") {
            guard let country = firstCountry else { throw CheckFailure(message: "country list unavailable") }
            return try await fetchImage(country.image, label: "country image")
        }
    }

    private func fetchImage(_ raw: String, label: String) async throws -> (Int?, String) {
        guard let url = client.posterImageURL(raw) else {
            throw CheckFailure(message: "posterImageURL returned nil for the \(label)")
        }
        let (data, response) = try await httpSession.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw CheckFailure(message: "no HTTP response for the \(label)")
        }
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? "?"
        try require(http.statusCode == 200, "\(label): HTTP \(http.statusCode)")
        try require(type.lowercased().hasPrefix("image/"), "\(label): content-type \(type)")
        try require(data.count > 512, "\(label): suspiciously small body (\(data.count) bytes)")
        return (data.count, "\(type) — \(url.host ?? "?")")
    }

    private func checkCacheAndDedupe() async {
        await perform("TTL cache (second call cached)") {
            client.invalidateCache()
            client.resetMetrics()
            let first = try await client.movies(page: 7)
            let roundTrips = client.networkRequestCount
            let second = try await client.movies(page: 7)
            try require(client.networkRequestCount == roundTrips,
                        "cached call hit the network (\(roundTrips) → \(client.networkRequestCount))")
            try require(first.count == second.count, "cache returned a different page")
            return (second.count, "1 round-trip, repeat served from memory")
        }

        await perform("in-flight de-duplication (6 concurrent)") {
            client.invalidateCache()
            client.resetMetrics()
            let api = client
            let counts: [Int?] = await withTaskGroup(of: Int?.self) { group in
                for _ in 0..<6 {
                    group.addTask {
                        (try? await api.movies(page: 8))?.count
                    }
                }
                var collected: [Int?] = []
                for await count in group { collected.append(count) }
                return collected
            }
            try require(counts.allSatisfy { $0 != nil }, "a concurrent call failed")
            let unique = Set(counts.compactMap { $0 })
            try require(unique.count == 1, "concurrent calls returned different pages: \(unique)")
            try require(client.networkRequestCount == 1,
                        "expected 1 shared network request, got \(client.networkRequestCount)")
            return (counts.first ?? nil, "6 callers → 1 network request")
        }
    }

    private func checkHostFallback() async {
        await perform("host fallback: force hostinnegar.com") {
            client.invalidateCache()
            client.preferHost("hostinnegar.com")
            let genres = try await client.genres()
            try require(!genres.isEmpty, "helper host returned no genres")
            try require(client.activeHost == "hostinnegar.com",
                        "request was not served by the helper host (active: \(client.activeHost))")
            guard let movie = firstMovie, let rewritten = client.posterImageURL(movie.image) else {
                throw CheckFailure(message: "poster rewrite check unavailable")
            }
            try require(rewritten.host == "hostinnegar.com",
                        "poster URL host \(rewritten.host ?? "nil") was not rewritten to the active host")
            return (genres.count, "served by hostinnegar.com، poster host rewritten")
        }

        await perform("host fallback: forced dead host") {
            client.invalidateCache()
            client.preferHost("windowsdiba.info") // NXDOMAIN as of 2026-10-24
            let movies = try await client.movies(page: 1)
            try require(!movies.isEmpty, "fallback after the dead host returned nothing")
            return (movies.count, "recovered via \(client.activeHost)")
        }

        await perform("host restore primary") {
            client.invalidateCache()
            client.preferHost("server-hi-speed-iran.info")
            let genres = try await client.genres()
            try require(!genres.isEmpty, "primary returned no genres")
            try require(client.activeHost == "server-hi-speed-iran.info",
                        "active host is \(client.activeHost) after restoring the primary")
            return (genres.count, "primary restored")
        }
    }

    private func checkHealth() async {
        await perform("healthCheck()") {
            client.invalidateCache()
            client.resetMetrics()
            let ok = await client.healthCheck()
            try require(ok, "healthCheck() returned false")
            try require(client.networkRequestCount > 0, "healthCheck() did not perform a network request")
            return (nil, "reachable via \(client.activeHost)")
        }
    }

    // MARK: Checking / recording

    private func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw CheckFailure(message: message()) }
    }

    private func perform(_ endpoint: String, _ body: () async throws -> (Int?, String)) async {
        FileHandle.standardError.write("[harness] \(endpoint)…\n".data(using: .utf8)!)
        do {
            let (count, sample) = try await body()
            rows.append(Row(endpoint: endpoint,
                            host: client.activeHost,
                            status: "OK",
                            count: count.map(String.init) ?? "-",
                            sample: sample))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            failures.append("\(endpoint): \(message)")
            rows.append(Row(endpoint: endpoint,
                            host: client.activeHost,
                            status: "FAIL",
                            count: "-",
                            sample: message))
        }
    }

    // MARK: Output

    private func printHeader() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        print("")
        print("==============================================================================")
        print(" CCloud macOS — live backend verification")
        print(" started:  \(formatter.string(from: startedAt))")
        print(" hosts:    \(client.hosts.joined(separator: "  →  "))")
        print("==============================================================================")
    }

    private func printSummary() {
        let widths: [Int] = [36, 26, 6, 6, 52]
        let header = ["ENDPOINT", "HOST", "STATUS", "COUNT", "SAMPLE"]
        print("")
        print(zip(header, widths).map { padded($0.0, $0.1) }.joined(separator: "  "))
        print(String(repeating: "-", count: widths.reduce(0, +) + 2 * (widths.count - 1)))
        for row in rows {
            print([
                padded(row.endpoint, widths[0]),
                padded(row.host, widths[1]),
                padded(row.status, widths[2]),
                padded(row.count, widths[3]),
                padded(row.sample, widths[4])
            ].joined(separator: "  "))
        }
        print(String(repeating: "-", count: widths.reduce(0, +) + 2 * (widths.count - 1)))

        let elapsed = Date().timeIntervalSince(startedAt)
        let passed = rows.count - failures.count
        if failures.isEmpty {
            print("RESULT: all \(rows.count) checks passed (network round-trips: \(client.totalNetworkRequestCount), \(String(format: "%.1f", elapsed))s)")
        } else {
            print("RESULT: \(passed)/\(rows.count) checks passed — \(failures.count) FAILED")
            print("")
            print("FAILED CHECKS:")
            for failure in failures {
                print("  [FAIL] \(failure)")
            }
        }
        print("")
    }

    private func padded(_ text: String, _ width: Int) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        if clean.count <= width {
            return clean + String(repeating: " ", count: width - clean.count)
        }
        return String(clean.prefix(max(0, width - 1))) + "…"
    }
}
