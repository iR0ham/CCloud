import SwiftUI

// OWNER: ui-browse — Favorites: two poster sections (movies / series) with hover removal,
// context menus, clear-all confirmation and a friendly empty state.

@MainActor
final class FavoritesUIModel: ObservableObject {
    @Published var showClearConfirm = false
}

struct FavoritesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var ui = FavoritesUIModel()

    private var visibleEntries: [FavoriteEntry] {
        let hiding = settings.contentHiding
        guard hiding.isActive else { return favorites.entries }
        return favorites.entries.filter { !hiding.isHidden($0) }
    }

    private var visibleMovies: [FavoriteEntry] {
        visibleEntries.filter { $0.kind == .movie }
    }

    private var visibleSeries: [FavoriteEntry] {
        visibleEntries.filter { $0.kind == .series }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            header

            if favorites.entries.isEmpty {
                EmptyStateView(icon: "heart.slash",
                               title: "علاقه‌مندی‌ها خالی است",
                               message: "در صفحهٔ جزئیات هر فیلم یا سریال روی قلب بزنید تا اینجا ذخیره شود.")
                    .frame(maxHeight: .infinity)
            } else if visibleEntries.isEmpty {
                EmptyStateView(icon: "eye.slash",
                               title: "همهٔ علاقه‌مندی‌ها پنهان شده‌اند",
                               message: "همهٔ عنوان‌های ذخیره‌شده در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.")
                    .frame(maxHeight: .infinity)
            } else {
                sections
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .task { await runQAIfRequested() }
        .alert("حذف همهٔ علاقه‌مندی‌ها",
               isPresented: Binding(get: { ui.showClearConfirm }, set: { ui.showClearConfirm = $0 })) {
            Button("حذف همه", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { favorites.clear() }
                app.showToast("فهرست علاقه‌مندی‌ها پاک شد")
            }
            Button("انصراف", role: .cancel) { }
        } message: {
            Text("همهٔ عنوان‌های ذخیره‌شده حذف می‌شوند. این عمل قابل بازگشت نیست.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 14) {
            SectionHeader(title: "علاقه‌مندی‌ها", subtitle: subtitle)

            if !favorites.entries.isEmpty {
                Button {
                    ui.showClearConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                        Text("پاک کردن همه")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .help("حذف همهٔ عنوان‌های ذخیره‌شده")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        let total = favorites.entries.count
        let visible = visibleEntries.count
        guard total > 0 else { return "هنوز چیزی ذخیره نکرده‌اید" }
        if visible != total {
            return "\(browseNumber(visible)) از \(browseNumber(total)) عنوان ذخیره‌شده"
        }
        return browseSubtitle(count: visible, noun: "عنوان ذخیره‌شده")
    }

    // MARK: Sections

    private var sections: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 30) {
                if !visibleMovies.isEmpty {
                    section(title: "فیلم‌ها",
                            icon: "film",
                            entries: visibleMovies)
                }
                if !visibleSeries.isEmpty {
                    section(title: "سریال‌ها",
                            icon: "tv",
                            entries: visibleSeries)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private func section(title: String, icon: String, entries: [FavoriteEntry]) -> some View {
        VStack(alignment: .trailing, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                Text(title)
                    .font(.ccloud(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(browseNumber(entries.count))
                    .font(.ccloud(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.card))
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: BrowseMetrics.columns,
                      alignment: .trailing,
                      spacing: BrowseMetrics.rowSpacing) {
                ForEach(entries) { entry in
                    FavoriteEntryCard(entry: entry,
                                      onOpen: { open(entry) },
                                      onRemove: { remove(entry) })
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func open(_ entry: FavoriteEntry) {
        if let movie = entry.movie {
            app.openMovie(movie)
        } else if let series = entry.series {
            app.openSeries(series)
        }
    }

    private func remove(_ entry: FavoriteEntry) {
        withAnimation(.easeInOut(duration: 0.2)) {
            favorites.remove(id: entry.mediaID,
                             kind: entry.kind == .movie ? .movie : .series)
        }
        app.showToast("«\(entry.title)» از علاقه‌مندی‌ها حذف شد")
    }

    // MARK: QA hooks (explicit launch flags only, never used by normal launches)

    /// `--seed-favorites-qa` fills a few live titles so the grids can be snapshot-verified,
    /// `--clear-favorites-qa` empties the list again.
    private func runQAIfRequested() async {
        let args = CommandLine.arguments
        guard args.contains("--seed-favorites-qa") || args.contains("--clear-favorites-qa") else { return }
        if args.contains("--clear-favorites-qa") {
            favorites.clear()
            return
        }
        guard favorites.entries.isEmpty else { return }
        if let movies = try? await APIClient.shared.movies(page: 0) {
            for movie in movies.prefix(4) { favorites.toggle(movie: movie) }
        }
        if let series = try? await APIClient.shared.series(page: 0) {
            for item in series.prefix(3) { favorites.toggle(series: item) }
        }
    }
}

// MARK: - Favorited poster with hover remove button

struct FavoriteEntryCard: View {
    let entry: FavoriteEntry
    let onOpen: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var hover = HoverState()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PosterCard(title: entry.title,
                       posterURL: entry.posterURL,
                       year: entry.year,
                       imdb: entry.imdb,
                       badge: entry.kind == .series ? "سریال" : nil,
                       action: onOpen)

            if hover.isHovering {
                Button(action: onRemove) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.red.opacity(0.92)))
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .help("حذف از علاقه‌مندی‌ها")
                .padding(7)
                .transition(.opacity)
            }
        }
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hover.isHovering)
        .contextMenu {
            Button("مشاهده جزئیات", action: onOpen)
            Button("حذف از علاقه‌مندی‌ها", action: onRemove)
            if let movie = entry.movie, !movie.sources.playable.isEmpty {
                Divider()
                Button("پخش «\(entry.title)»") {
                    let request = PlaybackRequest(
                        title: entry.title,
                        subtitle: movie.genreText,
                        posterURL: movie.image,
                        sources: movie.sources,
                        media: PlaybackInfo(kind: .movie, movie: movie)
                    )
                    app.playback = request
                    openWindow(id: "Player", value: request)
                }
            }
        }
    }
}
