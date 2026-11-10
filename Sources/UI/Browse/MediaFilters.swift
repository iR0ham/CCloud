import SwiftUI
import Foundation

// OWNER: ui-browse — shared multi-criteria filters (type, year range, IMDb) for Search and the
// paged browse feeds, plus the popover UI and the filter-aware empty/footer states.

struct MediaFilters: Equatable, Hashable {
    var kind: MediaKind?
    var yearFrom: Int?
    var yearTo: Int?
    var minIMDb: Double?

    var isActive: Bool {
        kind != nil || yearFrom != nil || yearTo != nil || minIMDb != nil
    }

    var activeCount: Int {
        var count = 0
        if kind != nil { count += 1 }
        if yearFrom != nil || yearTo != nil { count += 1 }
        if minIMDb != nil { count += 1 }
        return count
    }

    func matches(_ movie: Movie) -> Bool {
        matches(year: movie.year, imdb: movie.imdb, isSeries: movie.isSeries)
    }

    func matches(_ series: Series) -> Bool {
        matches(year: series.year, imdb: series.imdb, isSeries: true)
    }

    func matches(year: Int, imdb: Double, isSeries: Bool) -> Bool {
        if let kind {
            switch kind {
            case .movie: if isSeries { return false }
            case .series: if !isSeries { return false }
            }
        }
        if yearFrom != nil || yearTo != nil {
            guard year > 0 else { return false }
            if let yearFrom, year < yearFrom { return false }
            if let yearTo, year > yearTo { return false }
        }
        if let minIMDb {
            guard imdb > 0 else { return false }
            if imdb + 0.049 < minIMDb { return false }
        }
        return true
    }

    /// QA/demo hook (same mechanism as `QADemo`):
    /// `defaults write ir.ccloud.macapp QAFilters -string "movie|2020-2024|7"`
    /// Fields may be empty: `"|2020-|"` or `"all||8"`.
    static func qaSeed() -> MediaFilters {
        guard let raw = UserDefaults.standard.string(forKey: "QAFilters") else { return MediaFilters() }
        UserDefaults.standard.removeObject(forKey: "QAFilters")
        UserDefaults.standard.synchronize()

        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        var filters = MediaFilters()
        if let kind = parts.first {
            if kind == "movie" { filters.kind = .movie }
            if kind == "series" { filters.kind = .series }
        }
        if parts.count > 1, !parts[1].isEmpty {
            let bounds = parts[1].split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            if let first = bounds.first, !first.isEmpty { filters.yearFrom = Int(first) }
            if bounds.count > 1, let last = bounds.last, !last.isEmpty { filters.yearTo = Int(last) }
        }
        if parts.count > 2, let imdb = Double(parts[2]) { filters.minIMDb = imdb }
        return filters
    }
}

// MARK: - One removable criterion (used by the active-filter chips)

enum MediaFilterFacet: String, CaseIterable, Identifiable {
    case kind, year, imdb

    var id: String { rawValue }

    func label(in filters: MediaFilters) -> String? {
        switch self {
        case .kind:
            switch filters.kind {
            case .movie: return "فیلم"
            case .series: return "سریال"
            case nil: return nil
            }
        case .year:
            switch (filters.yearFrom, filters.yearTo) {
            case let (from?, to?): return from == to ? "سال \(from)" : "\(from) تا \(to)"
            case let (from?, nil): return "از \(from)"
            case let (nil, to?): return "تا \(to)"
            default: return nil
            }
        case .imdb:
            guard let min = filters.minIMDb else { return nil }
            return String(format: "IMDb %g+", min)
        }
    }

    func clear(in filters: inout MediaFilters) {
        switch self {
        case .kind: filters.kind = nil
        case .year: filters.yearFrom = nil; filters.yearTo = nil
        case .imdb: filters.minIMDb = nil
        }
    }
}

// MARK: - Regional visibility (Settings)
//
// The catalogue files these titles under both a country and a dedicated genre. `ContentHiding`
// (below) combines this with the anime rule and is applied app-wide — Home rails, feeds, search,
// favorites, history and category/country grids — except Live TV.

