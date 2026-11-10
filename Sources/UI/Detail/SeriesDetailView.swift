import SwiftUI
import AppKit

// MARK: - Series detail page (owner: ui-detail) — backdrop, seasons, episodes

@MainActor
final class SeriesDetailModel: ObservableObject {
    @Published private(set) var seasons: [Season] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedSeasonID: Int?

    private var loadedSeriesID: Int?

    static func defaultsKey(seriesID: Int) -> String { "ccloud.lastSeason.\(seriesID)" }

    var selectedSeason: Season? {
        if let id = selectedSeasonID, let hit = seasons.first(where: { $0.id == id }) { return hit }
        return seasons.first
    }

    func load(seriesID: Int, force: Bool = false) async {
        if !force {
            if isLoading { return }
            if loadedSeriesID == seriesID && !seasons.isEmpty { return }
        }
        loadedSeriesID = seriesID
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await APIClient.shared.seasons(seriesId: seriesID)
            seasons = fetched
            restoreSelection(seriesID: seriesID)
            isLoading = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoading = false
        }
    }

    func select(_ season: Season, seriesID: Int) {
        selectedSeasonID = season.id
        UserDefaults.standard.set(season.id, forKey: Self.defaultsKey(seriesID: seriesID))
    }

    /// Remember the season the user last opened (per series), like the Android app's watched state.
    private func restoreSelection(seriesID: Int) {
        let stored = UserDefaults.standard.integer(forKey: Self.defaultsKey(seriesID: seriesID))
        if stored != 0, seasons.contains(where: { $0.id == stored }) {
            selectedSeasonID = stored
        } else if let first = seasons.first {
            selectedSeasonID = first.id
            UserDefaults.standard.set(first.id, forKey: Self.defaultsKey(seriesID: seriesID))
        }
    }
}

// MARK: - Episode row

struct SeriesEpisodeRow: View {
    let episode: Episode
    let index: Int
    let seasonTitle: String
    let seriesTitle: String
    let fallbackPoster: URL?
    let qualityPreference: String
    var isWatched: Bool = false
    var isLastWatched: Bool = false
    var watchedProgress: Double = 0
    let onPlay: (MediaSource?) -> Void
    let onCopy: (MediaSource) -> Void
    var onDownload: ((MediaSource) -> Void)? = nil

    @StateObject private var hover = HoverState()

    private var sources: [MediaSource] { episode.playableSources }

    private var preferred: MediaSource? { episode.sources.preferred(for: qualityPreference) }

    private var thumbnailURL: URL? { episode.image.flatMap { URL(string: $0) } ?? fallbackPoster }

    private var episodeLabel: String {
        if let number = episode.episodeNumber { return "قسمت \(number)" }
        return episode.title.isEmpty ? "قسمت \(index + 1)" : episode.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(episodeLabel)
                        .font(.ccloud(13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let duration = episode.duration, !duration.isEmpty, duration != "null" {
                        Text(duration)
                            .font(.ccloud(10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if isWatched {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("دیده شده")
                                .font(.ccloud(9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.green.opacity(0.13)))
                    }
                    if isLastWatched {
                        Text("تا اینجا")
                            .font(.ccloud(9, weight: .bold))
                            .foregroundStyle(Theme.accentBright)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent.opacity(0.18)))
                            .help("آخرین قسمتی که دیده‌اید")
                    }
                }
                if let description = episode.description,
                   !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(description)
                        .font(.ccloud(10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                qualityChips
                if isWatched, watchedProgress > 0.01, watchedProgress < 0.98 {
                    watchProgress
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hover.isHovering
                      ? Theme.cardHover
                      : (isLastWatched ? Theme.accent.opacity(0.08) : Theme.bgElevated))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isLastWatched ? Theme.accent.opacity(0.6) : Theme.stroke,
                              lineWidth: isLastWatched ? 1.2 : 1)
        )
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hover.isHovering)
    }

    private var watchProgress: some View {
        HStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stroke)
                    Capsule()
                        .fill(Theme.green)
                        .frame(width: geo.size.width * watchedProgress)
                }
            }
            .frame(width: 84, height: 3)
            .environment(\.layoutDirection, .leftToRight)
            Text("٪\(browseNumber(Int((watchedProgress * 100).rounded()))) تماشا شده")
                .font(.ccloud(9))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            CachedAsyncImage(url: thumbnailURL, placeholderIcon: "tv")
                .frame(width: 104, height: 59)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            if sources.isEmpty {
                Text("بدون سورس")
                    .font(.ccloud(8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.red.opacity(0.85)))
                    .padding(4)
            }
        }
    }

    private var qualityChips: some View {
        HStack(spacing: 5) {
            if sources.isEmpty {
                Text("سورسی برای این قسمت ثبت نشده است")
                    .font(.ccloud(9.5))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(sources) { source in
                    Button {
                        onPlay(source)
                    } label: {
                        Text(source.qualityLabel)
                            .font(.ccloud(9.5, weight: .medium))
                            .foregroundStyle(source.id == preferred?.id ? Theme.accentBright : Theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(source.id == preferred?.id
                                               ? Theme.accent.opacity(0.16)
                                               : Theme.card)
                            )
                            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("پخش با کیفیت \(source.qualityLabel)")
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 5) {
            if let source = preferred {
                IconActionButton(
                    systemName: "doc.on.doc",
                    help: "کپی لینک",
                    tint: Theme.textSecondary,
                    action: { onCopy(source) }
                )
                if let onDownload {
                    IconActionButton(
                        systemName: "arrow.down.circle",
                        help: "دانلود این قسمت",
                        tint: Theme.textSecondary,
                        action: { onDownload(source) }
                    )
                }
            }
            Button(action: { onPlay(preferred) }) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 8.5, weight: .bold))
                    Text("پخش")
                }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .opacity(sources.isEmpty ? 0.45 : 1)
            .disabled(sources.isEmpty)
        }
    }
}

