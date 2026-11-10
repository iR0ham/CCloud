import SwiftUI
import Foundation

// OWNER: ui-browse — shared pieces for the browse screens (Movies, Series, Search, Favorites,
// Countries). Macro-free local state only: @StateObject / @ObservedObject / @EnvironmentObject.

// MARK: - Metrics

enum BrowseMetrics {
    /// Responsive poster grid: ~5 columns at 1320 pt window, ~4 at the 1120 pt minimum width.
    static let cardMin: CGFloat = 150
    static let cardMax: CGFloat = 208
    static let gridSpacing: CGFloat = 18
    static let rowSpacing: CGFloat = 24

    static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMin, maximum: cardMax),
                  spacing: gridSpacing,
                  alignment: .top)]
    }

    /// Country tiles are wider than posters (16:9 imagery).
    static var countryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 188, maximum: 268),
                  spacing: gridSpacing,
                  alignment: .top)]
    }

    /// Category tiles hold an icon + a long Persian genre title, so they get more width.
    static var categoryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 250, maximum: 340),
                  spacing: gridSpacing,
                  alignment: .top)]
    }
}

// MARK: - Persian formatting helpers

/// Latin → Persian digits, without grouping (counts are small enough that grouping is noise).
func browseNumber(_ value: Int) -> String {
    PersianNumber.string(value)
}

/// Subtle summary line such as «۳۰ فیلم • جدیدترین».
func browseSubtitle(count: Int, noun: String, trailing: String? = nil) -> String {
    var parts: [String] = []
    if count > 0 { parts.append("\(browseNumber(count)) \(noun)") }
    if let trailing, !trailing.isEmpty { parts.append(trailing) }
    return parts.joined(separator: " • ")
}

// MARK: - Header with optional sort menu

struct BrowseHeader: View {
    let title: String
    let subtitle: String
    var sort: SortOption? = nil
    var onSort: ((SortOption) -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            SectionHeader(title: title, subtitle: subtitle)
            if let sort, let onSort {
                BrowseSortMenu(sort: sort, onSelect: onSort)
                    .padding(.bottom, 1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sort menu (native macOS menu, styled as a chip)

struct BrowseSortMenu: View {
    let sort: SortOption
    var onSelect: (SortOption) -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    if option == sort {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sort.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(sort.title)
                    .font(.ccloud(12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .opacity(0.65)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(hover.isHovering ? Theme.cardHover : Theme.card))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hover.isHovering = $0 }
        .help("مرتب‌سازی")
    }
}

// MARK: - Genre chip strip

struct BrowseGenreChipRow: View {
    let genres: [Genre]
    let selectedId: Int
    var isLoading: Bool = false
    var errorText: String? = nil
    var onSelect: (Int) -> Void
    var onRetry: (() -> Void)? = nil

    private static let allChipId = "ccloud.browse.genre.all"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "همه", isSelected: selectedId == 0) {
                        onSelect(0)
                    }
                    .id(Self.allChipId)
                    ForEach(genres) { genre in
                        FilterChip(title: genre.title, isSelected: selectedId == genre.id) {
                            onSelect(genre.id)
                        }
                        .id("ccloud.browse.genre.\(genre.id)")
                    }
                    if genres.isEmpty, isLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(Theme.textSecondary)
                            Text("در حال دریافت ژانرها…")
                                .font(.ccloud(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 8)
                    } else if genres.isEmpty, errorText != nil, let onRetry {
                        Button(action: onRetry) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                                Text("ژانرها بارگذاری نشد؛ تلاش دوباره")
                                    .font(.ccloud(11))
                            }
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.card))
                            .overlay(Capsule().strokeBorder(Theme.red.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical, 1)
            }
            .onAppear { scrollToStart(proxy) }
            .onChange(of: genres.count) { _, _ in scrollToStart(proxy) }
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// On macOS a horizontal ScrollView starts at the wrong (trailing) end in RTL, so every time
    /// the strip appears or the genre list arrives we pin it to the first chip at the RTL leading
    /// (physical right) edge. A couple of attempts cover the late genre load.
    private func scrollToStart(_ proxy: ScrollViewProxy) {
        for delay in [0.02, 0.18, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(Self.allChipId, anchor: UnitPoint(x: 1, y: 0.5))
            }
        }
    }
}

