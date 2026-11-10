# CCloud for macOS — native macOS port of the CCloud Android app

We are building a **native macOS app** (SwiftUI + AppKit, no third-party dependencies, compiled with
`swiftc` from the Command Line Tools) that reproduces the CCloud Android streaming app
(<https://github.com/code3-dev/CCloud>, package `com.pira.ccloud`, version 2.0.0) on macOS.

Deliverable: a launchable **`build/CCloud.app`**, ad‑hoc signed, that browses the same live catalog
(movies, series, search, country filters, favorites) and plays the same sources.

---

## 1. Reference material (read-only, do not modify)

| What | Where |
|---|---|
| Original Android source (Kotlin/Compose) | `/tmp/CCloud` |
| Extracted APK (dex, res, assets) | `/tmp/apk_extract` |
| User's APK | `/Users/roham/Downloads/CCloud-universal.apk` |
| Server assets (logo, icon, fonts, screenshots) | `/tmp/CCloud/app/src/main/res/…` |

## 2. Live backend facts (verified 2026‑10‑23)

API base hosts, tried in order (helper hosts substitute the host in the URL):
`server-hi-speed-iran.info` → `hostinnegar.com` → `windowsdiba.info`.
API key path component: `4F5A9C3D9A86FA54EACEDDD635185`.

| Endpoint | URL suffix (after host) |
|---|---|
| Genres | `/api/genre/all/{KEY}/` |
| Movies page | `/api/movie/by/filtres/{genreId}/{sort}/{page}/{KEY}/` |
| Series page | `/api/serie/by/filtres/{genreId}/{sort}/{page}/{KEY}/` |
| Seasons of a series | `/api/season/by/serie/{seriesId}/{KEY}/` |
| Search | `/api/search/{urlEncodedQuery}/{KEY}/` |
| Countries | `/api/country/all/{KEY}/` |
| Posters by country | `/api/poster/by/filtres/0/{countryId}/{sort}/{page}/{KEY}/` |

- `sort` ∈ `created` (newest), `year`, `imdb`. `page` is **0-based**; 30 items per page.
- The server 301-redirects paths without the trailing slash → always use the trailing slash
  (URLSession follows redirects automatically, but trailing slash avoids one round trip).
- JSON is plain arrays (search returns `{"channels":[], "posters":[…]}`). See `Sources/Core/Models.swift`
  for the exact shapes. Details (description, sources, genres…) always come **from the list/search
  object itself** — there is no by-id endpoint (the Android app caches the object and passes it around).
- Media files are direct URLs (`http://` !) to `mkv` / `mp4` / hls. **ATS must allow arbitrary loads.**
- From this machine the media CDNs (`peer.tci.cdn.146.dl150m.info`, `node146.dl150m.info`,
  `drive*.google.dl175m.info`, `s1.giftmond.ir`) are **not reachable** (TCP timeout), so live video
  cannot be tested here. Playback must be validated with locally generated test media
  (`ffmpeg -f lavfi -i testsrc …`). The API + posters + images *are* reachable.

## 3. Playback strategy (already verified)

- `mp4` / `m3u8` sources → play directly with `AVPlayer`.
- `mkv` sources (≈72 % of catalog) → AVPlayer cannot decode Matroska. We **remux with ffmpeg into
  fMP4 HLS** on the fly and play that with AVPlayer:
  ```
  ffmpeg -hide_banner -nostdin -i <SOURCE_URL> -map 0:v:0 -map 0:a:0? -c copy \
    -f hls -hls_time 4 -hls_playlist_type event -hls_segment_type fmp4 \
    -hls_fmp4_init_filename init.mp4 -hls_segment_filename 'seg%05d.m4s' \
    <OUT_DIR>/playlist.m3u8
  ```
  A tiny local HTTP server (Network.framework) serves `<OUT_DIR>` on `127.0.0.1`; AVPlayer plays
  `http://127.0.0.1:<port>/playlist.m3u8`. Verified: video plays, timeline advances, audio track
  included. Far seeks are implemented by restarting ffmpeg with `-ss <t>` (engine detail, owned by
  `player-engine`).
- ffmpeg lookup order: `Contents/Resources/ffmpeg-bin/ffmpeg` (bundled) → `/opt/homebrew/bin/ffmpeg`
  → `/usr/local/bin/ffmpeg` → `PATH`. If missing → show a clear error with “Open in VLC”/copy URL.

## 4. Layout & file ownership (only edit files you own)

```
CCloudMac/
  PROJECT.md            Lead
  build.sh              Lead                     ← compiles all Sources/**/*.swift into build/CCloud.app
  Info.plist            Lead
  Sources/
    App/Theme.swift         Lead   design tokens, font registration, Font helpers
    App/AppState.swift      Lead   navigation, tabs, genres cache, playback request
    App/Components.swift    Lead   shared atoms (PosterCard, CachedAsyncImage, chips, badges…)
    App/RootView.swift      Lead   sidebar + content router + splash + sheets
    App/CCloudApp.swift     Lead   @main entry, window/appearance setup
    Core/Models.swift       Lead   shared data contract (API models, PlaybackRequest, SortOption)
    Core/Stores.swift       Lead   FavoritesStore + SettingsStore (UserDefaults persistence)
    Core/APIClient.swift    api-data
    UI/Browse/*.swift       ui-browse   MoviesView, SeriesView, SearchView, FavoritesView, CountriesView
    UI/Detail/*.swift       ui-detail   MovieDetailView, SeriesDetailView, CountryDetailView, SettingsView,
                                        AboutView, SplashView, PlayerScreen
    Player/*.swift          player-engine  HLSServer, PlaybackController, PlayerSurface
  Resources/            packaging   Fonts/*.ttf, AppIcon.icns, logo.png (+ optional bundled ffmpeg)
  Tests/                api-data / player-engine   standalone verification scripts
  scripts/              packaging   icon/font/asset generation, QA screenshots, zipping
```

Stub versions of every owned file already exist so the project always compiles; **replace the stub,
keep the public API**, and never edit files outside your scope (report interface problems to Lead).

## 5. Interfaces (do not change without asking Lead)

`Sources/Core/Models.swift` (Lead-owned, complete):
```swift
struct Genre: Codable, Hashable, Identifiable, Sendable { let id: Int; let title: String }
struct Country: Codable, Hashable, Identifiable, Sendable { let id: Int; let title: String; let image: String }
struct MediaSource: Codable, Hashable, Identifiable, Sendable {
    let id: Int; let quality: String?; let type: String; let url: String
    var qualityLabel: String; var isDirectPlayable: Bool; var kindLabel: String
}
struct Movie: Codable, Hashable, Identifiable, Sendable {
    let id: Int; let type: String; let title: String; let description: String
    let year: Int; let imdb: Double; let rating: Double; let duration: String?
    let image: String; let cover: String; let genres: [Genre]
    let sources: [MediaSource]; let country: [Country]
}
struct Series: Codable, Hashable, Identifiable, Sendable { /* same minus sources */ }
struct Season: Codable, Hashable, Identifiable, Sendable { let id: Int; let title: String; let episodes: [Episode] }
struct Episode: Codable, Hashable, Identifiable, Sendable {
    let id: Int; let title: String; let description: String?; let duration: String?
    let image: String?; let sources: [MediaSource]
}
enum MediaKind: String, Codable, Hashable, Sendable { case movie, series }
enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case newest, year, imdb        // → created / year / imdb
    var apiPath: String; var title: String   // Persian title
}
struct PlaybackRequest: Identifiable, Hashable, Sendable {
    let id: UUID; let title: String; let subtitle: String?
    let posterURL: String?; let sources: [MediaSource]; let preferredSourceID: Int?
    init(title: String, subtitle: String? = nil, posterURL: String? = nil,
         sources: [MediaSource], preferredSourceID: Int? = nil)
}
```
Also provided in Models.swift: `APIError`, `Movie.posterURL/coverURL/imageURL`, `Series.posterURL/coverURL`,
`Poster`-free conversions (`Movie`/`Series` are the only detail payloads), and
`Array<MediaSource>.preferred(for:)` helper.

`Sources/Core/APIClient.swift` (api-data):
```swift
enum APIError: LocalizedError { case offline(String), http(Int), decoding(String), empty(String) }
@MainActor final class APIClient {
    static let shared: APIClient
    var onBackendChange: ((String) -> Void)?          // report active host (for sidebar status)
    func genres() async throws -> [Genre]
    func movies(page: Int, genreId: Int = 0, sort: SortOption = .newest) async throws -> [Movie]
    func series(page: Int, genreId: Int = 0, sort: SortOption = .newest) async throws -> [Series]
    func seasons(seriesId: Int) async throws -> [Season]
    func search(query: String) async throws -> [Movie]   // search posters mapped to Movie/Series payload
    func countries() async throws -> [Country]
    func countryPosters(countryId: Int, page: Int, sort: SortOption = .newest) async throws -> [Movie]
}
```
`search` returns `[Movie]`-shaped payloads (`type == "movie" | "serie"`) — UI converts serie items via
`Series(movie:)` helper (already in Models.swift).

`Sources/Player/*` (player-engine):
```swift
enum PlaybackStatus: Equatable { case idle, preparing(String), ready, failed(String) }
@MainActor final class PlaybackController: ObservableObject {
    init(request: PlaybackRequest)
    @Published private(set) var status: PlaybackStatus
    @Published private(set) var isPlaying: Bool
    @Published private(set) var currentTime: Double
    @Published private(set) var duration: Double
    @Published private(set) var isBuffering: Bool
    @Published private(set) var sources: [MediaSource]
    @Published private(set) var selectedSourceID: Int?
    @Published var volume: Double          // 0…1
    @Published var rate: Float              // 0.5…2.0
    func play(); func pause(); func togglePlay(); func seek(to seconds: Double)
    func selectSource(_ source: MediaSource); func stop()
    var isFullscreenCapable: Bool { get }
}
struct PlayerSurface: NSViewRepresentable { let controller: PlaybackController }
```

`Sources/App/AppState.swift` (Lead):
```swift
@MainActor final class AppState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable { case movies, series, search, favorites, countries, settings }
    enum Route: Hashable { case movie(Movie), series(Series), country(Country) }
    @Published var tab: Tab
    @Published var path: [Route]
    @Published var playback: PlaybackRequest?      // non-nil → PlayerScreen sheet
    @Published var showAbout: Bool
    @Published var showSplash: Bool
    @Published var genres: [Genre]
    @Published var genresError: String?
    @Published var backendHost: String             // updated by API client
    func openMovie(_ m: Movie); func openSeries(_ s: Series); func openCountry(_ c: Country)
    func back(); func play(_ request: PlaybackRequest); func loadGenres() async
    var searchQuery: String                        // shared with SearchView
}
```

UI views (must keep these exact names + simple init):
```swift
struct MoviesView: View        // no params, uses @EnvironmentObject AppState + APIClient
struct SeriesView: View
struct SearchView: View
struct FavoritesView: View
struct CountriesView: View
struct CountryDetailView: View { let country: Country }
struct MovieDetailView: View   { let movie: Movie }
struct SeriesDetailView: View  { let series: Series }
struct SettingsView: View
struct AboutView: View
struct SplashView: View
struct PlayerScreen: View      { let request: PlaybackRequest }
```

## 5.5 ⚠️ Toolchain constraint: `@State` does NOT compile (macro plugin missing from CLT)

Apple's Command Line Tools ship the SwiftUI SDK but **not** the `SwiftUIMacros` plugin, so any use of
the `@State` attribute macro fails with *“external macro implementation type 'SwiftUIMacros.StateMacro'
could not be found”*. The same applies to `@Preview`/`@Previewable`/`#Preview`.

What is available (plain property-wrapper structs, verified compiling):
`@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Environment`, `@Binding` usage as a type,
`@Published` (Combine), `Binding(get:set:)`, all SwiftUI views/modifiers, `Task`, async/await, AppKit.

**Therefore — never write `@State`.** For local view state create a tiny `ObservableObject`:

```swift
@MainActor final class FooModel: ObservableObject { @Published var query = "" }
struct FooView: View {
    @StateObject private var model = FooModel()          // ✅
    var body: some View {
        TextField("…", text: Binding(get: { model.query }, set: { model.query = $0 }))
    }
}
```
`HoverState` (in `Sources/App/Components.swift`) is the ready-made helper for hover effects.
Project-wide state lives in `AppState`, `FavoritesStore`, `SettingsStore` (all `@EnvironmentObject`).

Also: no `@Observable`/Observation-based models, no SPM packages, no Xcode-only APIs.

## 6. UX spec (Persian, RTL, dark‑first)

**Content-area conventions** (RootView already does this — don't add your own outer padding):
the content area is inset by 32 pt horizontal / 34 pt top / 24 pt bottom, RTL, and views should fill
`maxWidth/maxHeight: .infinity` with a `ScrollView` where needed. The sidebar is 236 pt wide on the
physical right. The window is 1320×860 (min 1120×720). Every clickable poster calls
`app.openMovie/_.openSeries/_openCountry` and every playback calls `app.play(PlaybackRequest(...))`
which presents the player sheet.


- Whole UI is **Persian / RTL** (`EnvironmentValues.layoutDirection = .rightToLeft` is applied at the
  root). Text uses **Vazirmatn** via `Font.ccloud(size:weight:)`.
- Native macOS chrome: hidden title bar, 1280×830 default window, traffic lights over the sidebar.
- Sidebar (right side because RTL): logo + “CCloud”, nav items
  فیلمها / سریالها / جستجو / علاقهمندیها / کشورها, spacer, settings + about, backend status footer.
- Content: header (title + subtitle + controls), horizontally scrolling genre chips, sort menu,
  `LazyVGrid` of poster cards (adaptive ~5 columns at 1280 width, 2:3 posters, rounded 14, hover lift,
  rating badge, type badge for search results), infinite scroll, skeleton/loading + retry error state.
- Detail screens: full-bleed cover backdrop with dark gradient, poster thumb, title, meta row
  (year · IMDb · duration · country), genre chips, expandable description, and a **پخش** primary
  action + quality/source list. Series: season switcher + episode list (thumbnail, episode title,
  quality chips) and پخش per episode.
- Player sheet (`PlayerScreen`): AVPlayer surface + custom controls (play/pause, ±10s, timeline with
  buffered range, time labels, volume, speed menu, quality/source menu, fullscreen toggle, close),
  a “در حال آمادهسازی…” state with spinner while ffmpeg remuxes, error state with “باز کردن در VLC”.
- Motion should be subtle (0.15–0.25 s easeInOut). No third-party packages, no web views.

## 7. Build / run / verify

```
./build.sh                # → build/CCloud.app (ad-hoc signed)
./build.sh --run          # build + `open build/CCloud.app`
```
- **Parallel-safe builds:** each teammate must build into a private output dir so concurrent builds
  don't race: `CCLOUD_OUT="$PWD/build-<yourname>" ./build.sh` → app at `build-<yourname>/CCloud.app`.
  Only the Lead builds the shared `build/CCloud.app` for integration/QA.
- swiftc recipe (already in build.sh): `-O -swift-version 5 -parse-as-library`, module cache inside
  `build/`, target `arm64-apple-macos15.0`. TMPDIR must point inside `build/`.
- Never write outside this project directory (the harness sandbox only allows the workspace).
- Database/network **must not** be required for the app to launch: show Persian error states instead.
- The app must survive `build/CCloud.app` being launched from Finder and from `open`.
- QA: `scripts/snapshot.swift` (packaging) renders the app window to PNG via an in-app debug hook —
  terminal `screencapture` is blocked in this environment.

## 8. Team rules

1. Own your files; don't touch others'. Interfaces are fixed above.
2. Build often (`./build.sh`); errors outside your files → tell Lead, don't fix them yourself.
3. Everything user-facing is Persian; code/comments in English. RTL layout must be correct.
4. Hand-written Swift only, `@MainActor` for UI state, `async/await` for networking, no force-unwraps in
   user paths. Escape `$` in bash heredocs carefully (Swift string interpolation in bash = use quoted heredoc).
   **Never use `@State`** (see §5.5).
5. When done: report to Lead (files, what works, how verified) and mark your shared task complete.
