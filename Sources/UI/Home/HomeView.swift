import SwiftUI
import Foundation

// OWNER: ui-home — landing page: mixed movie/series hero slider, latest and top-rated rails,
// category shortcuts. Macro-free local state (PROJECT.md §5.5).

@MainActor
final class HomeModel: ObservableObject {
    @Published private(set) var latestMovies: [Movie] = []
    @Published private(set) var latestSeries: [Movie] = []
    @Published private(set) var topMovies: [Movie] = []
    @Published private(set) var topSeries: [Movie] = []
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?
    @Published private(set) var slideIndex = 0
    @Published var isHeroPaused = false

    private var started = false
    private var hiding = ContentHiding()

    /// Newest films and series interleaved, so the hero step-through alternates between both.
    var slides: [Movie] {
        let movies = Array(latestMovies.prefix(3))
        let series = Array(latestSeries.prefix(3))
        var mixed: [Movie] = []
        for index in 0..<max(movies.count, series.count) {
            if index < movies.count { mixed.append(movies[index]) }
            if index < series.count { mixed.append(series[index]) }
        }
        return Array(mixed.prefix(6))
    }

    var currentSlide: Movie? {
        guard !slides.isEmpty else { return nil }
        return slides[min(slideIndex, slides.count - 1)]
    }

    var isEmpty: Bool {
        latestMovies.isEmpty && latestSeries.isEmpty && topMovies.isEmpty && topSeries.isEmpty
    }

    /// Reloads only when the hiding settings changed; a plain re-appearance keeps the rails.
    func loadIfNeeded(hiding newHiding: ContentHiding) async {
        if started, newHiding == hiding { return }
        started = true
        hiding = newHiding
        await reload()
    }

    func reload() async {
        isLoading = true
        error = nil

        let client = APIClient.shared
        let hiding = self.hiding
        async let newestMoviesTask = Self.loadMovies(client, sort: .newest, hiding: hiding)
        async let newestSeriesTask = Self.loadSeries(client, sort: .newest, hiding: hiding)
        async let ratedMoviesTask = Self.loadMovies(client, sort: .imdb, hiding: hiding)
        async let ratedSeriesTask = Self.loadSeries(client, sort: .imdb, hiding: hiding)

        var firstFailure: Error?
        do {
            latestMovies = try await newestMoviesTask
        } catch {
            firstFailure = firstFailure ?? error
        }
        do {
            latestSeries = try await newestSeriesTask
        } catch {
            firstFailure = firstFailure ?? error
        }
        do {
            topMovies = try await ratedMoviesTask
        } catch {
            firstFailure = firstFailure ?? error
        }
        do {
            topSeries = try await ratedSeriesTask
        } catch {
            firstFailure = firstFailure ?? error
        }

        isLoading = false
        slideIndex = 0

        if isEmpty, let firstFailure {
            error = (firstFailure as? LocalizedError)?.errorDescription
                ?? firstFailure.localizedDescription
        } else if isEmpty, !hiding.isActive {
            error = "محتوایی برای نمایش پیدا نشد"
        }
    }

    /// Hidden titles are dropped client-side, so walk a few pages to keep the rails populated.
    private static func loadMovies(_ client: APIClient,
                                   sort: SortOption,
                                   hiding: ContentHiding) async throws -> [Movie] {
        var merged: [Movie] = []
        var seen = Set<Int>()
        for page in 0..<3 {
            do {
                let items = try await client.movies(page: page, sort: sort)
                for item in items where !seen.contains(item.id) {
                    seen.insert(item.id)
                    merged.append(item)
                }
            } catch {
                if merged.isEmpty { throw error }
                break
            }
            if !hiding.isActive || merged.filter({ !hiding.isHidden($0) }).count >= 12 { break }
        }
        return hiding.isActive ? merged.filter { !hiding.isHidden($0) } : merged
    }

    private static func loadSeries(_ client: APIClient,
                                   sort: SortOption,
                                   hiding: ContentHiding) async throws -> [Movie] {
        var merged: [Movie] = []
        var seen = Set<Int>()
        for page in 0..<3 {
            do {
                let items = try await client.series(page: page, sort: sort).map { Movie(from: $0) }
                for item in items where !seen.contains(item.id) {
                    seen.insert(item.id)
                    merged.append(item)
                }
            } catch {
                if merged.isEmpty { throw error }
                break
            }
            if !hiding.isActive || merged.filter({ !hiding.isHidden($0) }).count >= 12 { break }
        }
        return hiding.isActive ? merged.filter { !hiding.isHidden($0) } : merged
    }