// MARK: - Poster card wired to navigation (+ context menu)

struct BrowsePosterCard: View {
    let title: String
    let posterURL: URL?
    var year: Int = 0
    var imdb: Double = 0
    var badge: String? = nil
    var sources: [MediaSource] = []
    var playSubtitle: String? = nil
    var media: PlaybackInfo? = nil
    let onOpen: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PosterCard(title: title,
                   posterURL: posterURL,
                   year: year,
                   imdb: imdb,
                   badge: badge,
                   action: onOpen)
            .contextMenu {
                Button("مشاهده جزئیات") { onOpen() }
                if let source = sources.preferred(for: "auto") {
                    Divider()
                    Button("پخش «\(title)»") {
                        let request = PlaybackRequest(
                            title: title,
                            subtitle: playSubtitle,
                            posterURL: posterURL?.absoluteString,
                            sources: sources,
                            preferredSourceID: source.id,
                            media: media
                        )
                        app.playback = request
                        openWindow(id: "Player", value: request)
                    }
                }
            }
    }
}

// MARK: - Loading skeleton (matches the poster grid so there is no layout jump)

struct BrowseSkeletonGrid: View {
    var count: Int = 12

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.6) / 1.6
            LazyVGrid(columns: BrowseMetrics.columns, alignment: .trailing, spacing: BrowseMetrics.rowSpacing) {
                ForEach(Array(0..<count), id: \.self) { _ in
                    BrowsePosterSkeletonCard(phase: phase)
                }
            }
        }
    }
}

struct BrowsePosterSkeletonCard: View {
    let phase: Double

    private var pulse: Double {
        // 0.25 … 0.75, smooth triangle-ish pulse.
        let value = (sin(phase * 2 * .pi) + 1) / 2
        return 0.25 + value * 0.5
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.card)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .fill(Theme.cardHover.opacity(pulse))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )

            VStack(alignment: .trailing, spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.cardHover.opacity(pulse))
                    .frame(height: 11)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.cardHover.opacity(pulse * 0.8))
                    .frame(width: 54, height: 9)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Infinite-scroll footer (keeps a stable height so content does not jump)

struct BrowseFeedFooter: View {
    let isLoadingMore: Bool
    let hasMore: Bool
    let itemCount: Int
    var isFilterActive: Bool = false
    var isFilterScanning: Bool = false
    var onScanMore: (() -> Void)? = nil

    var body: some View {
        Group {
            if isLoadingMore || isFilterScanning {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text(isFilterActive ? "در حال بررسی عناوین بیشتر…" : "در حال بارگذاری عنوان‌های بیشتر…")
                        .font(.ccloud(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if isFilterActive, hasMore, let onScanMore {
                Button(action: onScanMore) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("بررسی عناوین بیشتر")
                            .font(.ccloud(11.5, weight: .medium))
                    }
                    .foregroundStyle(Theme.accentBright)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("صفحات بعدی را برای یافتن نتایج بیشتر بررسی کن")
            } else if !hasMore && itemCount > 0 {
                Text(isFilterActive
                     ? "پایان عناوین بررسی‌شده • \(browseNumber(itemCount)) نتیجه"
                     : "پایان فهرست • \(browseNumber(itemCount)) عنوان")
                    .font(.ccloud(11))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
    }
}

// MARK: - Grid of poster cards (used by Search)

struct BrowseMovieGrid: View {
    let movies: [Movie]
    var showsBadge: Bool = false
    let onOpen: (Movie) -> Void

    var body: some View {
        LazyVGrid(columns: BrowseMetrics.columns, alignment: .trailing, spacing: BrowseMetrics.rowSpacing) {
            ForEach(movies) { movie in
                BrowsePosterCard(title: movie.title,
                                posterURL: movie.posterURL,
                                year: movie.year,
                                imdb: movie.imdb,
                                badge: showsBadge ? (movie.isSeries ? "سریال" : "فیلم") : nil,
                                sources: movie.sources,
                                playSubtitle: movie.genreText,
                                media: movie.isSeries ? nil : PlaybackInfo(kind: .movie, movie: movie),
                                onOpen: { onOpen(movie) })
            }
        }
    }
}