enum OriginFilter {
    private static let countryTitles: Set<String> = [
        "چین", "کره جنوبی", "ترکیه", "هند", "تایلند", "ژاپن", "پاکستان",
        "افغانستان", "مصر", "اردن", "امارات", "تونس", "سوریه", "عراق",
        "عربستان", "قطر", "کویت", "لبنان", "مراکش"
    ]
    private static let genreTitles: Set<String> = ["چینی", "کره ای", "ترکی", "هندی", "ژاپنی", "چینی ژاپنی"]

    static func hides(_ countries: [Country]) -> Bool {
        countries.contains { countryTitles.contains(normalized($0.title)) }
    }

    static func hides(_ country: Country) -> Bool {
        countryTitles.contains(normalized(country.title))
    }

    static func hidesGenre(_ title: String) -> Bool {
        genreTitles.contains(normalized(title))
    }

    /// Anime is Japanese animation. The combined «انیمیشن + انیمه» genre also covers Western
    /// cartoons, so the country check keeps those visible.
    static func hidesAnime(countries: [Country], genres: [Genre]) -> Bool {
        let isJapanese = countries.contains { normalized($0.title) == "ژاپن" }
        guard isJapanese else { return false }
        return genres.contains { normalized($0.title).contains("انیمه") }
    }