    func advanceSlide() {
        guard slideCount > 1, !isHeroPaused else { return }
        slideIndex = (slideIndex + 1) % slideCount
    }

    func previousSlide() {
        guard slideCount > 1 else { return }
        slideIndex = (slideIndex - 1 + slideCount) % slideCount
    }

    func selectSlide(_ index: Int) {
        guard index >= 0, index < slideCount else { return }
        slideIndex = index
    }

    private var slideCount: Int { slides.count }
}

// MARK: - Home screen

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: WatchHistoryStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = HomeModel()

    var body: some View {
        Group {
            if model.isLoading && model.isEmpty {
                HomeSkeleton()
            } else if model.isEmpty, let error = model.error {
                ErrorStateView(message: error) {
                    Task { await model.reload() }
                }
            } else if model.isEmpty, settings.contentHiding.isActive {
                EmptyStateView(icon: "eye.slash",
                               title: "محتوایی برای نمایش نیست",
                               message: "همهٔ عناوین این بخش در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.")
                    .frame(maxHeight: .infinity)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .task {
            await app.loadGenresIfNeeded()
            await model.loadIfNeeded(hiding: settings.contentHiding)
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.45)) { model.advanceSlide() }
            }
        }
        .onChange(of: app.refreshTick) { _, _ in
            Task {
                await app.loadGenres()
                await model.reload()
            }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 30) {
                    hero
                    recentHistory.padding(.horizontal, 32)
                    rails.padding(.horizontal, 32)
                    categoryStrip.padding(.horizontal, 32)
                    Color.clear.frame(height: 2).id("home-bottom")
                }
                .padding(.bottom, 26)
            }
            .task {
                guard DetailQA.scrollToBottom else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("home-bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack {
            ForEach(Array(model.slides.enumerated()), id: \.element.id) { pair in
                HomeHeroCard(
                    movie: pair.element,
                    index: pair.offset,
                    count: model.slides.count,
                    onPlay: { play(pair.element) },
                    onDetails: { app.openMovie(pair.element) },
                    onPrevious: { withAnimation(.easeInOut(duration: 0.45)) { model.previousSlide() } },
                    onNext: { withAnimation(.easeInOut(duration: 0.45)) { model.advanceSlide() } },
                    onSelect: { index in
                        withAnimation(.easeInOut(duration: 0.45)) { model.selectSlide(index) }
                    }
                )
                .opacity(pair.offset == model.slideIndex ? 1 : 0)
                .allowsHitTesting(pair.offset == model.slideIndex)
            }
        }
        .frame(height: HomeMetrics.heroHeight)
        .animation(.easeInOut(duration: 0.45), value: model.slideIndex)
        .onHover { model.isHeroPaused = $0 }
    }

    // MARK: Recently watched

    private var visibleHistoryEntries: [HistoryEntry] {
        let hiding = settings.contentHiding
        let visible = history.entries.filter { !hiding.isHidden($0) }
        return Array(visible.prefix(12))
    }

    @ViewBuilder
    private var recentHistory: some View {
        if !visibleHistoryEntries.isEmpty {
            HomeHistoryRail(entries: visibleHistoryEntries,
                            onSeeAll: { app.select(tab: .history) },
                            onOpen: { entry in playHistory(entry) })
        }
    }

    // MARK: Rails

    private var rails: some View {
        VStack(alignment: .trailing, spacing: 28) {
            if !model.latestMovies.isEmpty {
                HomeRail(title: "آخرین فیلم‌های اضافه‌شده",
                         subtitle: "تازه‌ترین‌ها",
                         items: model.latestMovies,
                         onSeeAll: { app.select(tab: .movies) },
                         onOpen: { app.openMovie($0) })
            }
            if !model.latestSeries.isEmpty {
                HomeRail(title: "آخرین سریال‌های اضافه‌شده",
                         subtitle: "قسمت‌های تازه",
                         items: model.latestSeries,
                         onSeeAll: { app.select(tab: .series) },
                         onOpen: { app.openMovie($0) })
            }
            if !model.topSeries.isEmpty {
                HomeRail(title: "برترین سریال‌ها",
                         subtitle: "بر اساس امتیاز IMDb",
                         items: model.topSeries,
                         onSeeAll: { app.select(tab: .series) },
                         onOpen: { app.openMovie($0) })
            }
            if !model.topMovies.isEmpty {
                HomeRail(title: "برترین فیلم‌ها",
                         subtitle: "بر اساس امتیاز IMDb",
                         items: model.topMovies,
                         onSeeAll: { app.select(tab: .movies) },
                         onOpen: { app.openMovie($0) })
            }
        }
    }

    // MARK: Categories

    private var visibleGenres: [Genre] {
        settings.hideRegionalOrigins
            ? app.genres.filter { !OriginFilter.hidesGenre($0.title) }
            : app.genres
    }

    @ViewBuilder
    private var categoryStrip: some View {
        if !visibleGenres.isEmpty {
            VStack(alignment: .trailing, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("دسته‌بندی‌ها")
                        .font(.ccloud(17, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("بر اساس ژانر")
                        .font(.ccloud(11))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                    Button {
                        app.select(tab: .categories)
                    } label: {
                        HStack(spacing: 4) {
                            Text("همه دسته‌ها")
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .font(.ccloud(11.5, weight: .semibold))
                        .foregroundStyle(Theme.accentBright)
                    }
                    .buttonStyle(.plain)
                    .help("نمایش همه دسته‌بندی‌ها")
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(visibleGenres.reversed())) { genre in
                                HomeCategoryChip(genre: genre) {
                                    app.openCategory(genre)
                                }
                                .environment(\.layoutDirection, .rightToLeft)
                                .id(genre.id)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    // macOS mirrors a RTL horizontal ScrollView's offset to the wrong end, so the
                    // strip runs physically left→right with the list reversed: the first chip then
                    // sits at the trailing (right) edge and scrolling moves toward older items.
                    .environment(\.layoutDirection, .leftToRight)
                    .defaultScrollAnchor(.trailing)
                    .onAppear { pinGenres(proxy) }
                    .onChange(of: visibleGenres.count) { _, _ in pinGenres(proxy) }
                }
                .frame(height: 36)
            }
        }
    }

    private func pinGenres(_ proxy: ScrollViewProxy) {
        guard let first = visibleGenres.first else { return }
        for delay in [0.03, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(first.id, anchor: .trailing)
            }
        }
    }

    // MARK: Actions

    /// History cards resume movies directly; series still open their detail page, where the
    /// primary button already knows the last watched episode.
    private func playHistory(_ entry: HistoryEntry) {
        guard let movie = entry.movie, !movie.isSeries else {
            if let movie = entry.movie {
                app.openMovie(movie)
            } else if let series = entry.series {
                app.openSeries(series)
            }
            return
        }
        let sources = movie.sources.playable
        guard !sources.isEmpty else {
            app.openMovie(movie)
            return
        }
        let request = PlaybackRequest(
            title: movie.title,
            subtitle: movie.genreText,
            posterURL: movie.image.isEmpty ? nil : movie.image,
            sources: sources,
            preferredSourceID: movie.sources.preferred(for: settings.preferredQuality)?.id,
            media: PlaybackInfo(kind: .movie, movie: movie),
            startAt: resumePosition(for: entry)
        )
        app.playback = request
        openWindow(id: "Player", value: request)
    }

    private func resumePosition(for entry: HistoryEntry) -> Double {
        guard let position = entry.position,
              let duration = entry.duration,
              duration > 60,
              position > 15,
              position < duration * 0.98 else { return 0 }
        return position
    }

    private func play(_ movie: Movie) {
        guard !movie.isSeries else {
            app.openMovie(movie)
            return
        }
        let sources = movie.sources.playable
        guard !sources.isEmpty else {
            app.openMovie(movie)
            return
        }
        let request = PlaybackRequest(
            title: movie.title,
            subtitle: movie.genreText,
            posterURL: movie.image.isEmpty ? nil : movie.image,
            sources: sources,
            preferredSourceID: movie.sources.preferred(for: settings.preferredQuality)?.id,
            media: PlaybackInfo(kind: .movie, movie: movie)
        )
        app.playback = request
        openWindow(id: "Player", value: request)
    }
}