// MARK: - Series detail view

struct SeriesDetailView: View {
    let series: Series

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var history: WatchHistoryStore
    @EnvironmentObject private var downloads: DownloadsStore
    @Environment(\.openWindow) private var openWindow

    @StateObject private var model = SeriesDetailModel()
    @StateObject private var similar = SimilarTitlesModel()

    private var similarKey: String {
        "\(series.id)|\(settings.contentHiding.isActive)"
    }

    private var isFavorite: Bool {
        favorites.isFavorite(id: series.id, kind: .series)
    }

    private var metaItems: [DetailMetaItem] {
        DetailMetaFactory.items(
            year: series.year,
            imdb: series.imdb,
            duration: series.durationText,
            country: series.countryText,
            age: DetailMetaFactory.ageRating(from: series.description)
        )
    }

    private var subtitleText: String? {
        var parts: [String] = []
        if series.year > 0 { parts.append(String(series.year)) }
        if let duration = series.durationText { parts.append(duration) }
        if !series.genreText.isEmpty { parts.append(series.genreText) }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var seasonSummary: String? {
        guard !model.seasons.isEmpty else { return nil }
        let episodes = model.seasons.reduce(0) { $0 + $1.episodes.count }
        var parts = ["\(model.seasons.count) فصل", "\(episodes) قسمت"]
        if let last = history.lastWatchedEpisode(seriesID: series.id) {
            var watched = "تا \(last.label)"
            if !last.seasonTitle.isEmpty { watched += " • \(last.seasonTitle)" }
            parts.append(watched)
        }
        return parts.joined(separator: " • ")
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                DetailHero(
                    title: series.title,
                    coverURL: series.coverURL,
                    posterURL: series.posterURL,
                    meta: metaItems,
                    genres: series.genres,
                    isFavorite: isFavorite,
                    onBack: { app.back() },
                    onFavorite: toggleFavorite
                )

                actionBar

                DetailSection(title: "داستان سریال", icon: "text.quote") {
                    StoryText(text: series.description)
                }

                episodesSection

                similarSection

                    Color.clear.frame(height: 4).id("detail-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: series.id) {
                await model.load(seriesID: series.id)
                guard DetailQA.scrollToBottom else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("detail-bottom", anchor: .bottom)
                }
            }
        }
        .task(id: similarKey) {
            await similar.load(genre: series.genres.first,
                               isSeries: true,
                               excludingID: series.id,
                               hiding: settings.contentHiding)
        }
    }

    @ViewBuilder
    private var similarSection: some View {
        if !similar.items.isEmpty {
            HomeRail(title: "عناوین مشابه",
                     subtitle: series.genres.first.map { "در \($0.title)" },
                     items: similar.items,
                     onOpen: { app.openMovie($0) })
        }
    }

    // MARK: Action bar

    private var orderedEpisodes: [(season: Season, episode: Episode)] {
        model.seasons.flatMap { season in
            season.episodes.filter { !$0.playableSources.isEmpty }.map { (season, $0) }
        }
    }

    /// Where the primary play button should start: the unfinished episode, the next one after a
    /// finished episode, or the very first episode.
    private var resumeTarget: (season: Season, episode: Episode, startAt: Double)? {
        let ordered = orderedEpisodes
        guard let first = ordered.first else { return nil }
        guard let last = history.lastWatchedEpisode(seriesID: series.id),
              let index = ordered.firstIndex(where: { $0.episode.id == last.id }) else {
            return (first.season, first.episode, 0)
        }
        if let position = history.resumePosition(seriesID: series.id, episodeID: last.id) {
            return (ordered[index].season, ordered[index].episode, position)
        }
        if index + 1 < ordered.count {
            return (ordered[index + 1].season, ordered[index + 1].episode, 0)
        }
        return (ordered[index].season, ordered[index].episode, 0)
    }

    private var playButtonTitle: String {
        guard let target = resumeTarget else { return "پخش اولین قسمت" }
        let label = target.episode.episodeNumber.map { "قسمت \($0)" } ?? target.episode.title
        if target.startAt > 0 { return "ادامه \(label)" }
        if history.lastWatchedEpisode(seriesID: series.id) != nil { return "پخش \(label)" }
        return "پخش اولین قسمت"
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: toggleFavorite) {
                HStack(spacing: 6) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isFavorite ? Theme.red : Theme.text)
                    Text(isFavorite ? "در علاقه‌مندی‌ها" : "افزودن به علاقه‌مندی‌ها")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            if let summary = seasonSummary {
                Text(summary)
                    .font(.ccloud(11.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            Button {
                guard let target = resumeTarget else {
                    app.showToast("قسمتی برای پخش موجود نیست")
                    return
                }
                model.select(target.season, seriesID: series.id)
                playEpisode(target.episode,
                            season: target.season,
                            source: target.episode.sources.preferred(for: settings.preferredQuality),
                            startAt: target.startAt)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                    Text(playButtonTitle)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .opacity(model.seasons.isEmpty ? 0.5 : 1)
            .disabled(model.seasons.isEmpty)
        }
    }

    // MARK: Episodes

    private var episodesSection: some View {
        DetailSection(
            title: "فصل‌ها و قسمت‌ها",
            subtitle: seasonSummary,
            icon: "rectangle.stack"
        ) {
            if model.isLoading && model.seasons.isEmpty {
                LoadingView(text: "در حال دریافت قسمت‌ها…")
                    .frame(height: 170)
            } else if let error = model.errorMessage, model.seasons.isEmpty {
                ErrorStateView(message: error, retryTitle: "تلاش دوباره") {
                    Task { await model.load(seriesID: series.id, force: true) }
                }
                .frame(height: 210)
            } else if model.seasons.isEmpty {
                EmptyStateView(
                    icon: "tv.slash",
                    title: "فصلی برای نمایش وجود ندارد",
                    message: "هنوز فصلی برای این سریال منتشر نشده است."
                )
                .frame(height: 180)
            } else {
                seasonPicker
                if let season = model.selectedSeason {
                    episodesList(season: season)
                }
            }
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.seasons) { season in
                    FilterChip(
                        title: season.title,
                        isSelected: model.selectedSeasonID == season.id,
                        action: { model.select(season, seriesID: series.id) }
                    )
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func episodesList(season: Season) -> some View {
        let watched = history.entry(seriesID: series.id)?.episodes ?? []
        let watchedByID = Dictionary(watched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lastWatchedID = history.lastWatchedEpisode(seriesID: series.id)?.id
        let watchedCount = season.episodes.reduce(0) { $0 + (watchedByID[$1.id] == nil ? 0 : 1) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(season.title)
                    .font(.ccloud(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("(\(season.episodes.count) قسمت)")
                    .font(.ccloud(10.5))
                    .foregroundStyle(Theme.textTertiary)
                if watchedCount > 0 {
                    Text("• \(browseNumber(watchedCount)) دیده شده")
                        .font(.ccloud(10.5, weight: .medium))
                        .foregroundStyle(Theme.green)
                }
                Spacer(minLength: 0)
            }

            if season.episodes.isEmpty {
                EmptyStateView(icon: "film", title: "قسمتی موجود نیست")
                    .frame(height: 120)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(season.episodes.enumerated()), id: \.element.id) { pair in
                        let watchedEpisode = watchedByID[pair.element.id]
                        SeriesEpisodeRow(
                            episode: pair.element,
                            index: pair.offset,
                            seasonTitle: season.title,
                            seriesTitle: series.title,
                            fallbackPoster: series.posterURL,
                            qualityPreference: settings.preferredQuality,
                            isWatched: watchedEpisode != nil,
                            isLastWatched: pair.element.id == lastWatchedID,
                            watchedProgress: watchedEpisode?.progress ?? 0,
                            onPlay: { source in
                                model.select(season, seriesID: series.id)
                                playEpisode(pair.element,
                                            season: season,
                                            source: source,
                                            startAt: history.resumePosition(seriesID: series.id,
                                                                            episodeID: pair.element.id) ?? 0)
                            },
                            onCopy: { source in
                                app.copyToPasteboard(source.url, toastMessage: "لینک قسمت کپی شد")
                            },
                            onDownload: { source in
                                downloadEpisode(pair.element, season: season, source: source)
                            }
                        )
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: Actions

    private func playEpisode(_ episode: Episode,
                             season: Season,
                             source: MediaSource?,
                             startAt: Double = 0) {
        let sources = episode.playableSources
        guard !sources.isEmpty else {
            app.showToast("سورسی برای این قسمت موجود نیست")
            return
        }
        let label = episode.episodeNumber.map { "قسمت \($0)" } ?? episode.title
        var parts: [String] = [season.title]
        if !label.isEmpty { parts.append(label) }
        let poster = episode.image.flatMap { $0.isEmpty ? nil : $0 } ?? series.image
        let request = PlaybackRequest(
            title: series.title,
            subtitle: parts.joined(separator: " • "),
            posterURL: poster.isEmpty ? nil : poster,
            sources: sources,
            preferredSourceID: source?.id,
            media: PlaybackInfo(kind: .series,
                                series: series,
                                episodeID: episode.id,
                                seasonTitle: season.title,
                                episodeLabel: label),
            upcomingEpisodes: upcomingEpisodes(after: episode),
            startAt: startAt
        )
        app.playback = request
        openWindow(id: "Player", value: request)
    }

    /// Playable episodes after `episode` across every season, so the player's «قسمت بعد» can
    /// walk the whole series without coming back to the detail page.
    private func upcomingEpisodes(after episode: Episode) -> [PlaybackEpisode] {
        let ordered: [(season: Season, episode: Episode)] = model.seasons.flatMap { season in
            season.episodes.compactMap { candidate in
                candidate.playableSources.isEmpty ? nil : (season, candidate)
            }
        }
        guard let index = ordered.firstIndex(where: { $0.episode.id == episode.id }) else { return [] }
        let posterFallback = series.image.isEmpty ? nil : series.image
        return ordered[(index + 1)...].map { pair in
            let label = pair.episode.episodeNumber.map { "قسمت \($0)" } ?? pair.episode.title
            let parts = [pair.season.title, label].filter { !$0.isEmpty }
            let poster = pair.episode.image.flatMap { $0.isEmpty ? nil : $0 } ?? posterFallback
            return PlaybackEpisode(
                id: pair.episode.id,
                subtitle: parts.joined(separator: " • "),
                posterURL: poster,
                sources: pair.episode.playableSources,
                preferredSourceID: pair.episode.sources.preferred(for: settings.preferredQuality)?.id,
                episodeID: pair.episode.id,
                seasonTitle: pair.season.title,
                episodeLabel: label
            )
        }
    }

    private func toggleFavorite() {
        let added = favorites.toggle(series: series)
        app.showToast(added ? "به علاقه‌مندی‌ها اضافه شد" : "از علاقه‌مندی‌ها حذف شد")
    }

    private func downloadEpisode(_ episode: Episode, season: Season, source: MediaSource) {
        let label = episode.episodeNumber.map { "قسمت \($0)" } ?? episode.title
        let title = "\(series.title) - \(label)"
        let poster = episode.image.flatMap { $0.isEmpty ? nil : $0 } ?? (series.image.isEmpty ? nil : series.image)
        switch downloads.start(title: title,
                               subtitle: season.title,
                               posterURL: poster,
                               source: source) {
        case .started:
            app.showToast("دانلود آغاز شد؛ پیشرفت را در تنظیمات ببینید")
        case .duplicate:
            app.showToast("این دانلود از قبل در حال انجام است")
        case .unsupported:
            app.copyToPasteboard(source.url, toastMessage: "این سورس قابل دانلود مستقیم نیست؛ لینک کپی شد")
        }
    }
}
