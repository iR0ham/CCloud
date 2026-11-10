import SwiftUI
import AppKit

// MARK: - Movie detail page (owner: ui-detail)

struct MovieDetailView: View {
    let movie: Movie

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var history: WatchHistoryStore
    @EnvironmentObject private var downloads: DownloadsStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var similar = SimilarTitlesModel()

    // MARK: Derived data

    private var playableSources: [MediaSource] { movie.sources.playable }

    private var resumePosition: Double? { history.resumePosition(movieID: movie.id) }

    private var preferredSource: MediaSource? {
        movie.sources.preferred(for: settings.preferredQuality)
    }

    private var isFavorite: Bool {
        favorites.isFavorite(id: movie.id, kind: .movie)
    }

    private var metaItems: [DetailMetaItem] {
        DetailMetaFactory.items(
            year: movie.year,
            imdb: movie.imdb,
            duration: movie.durationText,
            country: movie.countryText,
            age: DetailMetaFactory.ageRating(from: movie.description)
        )
    }

    private var subtitleText: String? {
        var parts: [String] = []
        if movie.year > 0 { parts.append(String(movie.year)) }
        if let duration = movie.durationText { parts.append(duration) }
        if !movie.genreText.isEmpty { parts.append(movie.genreText) }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                DetailHero(
                    title: movie.title,
                    coverURL: movie.coverURL,
                    posterURL: movie.posterURL,
                    meta: metaItems,
                    genres: movie.genres,
                    isFavorite: isFavorite,
                    onBack: { app.back() },
                    onFavorite: toggleFavorite
                )

                actionBar

                DetailSection(title: "داستان فیلم", icon: "text.quote") {
                    StoryText(text: movie.description)
                }

                sourcesSection

                similarSection

                    Color.clear.frame(height: 4).id("detail-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                guard DetailQA.scrollToBottom else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("detail-bottom", anchor: .bottom)
                }
            }
        }
        .task(id: similarKey) {
            await similar.load(genre: movie.genres.first,
                               isSeries: movie.isSeries,
                               excludingID: movie.id,
                               hiding: settings.contentHiding)
        }
    }

    private var similarKey: String {
        "\(movie.id)|\(movie.isSeries)|\(settings.contentHiding.isActive)"
    }

    @ViewBuilder
    private var similarSection: some View {
        if !similar.items.isEmpty {
            HomeRail(title: "عناوین مشابه",
                     subtitle: movie.genres.first.map { "در \($0.title)" },
                     items: similar.items,
                     onOpen: { app.openMovie($0) })
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: { play(preferredSource) }) {
                HStack(spacing: 7) {
                    Image(systemName: preferredSource == nil ? "play.slash.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(resumeLabel)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .opacity(preferredSource == nil ? 0.5 : 1)
            .help(preferredSource == nil ? "سورسی برای پخش موجود نیست" : resumeHelp)

            Button(action: toggleFavorite) {
                HStack(spacing: 6) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isFavorite ? Theme.red : Theme.text)
                    Text(isFavorite ? "در علاقه‌مندی‌ها" : "افزودن به علاقه‌مندی‌ها")
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer(minLength: 8)

            if let preferred = preferredSource {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text("پیشنهادی: \(preferred.qualityLabel)")
                }
                .font(.ccloud(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: Sources

    private var sourcesSection: some View {
        DetailSection(
            title: "کیفیت‌های موجود",
            subtitle: playableSources.isEmpty ? nil : "\(playableSources.count) سورس",
            icon: "4k.tv"
        ) {
            if playableSources.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 12))
                    Text("برای این فیلم سورس قابل پخشی ثبت نشده است.")
                        .font(.ccloud(12))
                }
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(playableSources) { source in
                        MediaSourceRow(
                            source: source,
                            isSelected: preferredSource?.id == source.id,
                            onPlay: { play(source) },
                            onCopy: { app.copyToPasteboard(source.url, toastMessage: "لینک کپی شد") },
                            onDownload: { download(source) }
                        )
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var resumeLabel: String {
        guard let resumePosition else { return "پخش" }
        return "ادامه از \(PlayerTime.string(resumePosition))"
    }

    private var resumeHelp: String {
        guard let resumePosition else { return "پخش با کیفیت پیشنهادی" }
        return "ادامهٔ تماشا از دقیقهٔ \(PlayerTime.string(resumePosition))"
    }

    private func play(_ source: MediaSource?) {
        let sources = playableSources
        guard !sources.isEmpty else {
            app.showToast("سورسی برای پخش موجود نیست")
            return
        }
        let request = PlaybackRequest(
            title: movie.title,
            subtitle: subtitleText,
            posterURL: movie.image.isEmpty ? nil : movie.image,
            sources: sources,
            preferredSourceID: source?.id,
            media: PlaybackInfo(kind: .movie, movie: movie),
            startAt: resumePosition ?? 0
        )
        app.playback = request
        openWindow(id: "Player", value: request)
    }

    private func toggleFavorite() {
        let added = favorites.toggle(movie: movie)
        app.showToast(added ? "به علاقه‌مندی‌ها اضافه شد" : "از علاقه‌مندی‌ها حذف شد")
    }

    private func download(_ source: MediaSource) {
        switch downloads.start(title: movie.title,
                               subtitle: subtitleText,
                               posterURL: movie.image.isEmpty ? nil : movie.image,
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