// MARK: - Metrics

enum HomeMetrics {
    static let heroHeight: CGFloat = 430
    static let railCardWidth: CGFloat = 148
}

// MARK: - Hero card

struct HomeHeroCard: View {
    let movie: Movie
    let index: Int
    let count: Int
    let onPlay: () -> Void
    let onDetails: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelect: (Int) -> Void

    var body: some View {
        ZStack {
            artwork
            scrims
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: HomeMetrics.heroHeight)
        .clipped()
        .overlay(alignment: .leading) {
            if count > 1 {
                HomeHeroArrow(systemName: "chevron.right", help: "اسلاید قبلی", action: onPrevious)
                    .padding(.leading, 12)
            }
        }
        .overlay(alignment: .trailing) {
            if count > 1 {
                HomeHeroArrow(systemName: "chevron.left", help: "اسلاید بعدی", action: onNext)
                    .padding(.trailing, 12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if count > 1 {
                dots
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.38)))
                    .padding(.trailing, 22)
                    .padding(.bottom, 18)
            }
        }
    }

    private var backdropURL: URL? {
        if !movie.cover.isEmpty, let url = movie.coverURL { return url }
        return movie.posterURL
    }

    private var artwork: some View {
        CachedAsyncImage(url: backdropURL, placeholderIcon: "film")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var scrims: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.92), location: 0.0),
                    .init(color: .black.opacity(0.58), location: 0.38),
                    .init(color: .black.opacity(0.10), location: 0.78),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            // Keeps the window traffic lights readable over bright artwork.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.38), location: 0.0),
                    .init(color: .clear, location: 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.55), location: 0.82),
                    .init(color: .black.opacity(0.18), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Melts the artwork into the page instead of ending on a card edge.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.66),
                    .init(color: Theme.bg.opacity(0.55), location: 0.86),
                    .init(color: Theme.bg, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    TypeBadge(text: movie.isSeries ? "سریال" : "فیلم")
                }

                Text(movie.title)
                    .font(.ccloud(31, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.55), radius: 5, y: 2)

                if let summary {
                    Text(summary)
                        .font(.ccloud(12.5))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineSpacing(3)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 540, alignment: .leading)
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                }

                metaRow

                if !movie.genres.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(movie.genres.prefix(3))) { genre in
                            Text(genre.title)
                                .font(.ccloud(10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.86))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
                        }
                    }
                }

                actions
                    .padding(.top, 3)
            }
            .frame(maxWidth: 600, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 92)
        .padding(.top, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var summary: String? {
        PlotSummary.plot(from: movie.description)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if movie.year > 0 {
                metaItem("calendar", String(movie.year))
            }
            if movie.imdb > 0 {
                metaItem("star.fill", String(format: "%.1f", movie.imdb), tint: Theme.gold)
            }
            if !movie.countryText.isEmpty {
                metaItem("globe", movie.countryText)
            }
        }
        .lineLimit(1)
    }

    private func metaItem(_ icon: String, _ text: String, tint: Color = .white.opacity(0.82)) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.ccloud(11.5, weight: .medium))
        }
        .foregroundStyle(tint)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(movie.isSeries ? "مشاهده قسمت‌ها" : "پخش فیلم")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(action: onDetails) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("جزئیات")
                }
            }
            .buttonStyle(HomeGlassButtonStyle())
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Capsule()
                        .fill(Color.white.opacity(index == self.index ? 0.95 : 0.36))
                        .frame(width: index == self.index ? 20 : 7, height: 7)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
    }
}

