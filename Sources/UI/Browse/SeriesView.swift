import SwiftUI
import Combine

// OWNER: ui-browse — Series catalog: header, genre chips, sort menu, infinite poster grid.

@MainActor
final class SeriesModel: ObservableObject {
    @Published private(set) var feed: PagedFeed<Series>
    @Published private(set) var genreId: Int = 0
    @Published private(set) var sort: SortOption = .newest
    @Published private(set) var filters = MediaFilters()
    @Published private(set) var hidesRegionalOrigins = false
    @Published private(set) var hidesAnime = false
    @Published private(set) var isFilterScanning = false
    @Published private(set) var didFinishInitialLoad = false

    private var started = false
    private var generation = 0
    private var filterScanGeneration = 0
    private var filterScanTask: Task<Void, Never>?
    private var feedObservation: AnyCancellable?

    var isPostFiltering: Bool { filters.isActive || hidesRegionalOrigins || hidesAnime }

    var visibleItems: [Series] {
        guard isPostFiltering else { return feed.items }
        return feed.items.filter {
            Self.isVisible($0, filters: filters, regional: hidesRegionalOrigins, anime: hidesAnime)
        }
    }

    private static func isVisible(_ item: Series,
                                  filters: MediaFilters,
                                  regional: Bool,
                                  anime: Bool) -> Bool {
        if filters.isActive, !filters.matches(item) { return false }
        if regional, OriginFilter.hides(item.country) { return false }
        if anime, OriginFilter.hidesAnime(countries: item.country, genres: item.genres) { return false }
        return true
    }

    init() {
        filters = MediaFilters.qaSeed()
        feed = PagedFeed<Series> { page in
            try await APIClient.shared.series(page: page)
        }
        feedObservation = feed.forwardChanges(to: self)
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        reload()
    }

    func selectGenre(_ id: Int) {
        guard id != genreId else { return }
        genreId = id
        reload()
    }

    func selectSort(_ option: SortOption) {
        guard option != sort else { return }
        sort = option
        reload()
    }

    func refresh() {
        reload()
    }

    func applyFilters(_ new: MediaFilters) {
        guard new != filters else { return }
        filters = new
        startFilterScan()
    }

    func setRegionalFilter(_ hidden: Bool) {
        guard hidden != hidesRegionalOrigins else { return }
        hidesRegionalOrigins = hidden
        if didFinishInitialLoad { startFilterScan() }
    }

    func setAnimeFilter(_ hidden: Bool) {
        guard hidden != hidesAnime else { return }
        hidesAnime = hidden
        if didFinishInitialLoad { startFilterScan() }
    }

    func scanMore() {
        guard isPostFiltering, !isFilterScanning else { return }
        filterScanGeneration += 1
        let generation = filterScanGeneration
        let snapshot = filters
        let hidesRegions = hidesRegionalOrigins
        let animeHidden = hidesAnime
        isFilterScanning = true
        filterScanTask = Task { [weak self] in
            guard let self else { return }
            await scanFeedForMore(self.feed, matcher: {
                Self.isVisible($0, filters: snapshot, regional: hidesRegions, anime: animeHidden)
            })
            guard self.filterScanGeneration == generation else { return }
            self.isFilterScanning = false
        }
    }

    private func startFilterScan() {
        filterScanTask?.cancel()
        filterScanGeneration += 1
        let generation = filterScanGeneration
        guard isPostFiltering else {
            isFilterScanning = false
            return
        }
        let snapshot = filters
        let hidesRegions = hidesRegionalOrigins
        let animeHidden = hidesAnime
        isFilterScanning = true
        filterScanTask = Task { [weak self] in
            guard let self else { return }
            await scanFeed(self.feed, matcher: {
                Self.isVisible($0, filters: snapshot, regional: hidesRegions, anime: animeHidden)
            })
            guard self.filterScanGeneration == generation else { return }
            self.isFilterScanning = false
        }
    }

    private func reload() {
        generation += 1
        let generation = generation
        let genreId = genreId
        let sort = sort
        didFinishInitialLoad = false

        let feed = PagedFeed<Series> { page in
            try await APIClient.shared.series(page: page, genreId: genreId, sort: sort)
        }
        self.feed = feed
        feedObservation = feed.forwardChanges(to: self)
        Task { [weak self] in
            await feed.start()
            guard let self, self.generation == generation else { return }
            self.didFinishInitialLoad = true
            self.startFilterScan()
        }
    }
}

