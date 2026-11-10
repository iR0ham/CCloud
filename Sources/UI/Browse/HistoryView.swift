import SwiftUI

// OWNER: ui-browse — Recently watched: mixed movie/series poster grid with progress,
// kind filters, hover removal, context menu and a clear-all confirmation.

@MainActor
final class HistoryUIModel: ObservableObject {
    @Published var showClearConfirm = false
    @Published var filter: HistoryFilter = .all
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, movies, series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "همه"
        case .movies: return "فیلم‌ها"
        case .series: return "سریال‌ها"
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: WatchHistoryStore
    @StateObject private var ui = HistoryUIModel()

    private var visibleEntries: [HistoryEntry] {
        let hiding = settings.contentHiding
        guard hiding.isActive else { return history.entries }
        return history.entries.filter { !hiding.isHidden($0) }
    }

    private var filteredEntries: [HistoryEntry] {
        switch ui.filter {
        case .all: return visibleEntries
        case .movies: return visibleEntries.filter { $0.kind == .movie }
        case .series: return visibleEntries.filter { $0.kind == .series }
        }
    }

    private var allHidden: Bool {
        settings.contentHiding.isActive && visibleEntries.isEmpty && !history.entries.isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            header

            if history.entries.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath",
                               title: "هنوز چیزی تماشا نکرده‌اید",
                               message: "هر فیلم یا قسمتی که پخش کنید اینجا با میزان پیشرفت ذخیره می‌شود.")
                    .frame(maxHeight: .infinity)
            } else {
                filterRow
                    .padding(.top, 20)
                grid
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .alert("پاک کردن تاریخچه",
               isPresented: Binding(get: { ui.showClearConfirm }, set: { ui.showClearConfirm = $0 })) {
            Button("پاک کردن همه", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { history.clear() }
                app.showToast("تاریخچهٔ تماشا پاک شد")
            }
            Button("انصراف", role: .cancel) { }
        } message: {
            Text("همهٔ عنوان‌ها و نشانه‌های «دیده شده» حذف می‌شوند. این عمل قابل بازگشت نیست.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 14) {
            SectionHeader(title: "اخیراً دیده‌شده", subtitle: subtitle)

            if !history.entries.isEmpty {
                Button {
                    ui.showClearConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                        Text("پاک کردن تاریخچه")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .help("حذف همهٔ عنوان‌های تماشاشده")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        guard !history.entries.isEmpty else { return "تاریخچهٔ پخش شما خالی است" }
        let visible = visibleEntries.count
        if visible != history.entries.count {
            return "\(browseNumber(visible)) از \(browseNumber(history.entries.count)) عنوان تماشا شده"
        }
        return browseSubtitle(count: visible, noun: "عنوان تماشا شده")
    }

    // MARK: Filters + grid

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(HistoryFilter.allCases) { filter in
                FilterChip(title: filter.title, isSelected: ui.filter == filter) {
                    withAnimation(.easeInOut(duration: 0.18)) { ui.filter = filter }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            if filteredEntries.isEmpty {
                if allHidden {
                    EmptyStateView(icon: "eye.slash",
                                   title: "همهٔ عنوان‌ها پنهان شده‌اند",
                                   message: "همهٔ عنوان‌های تماشاشده در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.")
                        .frame(height: 220)
                } else {
                    EmptyStateView(icon: "line.3.horizontal.decrease.circle",
                                   title: "موردی در این دسته نیست",
                                   message: "فیلتر دیگری را امتحان کنید.")
                        .frame(height: 220)
                }
            } else {
                LazyVGrid(columns: BrowseMetrics.columns,
                          alignment: .trailing,
                          spacing: BrowseMetrics.rowSpacing) {
                    ForEach(filteredEntries) { entry in
                        HistoryEntryCard(entry: entry,
                                         onOpen: { open(entry) },
                                         onRemove: { remove(entry) })
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func open(_ entry: HistoryEntry) {
        if let movie = entry.movie {
            app.openMovie(movie)
        } else if let series = entry.series {
            app.openSeries(series)
        }
    }

    private func remove(_ entry: HistoryEntry) {
        withAnimation(.easeInOut(duration: 0.2)) {
            history.remove(id: entry.mediaID, kind: entry.kind)
        }
        app.showToast("«\(entry.title)» از تاریخچه حذف شد")
    }
}

// MARK: - History poster with watch progress + hover remove

struct HistoryEntryCard: View {
    let entry: HistoryEntry
    let onOpen: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var history: WatchHistoryStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var hover = HoverState()

    private var progress: Double? {
        if entry.kind == .movie {
            return entry.progress > 0.01 ? entry.progress : nil
        }
        guard let last = entry.lastEpisode, last.progress > 0.01 else { return nil }
        return last.progress
    }

    private var progressText: String {
        let percent = Int((min(max(progress ?? 0, 0), 1) * 100).rounded())
        return "٪\(browseNumber(percent)) تماشا شده"
    }

    private var subtitle: String {
        switch entry.kind {
        case .movie:
            if let progress { return progress < 0.995 ? progressText : "تماشا شده" }
            return "فیلم"
        case .series:
            guard let last = entry.lastEpisode else { return "سریال" }
            var parts = [last.label].filter { !$0.isEmpty }
            if parts.isEmpty { parts.append(last.seasonTitle) }
            if let progress {
                parts.append(progress < 0.995 ? progressText : "تماشا شده")
            }
            if parts.isEmpty { parts.append("سریال") }
            return parts.joined(separator: " • ")
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PosterCard(title: entry.title,
                       posterURL: entry.posterURL,
                       year: entry.year,
                       imdb: entry.imdb,
                       badge: entry.kind == .series ? "سریال" : nil,
                       subtitle: subtitle,
                       progress: progress,
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
                .help("حذف از تاریخچه")
                .padding(7)
                .transition(.opacity)
            }
        }
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hover.isHovering)
        .contextMenu {
            Button("مشاهده جزئیات", action: onOpen)
            if let movie = entry.movie, let source = movie.sources.preferred(for: "auto") {
                Divider()
                Button(playTitle(movie: movie)) { play(movie: movie, source: source) }
            }
            Divider()
            Button("حذف از تاریخچه", action: onRemove)
        }
    }

    private func playTitle(movie: Movie) -> String {
        history.resumePosition(movieID: movie.id) != nil
            ? "ادامه «\(entry.title)»"
            : "پخش «\(entry.title)»"
    }

    private func play(movie: Movie, source: MediaSource) {
        let request = PlaybackRequest(title: movie.title,
                                      subtitle: movie.genreText,
                                      posterURL: movie.image.isEmpty ? nil : movie.image,
                                      sources: movie.sources,
                                      preferredSourceID: source.id,
                                      media: PlaybackInfo(kind: .movie, movie: movie),
                                      startAt: history.resumePosition(movieID: movie.id) ?? 0)
        app.playback = request
        openWindow(id: "Player", value: request)
    }
}