    /// Country and genre titles arrive with either a space or a ZWNJ between the words.
    static func normalized(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\u{200C}", with: " ")
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

// MARK: - Content hiding (Settings → «پنهان‌سازی محتوا»)

/// Applies the two Settings toggles to any list of catalogue titles. Live TV and detail screens
/// are deliberately outside this model.
struct ContentHiding: Equatable {
    var origins = false
    var anime = false

    var isActive: Bool { origins || anime }

    func hides(countries: [Country], genres: [Genre]) -> Bool {
        if origins, OriginFilter.hides(countries) { return true }
        if anime, OriginFilter.hidesAnime(countries: countries, genres: genres) { return true }
        return false
    }

    func isHidden(_ movie: Movie) -> Bool {
        hides(countries: movie.country, genres: movie.genres)
    }

    func isHidden(_ series: Series) -> Bool {
        hides(countries: series.country, genres: series.genres)
    }

    func isHidden(_ entry: FavoriteEntry) -> Bool {
        if let movie = entry.movie { return isHidden(movie) }
        if let series = entry.series { return isHidden(series) }
        return false
    }

    func isHidden(_ entry: HistoryEntry) -> Bool {
        if let movie = entry.movie { return isHidden(movie) }
        if let series = entry.series { return isHidden(series) }
        return false
    }
}

extension SettingsStore {
    var contentHiding: ContentHiding {
        ContentHiding(origins: hideRegionalOrigins, anime: hideAnime)
    }
}

// MARK: - Feed scanning
//
// The backend has no year/IMDb parameters, so filters run over loaded pages. When a filter is
// strict we walk forward through pages (bounded) until enough matches are found or the feed ends.

@MainActor
private func waitForFeedIdle<Item>(_ feed: PagedFeed<Item>) async {
    while feed.isLoading || feed.isLoadingMore {
        if Task.isCancelled { return }
        try? await Task.sleep(nanoseconds: 40_000_000)
    }
}

@MainActor
func scanFeed<Item: Identifiable & Hashable>(
    _ feed: PagedFeed<Item>,
    matching filters: MediaFilters,
    matcher: @escaping (Item) -> Bool,
    minimumMatches: Int = 12,
    maxPages: Int = 10
) async {
    guard filters.isActive else { return }
    await scanFeed(feed, matcher: matcher, minimumMatches: minimumMatches, maxPages: maxPages)
}

/// Scan variant for post-filters that are not part of `MediaFilters` (e.g. the regional setting).
@MainActor
func scanFeed<Item: Identifiable & Hashable>(
    _ feed: PagedFeed<Item>,
    matcher: @escaping (Item) -> Bool,
    minimumMatches: Int = 12,
    maxPages: Int = 10
) async {
    await waitForFeedIdle(feed)
    var scanned = 0
    while scanned < maxPages,
          !Task.isCancelled,
          feed.hasMore,
          feed.error == nil,
          !feed.isLoading, !feed.isLoadingMore,
          feed.items.filter(matcher).count < minimumMatches {
        let before = feed.items.count
        await feed.loadNextPage()
        guard !Task.isCancelled else { return }
        if feed.items.count == before { break }
        scanned += 1
    }
}

/// Footer action: pull a few more pages until at least one new match appears.
@MainActor
func scanFeedForMore<Item: Identifiable & Hashable>(
    _ feed: PagedFeed<Item>,
    matching filters: MediaFilters,
    matcher: @escaping (Item) -> Bool,
    maxPages: Int = 4
) async {
    guard filters.isActive else { return }
    await scanFeedForMore(feed, matcher: matcher, maxPages: maxPages)
}

/// Scan variant for post-filters that are not part of `MediaFilters`.
@MainActor
func scanFeedForMore<Item: Identifiable & Hashable>(
    _ feed: PagedFeed<Item>,
    matcher: @escaping (Item) -> Bool,
    maxPages: Int = 4
) async {
    await waitForFeedIdle(feed)
    let baseline = feed.items.count
    var scanned = 0
    while scanned < maxPages,
          !Task.isCancelled,
          feed.hasMore,
          feed.error == nil,
          !feed.isLoading, !feed.isLoadingMore,
          !feed.items.dropFirst(baseline).contains(where: matcher) {
        let before = feed.items.count
        await feed.loadNextPage()
        guard !Task.isCancelled else { return }
        if feed.items.count == before { break }
        scanned += 1
    }
}

// MARK: - Filter button + popover

@MainActor
final class MediaFilterPopoverModel: ObservableObject {
    @Published var isPresented = false
}

struct MediaFilterButton: View {
    let filters: MediaFilters
    var showsKind: Bool = false
    let onChange: (MediaFilters) -> Void

    @StateObject private var ui = MediaFilterPopoverModel()
    @StateObject private var hover = HoverState()

    var body: some View {
        Button {
            ui.isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                Text("فیلتر")
                    .font(.ccloud(12, weight: .medium))
                if filters.isActive {
                    Text(browseNumber(filters.activeCount))
                        .font(.ccloud(9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Circle().fill(Theme.accent))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .opacity(0.65)
            }
            .foregroundStyle(filters.isActive ? Theme.accentBright : Theme.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(filters.isActive
                               ? Theme.accent.opacity(0.14)
                               : (hover.isHovering ? Theme.cardHover : Theme.card))
            )
            .overlay(
                Capsule().strokeBorder(filters.isActive
                                       ? Theme.accent.opacity(0.45)
                                       : Theme.stroke,
                                       lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hover.isHovering = $0 }
        .help("فیلتر بر اساس نوع، سال ساخت و امتیاز IMDb")
        .popover(isPresented: Binding(get: { ui.isPresented }, set: { ui.isPresented = $0 }),
                 arrowEdge: .top) {
            MediaFilterPanel(filters: filters,
                             showsKind: showsKind,
                             onChange: onChange,
                             onClose: { ui.isPresented = false })
        }
    }
}

struct MediaFilterPanel: View {
    let filters: MediaFilters
    var showsKind: Bool = false
    let onChange: (MediaFilters) -> Void
    let onClose: () -> Void

    private let imdbChoices: [Double] = [6, 7, 8, 9]

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(stride(from: current + 1, through: 1950, by: -1))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            HStack(spacing: 10) {
                Text("فیلترها")
                    .font(.ccloud(14, weight: .bold))
                    .foregroundStyle(Theme.text)

                Spacer(minLength: 0)

                Button {
                    onChange(MediaFilters())
                } label: {
                    Text("پاک کردن همه")
                        .font(.ccloud(11, weight: .medium))
                        .foregroundStyle(filters.isActive ? Theme.accentBright : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!filters.isActive)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("بستن")
            }

            if showsKind {
                VStack(alignment: .trailing, spacing: 8) {
                    filterLabel("نوع")
                    HStack(spacing: 6) {
                        FilterChip(title: "همه", isSelected: filters.kind == nil) {
                            update { $0.kind = nil }
                        }
                        FilterChip(title: "فیلم", isSelected: filters.kind == .movie) {
                            update { $0.kind = .movie }
                        }
                        FilterChip(title: "سریال", isSelected: filters.kind == .series) {
                            update { $0.kind = .series }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            VStack(alignment: .trailing, spacing: 8) {
                filterLabel("سال ساخت")
                HStack(spacing: 8) {
                    FilterYearMenu(prefix: "از", selection: filters.yearFrom, years: years) { value in
                        update { current in
                            current.yearFrom = value
                            if let value, let to = current.yearTo, to < value {
                                current.yearTo = value
                            }
                        }
                    }

                    FilterYearMenu(prefix: "تا", selection: filters.yearTo, years: years) { value in
                        update { current in
                            current.yearTo = value
                            if let value, let from = current.yearFrom, from > value {
                                current.yearFrom = value
                            }
                        }
                    }
                }
                Text("برای فیلتر یک سال مشخص، «از» و «تا» را برابر انتخاب کنید.")
                    .font(.ccloud(10))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .trailing, spacing: 8) {
                filterLabel("حداقل امتیاز IMDb")
                HStack(spacing: 5) {
                    FilterChip(title: "همه", isSelected: filters.minIMDb == nil) {
                        update { $0.minIMDb = nil }
                    }
                    ForEach(imdbChoices, id: \.self) { value in
                        FilterChip(title: String(format: "%g+", value),
                                   isSelected: filters.minIMDb == value) {
                            update { current in
                                current.minIMDb = current.minIMDb == value ? nil : value
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(width: 336)
        .background(Theme.bgElevated)
    }

    private func filterLabel(_ text: String) -> some View {
        Text(text)
            .font(.ccloud(11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func update(_ mutate: (inout MediaFilters) -> Void) {
        var copy = filters
        mutate(&copy)
        guard copy != filters else { return }
        onChange(copy)
    }
}

struct FilterYearMenu: View {
    let prefix: String
    let selection: Int?
    let years: [Int]
    let onSelect: (Int?) -> Void

    @StateObject private var hover = HoverState()

    private var label: String {
        guard let selection else { return "\(prefix) سال" }
        return "\(prefix) \(String(selection))"
    }

    var body: some View {
        Menu {
            Button("هر سال") { onSelect(nil) }
            Divider()
            ForEach(years, id: \.self) { year in
                Button {
                    onSelect(year)
                } label: {
                    if year == selection {
                        Label(String(year), systemImage: "checkmark")
                    } else {
                        Text(String(year))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.ccloud(11.5, weight: .medium))
                    .foregroundStyle(selection == nil ? Theme.textSecondary : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hover.isHovering ? Theme.cardHover : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hover.isHovering = $0 }
    }
}

// MARK: - Active-filter chips

struct ActiveMediaFilterChips: View {
    let filters: MediaFilters
    let onChange: (MediaFilters) -> Void

    var body: some View {
        if filters.isActive {
            HStack(spacing: 8) {
                ForEach(MediaFilterFacet.allCases) { facet in
                    if let label = facet.label(in: filters) {
                        ActiveFilterChip(text: label) {
                            var copy = filters
                            facet.clear(in: &copy)
                            onChange(copy)
                        }
                    }
                }

                Button {
                    onChange(MediaFilters())
                } label: {
                    Text("پاک کردن همه")
                        .font(.ccloud(10.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .frame(height: 26)
        }
    }
}

struct ActiveFilterChip: View {
    let text: String
    let onRemove: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Text(text)
                    .font(.ccloud(10.5, weight: .medium))
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
            }
            .foregroundStyle(Theme.accentBright)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.accent.opacity(hover.isHovering ? 0.22 : 0.14)))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.32), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .help("حذف این فیلتر")
    }
}

// MARK: - Filter-aware states

struct MediaFilterScanningView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("در حال بررسی عناوین با فیلترهای انتخابی…")
                .font(.ccloud(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct MediaFilteredEmptyView: View {
    let hasMore: Bool
    let onScanMore: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("نتیجه‌ای با این فیلترها پیدا نشد")
                .font(.ccloud(15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(hasMore
                 ? "صفحات بارگذاری‌شده خالی بودند؛ می‌توانید عناوین بیشتری را بررسی کنید یا فیلترها را ساده‌تر کنید."
                 : "فیلترها را تغییر دهید یا پاک کنید.")
                .font(.ccloud(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            HStack(spacing: 10) {
                if hasMore {
                    Button(action: onScanMore) {
                        Text("بررسی عناوین بیشتر")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                }
                Button(action: onClear) {
                    Text("پاک کردن فیلترها")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