struct HomeHeroArrow: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(hover.isHovering ? 0.72 : 0.42)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .scaleEffect(hover.isHovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .help(help)
    }
}

struct HomeGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ccloud(13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.22 : 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
            )
    }
}

// MARK: - Horizontal rail

struct HomeRail: View {
    let title: String
    var subtitle: String? = nil
    let items: [Movie]
    var onSeeAll: (() -> Void)? = nil
    let onOpen: (Movie) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.ccloud(17, weight: .bold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.ccloud(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 4) {
                            Text("مشاهده همه")
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .font(.ccloud(11.5, weight: .semibold))
                        .foregroundStyle(Theme.accentBright)
                    }
                    .buttonStyle(.plain)
                    .help("مشاهده همه")
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(items.reversed())) { movie in
                            BrowsePosterCard(title: movie.title,
                                             posterURL: movie.posterURL,
                                             year: movie.year,
                                             imdb: movie.imdb,
                                             badge: movie.isSeries ? "سریال" : nil,
                                             sources: movie.sources,
                                             playSubtitle: movie.genreText,
                                             media: movie.isSeries ? nil : PlaybackInfo(kind: .movie, movie: movie),
                                             onOpen: { onOpen(movie) })
                                .frame(width: HomeMetrics.railCardWidth)
                                .environment(\.layoutDirection, .rightToLeft)
                                .id(movie.id)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
                }
                // See the category strip: RTL + horizontal ScrollView misplaces the offset on
                // macOS, so lay the reversed list out LTR and anchor it at the right edge.
                .environment(\.layoutDirection, .leftToRight)
                .defaultScrollAnchor(.trailing)
                .onAppear { pin(proxy) }
                .onChange(of: items.count) { _, _ in pin(proxy) }
            }
        }
    }

    private func pin(_ proxy: ScrollViewProxy) {
        guard let first = items.first else { return }
        for delay in [0.03, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(first.id, anchor: .trailing)
            }
        }
    }
}

