import SwiftUI
import Foundation
import Combine

// OWNER: ui-browse — One category: paged film/series feed filtered by genre, with sort.

@MainActor
final class CategoryDetailModel: ObservableObject {
    @Published private(set) var feed: PagedFeed<Movie>
    @Published private(set) var kind: MediaKind = .movie
    @Published private(set) var sort: SortOption = .newest
    @Published private(set) var filters = MediaFilters()
    @Published private(set) var hiding = ContentHiding()
    @Published private(set) var isFilterScanning = false
    @Published private(set) var didFinishInitialLoad = false

    private var genre: Genre?
    private var started = false
    private var generation = 0
    private var filterScanGeneration = 0
    private var filterScanTask: Task<Void, Never>?
    private var feedObservation: AnyCancellable?

    var isPostFiltering: Bool { filters.isActive || hiding.isActive }

    var visibleItems: [Movie] {
        guard isPostFiltering else { return feed.items }
        return feed.items.filter {
            !hiding.isHidden($0) && (!filters.isActive || filters.matches($0))
        }
    }

    init() {
        filters = MediaFilters.qaSeed()
        feed = PagedFeed<Movie> { _ in [] }
        feedObservation = feed.forwardChanges(to: self)
    }

    func start(genre: Genre) {
        guard !started else { return }
        started = true
        self.genre = genre
        reload()
    }

    func select(kind: MediaKind) {
        guard kind != self.kind else { return }
        self.kind = kind
        reload()
    }

    func selectSort(_ option: SortOption) {
        guard option != sort else { return }
        sort = option
        reload()
    }

    func applyFilters(_ new: MediaFilters) {
        guard new != filters else { return }
        filters = new
        startFilterScan()
    }

    func setHiding(_ new: ContentHiding) {
        guard new != hiding else { return }
        hiding = new
        if didFinishInitialLoad { startFilterScan() }
    }

    func scanMore() {
        guard isPostFiltering, !isFilterScanning else { return }
        filterScanGeneration += 1
        let generation = filterScanGeneration
        let snapshot = filters
        let hidingSnapshot = hiding
        isFilterScanning = true
        filterScanTask = Task { [weak self] in
            guard let self else { return }
            await scanFeedForMore(self.feed, matcher: {
                !hidingSnapshot.isHidden($0) && (!snapshot.isActive || snapshot.matches($0))
            })
            guard self.filterScanGeneration == generation else { return }
            self.isFilterScanning = false
        }
    }

    func retry() {
        reload()
    }

    func refresh() {
        reload()
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
        let hidingSnapshot = hiding
        isFilterScanning = true
        filterScanTask = Task { [weak self] in
            guard let self else { return }
            await scanFeed(self.feed, matcher: {
                !hidingSnapshot.isHidden($0) && (!snapshot.isActive || snapshot.matches($0))
            })
            guard self.filterScanGeneration == generation else { return }
            self.isFilterScanning = false
        }
    }

    private func reload() {
        guard let genre else { return }
        generation += 1
        let generation = generation
        let kind = kind
        let sort = sort
        didFinishInitialLoad = false

        let newFeed: PagedFeed<Movie>
        switch kind {
        case .movie:
            newFeed = PagedFeed<Movie> { page in
                try await APIClient.shared.movies(page: page, genreId: genre.id, sort: sort)
            }
        case .series:
            newFeed = PagedFeed<Movie> { page in
                let series = try await APIClient.shared.series(page: page, genreId: genre.id, sort: sort)
                return series.map { Movie(from: $0) }
            }
        }

        feed = newFeed
        feedObservation = newFeed.forwardChanges(to: self)
        Task { [weak self] in
            await newFeed.start()
            guard let self, self.generation == generation else { return }
            self.didFinishInitialLoad = true
            self.startFilterScan()
        }
    }
}

