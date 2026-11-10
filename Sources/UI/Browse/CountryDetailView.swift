import SwiftUI
import Foundation
import Combine

// OWNER: ui-browse — Country detail: banner header, sort menu and the per-country poster feed.
// (Moved here from Sources/UI/Detail/CountryDetailView.swift during integration.)

@MainActor
final class CountryFeedModel: ObservableObject {
    @Published private(set) var feed: PagedFeed<Movie>
    @Published private(set) var sort: SortOption = .newest
    @Published private(set) var hiding = ContentHiding()
    @Published private(set) var isFilterScanning = false
    @Published private(set) var didFinishInitialLoad = false

    private var country: Country?
    private var started = false
    private var generation = 0
    private var filterScanGeneration = 0
    private var filterScanTask: Task<Void, Never>?
    private var feedObservation: AnyCancellable?

    var isPostFiltering: Bool { hiding.isActive }

    var visibleItems: [Movie] {
        guard hiding.isActive else { return feed.items }
        return feed.items.filter { !hiding.isHidden($0) }
    }

    init() {
        feed = PagedFeed<Movie> { _ in [] }
        feedObservation = feed.forwardChanges(to: self)
    }

    func start(country: Country) {
        guard !started else { return }
        started = true
        self.country = country
        reload()
    }

    func setHiding(_ new: ContentHiding) {
        guard new != hiding else { return }
        hiding = new
        if didFinishInitialLoad { startFilterScan() }
    }

    func selectSort(_ option: SortOption) {
        guard option != sort else { return }
        sort = option
        reload()
    }

    /// Footer action: keep loading pages until another visible title appears.
    func scanMore() {
        guard hiding.isActive, !isFilterScanning else { return }
        filterScanGeneration += 1
        let generation = filterScanGeneration
        let snapshot = hiding
        isFilterScanning = true
        filterScanTask = Task { [weak self] in
            guard let self else { return }
            await scanFeedForMore(self.feed, matcher: { !snapshot.isHidden($0) })
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
        guard hiding.isActive else {
            isFilterScanning = false
            return
        }
        let snapshot = hiding
        isFilterScanning = true
        filterScanTask = Task { [weak self] in
            guard let self else { return }
            await scanFeed(self.feed, matcher: { !snapshot.isHidden($0) })
            guard self.filterScanGeneration == generation else { return }
            self.isFilterScanning = false
        }
    }

    private func reload() {
        guard let country else { return }
        generation += 1
        let generation = generation
        let sort = sort
        didFinishInitialLoad = false

        let feed = PagedFeed<Movie> { page in
            try await APIClient.shared.countryPosters(countryId: country.id, page: page, sort: sort)
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

struct CountryDetailView: View {
    let country: Country
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = CountryFeedModel()

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            header
            content
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .task {
            model.setHiding(settings.contentHiding)
            model.start(country: country)
        }
        .onChange(of: app.refreshTick) { _, _ in
            model.refresh()
        }
    }

    private var subtitle: String {
        let feed = model.feed
        let items = model.visibleItems
        if !items.isEmpty {
            return browseSubtitle(count: items.count,
                                  noun: "عنوان",
                                  trailing: model.isPostFiltering ? "فیلترشده" : model.sort.title)
        }
        if feed.error != nil { return "اتصال به سرور برقرار نشد" }
        if model.isFilterScanning { return "در حال بررسی عناوین…" }
        if model.hiding.isActive, !feed.items.isEmpty { return "همهٔ عناوین پنهان شده‌اند" }
        return "در حال دریافت عنوان‌های \(country.title)…"
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
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

            CachedAsyncImage(url: country.imageURL, placeholderIcon: "globe")
                .frame(width: 88, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )

            SectionHeader(title: country.title, subtitle: subtitle)

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
            } else if model.hiding.isActive {
                EmptyStateView(icon: "eye.slash",
                               title: "همهٔ عناوین پنهان شده‌اند",
                               message: "همهٔ عنوان‌های این کشور در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.")
                    .frame(maxHeight: .infinity)
            } else {
                EmptyStateView(icon: "film",
                               title: "عنوانی برای این کشور نیست",
                               message: "مرتب‌سازی دیگری را امتحان کنید یا کشور دیگری را انتخاب کنید.")
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