// MARK: - Recently watched rail

struct HomeHistoryRail: View {
    let entries: [HistoryEntry]
    let onSeeAll: () -> Void
    let onOpen: (HistoryEntry) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("آخرین مشاهده‌شده‌ها")
                    .font(.ccloud(17, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("ادامه از همان‌جا")
                    .font(.ccloud(11))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                Button(action: onSeeAll) {
                    HStack(spacing: 4) {
                        Text("مشاهده همه")
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .font(.ccloud(11.5, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                }
                .buttonStyle(.plain)
                .help("نمایش تاریخچهٔ کامل تماشا")
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(entries.reversed())) { entry in
                            HomeHistoryCard(entry: entry) { onOpen(entry) }
                                .frame(width: HomeMetrics.railCardWidth)
                                .environment(\.layoutDirection, .rightToLeft)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
                }
                .environment(\.layoutDirection, .leftToRight)
                .defaultScrollAnchor(.trailing)
                .onAppear { pin(proxy) }
                .onChange(of: entries.count) { _, _ in pin(proxy) }
            }
        }
    }

    private func pin(_ proxy: ScrollViewProxy) {
        guard let first = entries.first else { return }
        for delay in [0.03, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(first.id, anchor: .trailing)
            }
        }
    }
}

struct HomeHistoryCard: View {
    let entry: HistoryEntry
    let onOpen: () -> Void

    private var progress: Double? {
        if entry.kind == .movie {
            return entry.progress > 0.01 ? entry.progress : nil
        }
        guard let last = entry.lastEpisode, last.progress > 0.01 else { return nil }
        return last.progress
    }

    private var resumeTime: Double? {
        guard let position = entry.position,
              let duration = entry.duration,
              duration > 60,
              position > 15,
              position < duration * 0.98 else { return nil }
        return position
    }

    private var subtitle: String {
        switch entry.kind {
        case .movie:
            if let resumeTime { return "ادامه از \(PlayerTime.string(resumeTime))" }
            if let progress { return progress < 0.995 ? percentText(progress) : "تماشا شده" }
            return "فیلم"
        case .series:
            guard let last = entry.lastEpisode else { return "سریال" }
            var parts: [String] = []
            let episode = last.label.isEmpty ? last.seasonTitle : last.label
            if !episode.isEmpty { parts.append(episode) }
            if let resumeTime {
                parts.append("ادامه از \(PlayerTime.string(resumeTime))")
            } else if let progress {
                parts.append(progress < 0.995 ? percentText(progress) : "تماشا شده")
            }
            if parts.isEmpty { parts.append("سریال") }
            return parts.joined(separator: " • ")
        }
    }

    private func percentText(_ value: Double) -> String {
        "٪\(browseNumber(Int((min(max(value, 0), 1) * 100).rounded())))"
    }

    var body: some View {
        PosterCard(title: entry.title,
                   posterURL: entry.posterURL,
                   year: entry.year,
                   imdb: entry.imdb,
                   badge: entry.kind == .series ? "سریال" : nil,
                   subtitle: subtitle,
                   progress: progress,
                   action: onOpen)
            .help(entry.title)
    }
}

// MARK: - Category chip

struct HomeCategoryChip: View {
    let genre: Genre
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: CategoryStyle.icon(for: genre.title))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                Text(genre.title)
                    .font(.ccloud(12, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(hover.isHovering ? Theme.cardHover : Theme.card))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .help("نمایش \(genre.title)")
    }
}

// MARK: - Skeleton

struct HomeSkeleton: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.6) / 1.6
            let pulse = 0.25 + ((sin(phase * 2 * .pi) + 1) / 2) * 0.5

            ScrollView(showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 28) {
                    Rectangle()
                        .fill(Theme.card)
                        .frame(height: HomeMetrics.heroHeight)
                        .overlay(Rectangle().fill(Theme.cardHover.opacity(pulse)))
                        .overlay(
                            LinearGradient(colors: [.clear, Theme.bg],
                                           startPoint: .center,
                                           endPoint: .bottom)
                        )

                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .trailing, spacing: 12) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.cardHover.opacity(pulse))
                                .frame(width: 190, height: 16)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            HStack(spacing: 14) {
                                ForEach(0..<6, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                        .fill(Theme.card)
                                        .frame(width: HomeMetrics.railCardWidth, height: 222)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                                .fill(Theme.cardHover.opacity(pulse))
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .clipped()
                        }
                        .padding(.horizontal, 32)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .accessibilityHidden(true)
    }
}