struct SeriesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = SeriesModel()

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            BrowseHeader(title: "سریال‌ها",
                         subtitle: subtitle,
                         sort: model.sort,
                         onSort: { model.selectSort($0) })

            HStack(spacing: 10) {
                BrowseGenreChipRow(genres: visibleGenres,
                             selectedId: model.genreId,
                             isLoading: app.genresLoading,
                             errorText: app.genresError,
                             onSelect: { model.selectGenre($0) },
                             onRetry: { Task { await app.loadGenres() } })
                MediaFilterButton(filters: model.filters,
                                  onChange: { model.applyFilters($0) })
            }
            .padding(.top, 18)

            if model.filters.isActive {
                ActiveMediaFilterChips(filters: model.filters,
                                       onChange: { model.applyFilters($0) })
                    .padding(.top, 10)
            }

            content
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .task {
            await app.loadGenresIfNeeded()
            model.setRegionalFilter(settings.hideRegionalOrigins)
            model.setAnimeFilter(settings.hideAnime)
            model.startIfNeeded()
        }
        .onChange(of: app.refreshTick) { _, _ in
            Task { await app.loadGenres() }
            model.refresh()
        }
        .onChange(of: settings.hideRegionalOrigins) { _, hidden in
            model.setRegionalFilter(hidden)
            if hidden,
               let selected = app.genres.first(where: { $0.id == model.genreId }),
               OriginFilter.hidesGenre(selected.title) {
                model.selectGenre(0)
            }
        }
        .onChange(of: settings.hideAnime) { _, hidden in
            model.setAnimeFilter(hidden)
        }
    }

    /// The genre strip follows the same rule so hidden categories cannot be picked either.
    private var visibleGenres: [Genre] {
        guard settings.hideRegionalOrigins else { return app.genres }
        return app.genres.filter { !OriginFilter.hidesGenre($0.title) }
    }

    private var subtitle: String {
        let feed = model.feed
        let items = model.visibleItems
        if !items.isEmpty {
            let trailing: String
            if model.isPostFiltering {
                trailing = "فیلترشده"
            } else {
                trailing = model.genreId == 0 ? model.sort.title : "ژانر انتخاب‌شده"
            }
            return browseSubtitle(count: items.count, noun: "سریال", trailing: trailing)
        }
        if feed.error != nil { return "اتصال به سرور برقرار نشد" }
        if model.isFilterScanning { return "در حال بررسی عناوین با فیلتر…" }
        if model.isPostFiltering, !feed.items.isEmpty { return "نتیجه‌ای با این فیلترها نیست" }
        return "در حال دریافت سریال‌ها…"
    }

    @ViewBuilder
    private var content: some View {
        let feed = model.feed
        let items = model.visibleItems
        if let error = feed.error, feed.items.isEmpty {
            ErrorStateView(message: error) {
                Task { await feed.retry() }
            }
            .frame(maxHeight: .infinity)
        } else if items.isEmpty {
            if feed.items.isEmpty, !model.didFinishInitialLoad {
                ScrollView(showsIndicators: false) {
                    BrowseSkeletonGrid()
                        .padding(.bottom, 24)
                }
                .frame(maxHeight: .infinity)
            } else if model.filters.isActive, model.isFilterScanning {
                MediaFilterScanningView()
            } else if model.filters.isActive {
                MediaFilteredEmptyView(hasMore: feed.hasMore,
                                       onScanMore: { model.scanMore() },
                                       onClear: { model.applyFilters(MediaFilters()) })
            } else if (model.hidesRegionalOrigins || model.hidesAnime), !feed.items.isEmpty {
                EmptyStateView(icon: "eye.slash",
                               title: "همهٔ سریال‌ها پنهان شده‌اند",
                               message: "همهٔ سریال‌های این فهرست در دسته‌های پنهان‌شده قرار دارند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را در تنظیمات تغییر دهید.")
                    .frame(maxHeight: .infinity)
            } else {
                EmptyStateView(icon: "tv",
                               title: "سریالی برای نمایش نیست",
                               message: "ژانر یا مرتب‌سازی دیگری را امتحان کنید.")
                    .frame(maxHeight: .infinity)
            }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: BrowseMetrics.columns,
                          alignment: .trailing,
                          spacing: BrowseMetrics.rowSpacing) {
                    ForEach(items) { series in
                        BrowsePosterCard(title: series.title,
                                        posterURL: series.posterURL,
                                        year: series.year,
                                        imdb: series.imdb,
                                        badge: "سریال",
                                        playSubtitle: series.genreText,
                                        onOpen: { app.openSeries(series) })
                            .onAppear {
                                Task { await feed.loadMoreIfNeeded(current: series) }
                            }
                    }
                }
                BrowseFeedFooter(isLoadingMore: feed.isLoadingMore,
                           hasMore: feed.hasMore,
                           itemCount: items.count,
                           isFilterActive: model.isPostFiltering,
                           isFilterScanning: model.isFilterScanning,
                           onScanMore: { model.scanMore() })
            }
            .frame(maxHeight: .infinity)
        }
    }
}