struct CategoryDetailView: View {
    let genre: Genre

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = CategoryDetailModel()

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            header
            if model.filters.isActive {
                ActiveMediaFilterChips(filters: model.filters,
                                       onChange: { model.applyFilters($0) })
                    .padding(.top, 12)
            }
            content
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .task {
            model.setHiding(settings.contentHiding)
            model.start(genre: genre)
        }
        .onChange(of: app.refreshTick) { _, _ in
            model.refresh()
        }
    }

    private var subtitle: String {
        let feed = model.feed
        let items = model.visibleItems
        let noun = model.kind == .movie ? "فیلم" : "سریال"
        if !items.isEmpty {
            return browseSubtitle(count: items.count,
                                  noun: noun,
                                  trailing: model.isPostFiltering ? "فیلترشده" : model.sort.title)
        }
        if feed.error != nil { return "اتصال به سرور برقرار نشد" }
        if model.isFilterScanning { return "در حال بررسی عناوین با فیلتر…" }
        if model.filters.isActive, !feed.items.isEmpty { return "نتیجه‌ای با این فیلترها نیست" }
        if model.hiding.isActive, !feed.items.isEmpty { return "همهٔ عناوین پنهان شده‌اند" }
        return "در حال دریافت \(noun)های \(genre.title)…"
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                app.back()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("بازگشت")
                }
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .keyboardShortcut(.escape, modifiers: [])
            .help("بازگشت")

            Image(systemName: CategoryStyle.icon(for: genre.title))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: CategoryStyle.gradient(for: genre.id),
                                             startPoint: .topTrailing,
                                             endPoint: .bottomLeading))
                )

            SectionHeader(title: genre.title, subtitle: subtitle)

            HStack(spacing: 7) {
                FilterChip(title: "فیلم‌ها", isSelected: model.kind == .movie) {
                    model.select(kind: .movie)
                }
                FilterChip(title: "سریال‌ها", isSelected: model.kind == .series) {
                    model.select(kind: .series)
                }
            }

            MediaFilterButton(filters: model.filters,
                              onChange: { model.applyFilters($0) })

            BrowseSortMenu(sort: model.sort, onSelect: { model.selectSort($0) })
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let feed = model.feed
        let items = model.visibleItems
        if let error = feed.error, feed.items.isEmpty {
            ErrorStateView(message: error) {
                model.retry()
            }
            .frame(maxHeight: .infinity)
        } else if items.isEmpty {
            if feed.items.isEmpty, !model.didFinishInitialLoad {
                ScrollView(showsIndicators: false) {
                    BrowseSkeletonGrid()
                        .padding(.bottom, 24)
                }
                .frame(maxHeight: .infinity)
            } else if model.isFilterScanning {
                MediaFilterScanningView()
            } else if model.filters.isActive {
                MediaFilteredEmptyView(hasMore: feed.hasMore,
                                       onScanMore: { model.scanMore() },
                                       onClear: { model.applyFilters(MediaFilters()) })
            } else if model.hiding.isActive {
                EmptyStateView(icon: "eye.slash",
                               title: "همهٔ عناوین پنهان شده‌اند",
                               message: "همهٔ عنوان‌های این دسته در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.")
                    .frame(maxHeight: .infinity)
            } else {
                EmptyStateView(icon: model.kind == .movie ? "film" : "tv",
                               title: "محتوایی در این دسته نیست",
                               message: "دسته یا نوع دیگری را امتحان کنید.")
                    .frame(maxHeight: .infinity)
            }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: BrowseMetrics.columns,
                          alignment: .trailing,
                          spacing: BrowseMetrics.rowSpacing) {
                    ForEach(items) { movie in
                        BrowsePosterCard(title: movie.title,
                                         posterURL: movie.posterURL,
                                         year: movie.year,
                                         imdb: movie.imdb,
                                         badge: movie.isSeries ? "سریال" : nil,
                                         sources: movie.sources,
                                         playSubtitle: movie.genreText,
                                         media: movie.isSeries ? nil : PlaybackInfo(kind: .movie, movie: movie),
                                         onOpen: { app.openMovie(movie) })
                            .onAppear {
                                Task { await feed.loadMoreIfNeeded(current: movie) }
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
