import SwiftUI
import AppKit

// MARK: - Shared building blocks for the detail pages (owner: ui-detail)
//
// Everything here is deliberately @State-free (see PROJECT.md §5.5). Local interaction
// state lives in small @MainActor ObservableObject models that views own via @StateObject.

// MARK: Meta row

struct DetailMetaItem {
    var icon: String? = nil
    let text: String
    var tint: Color = Theme.textSecondary
}

/// "1992 · ★ 7.7 · 130 min · امریکا · +16" style row used in the hero.
struct DetailMetaRow: View {
    let items: [DetailMetaItem]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                if pair.offset > 0 {
                    Circle()
                        .fill(Theme.textTertiary)
                        .frame(width: 3, height: 3)
                }
                HStack(spacing: 4) {
                    if let icon = pair.element.icon {
                        Image(systemName: icon)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(pair.element.tint)
                    }
                    Text(pair.element.text)
                        .font(.ccloud(12, weight: .medium))
                        .foregroundStyle(pair.element.tint)
                        .lineLimit(1)
                }
            }
        }
    }
}

enum DetailMetaFactory {
    /// Builds the standard meta row (year · IMDb · duration · country · age rating).
    static func items(year: Int, imdb: Double, duration: String?, country: String, age: String?) -> [DetailMetaItem] {
        var items: [DetailMetaItem] = []
        if year > 0 { items.append(DetailMetaItem(icon: "calendar", text: String(year))) }
        if imdb > 0 {
            items.append(DetailMetaItem(icon: "star.fill", text: String(format: "%.1f", imdb), tint: Theme.gold))
        }
        if let duration, !duration.isEmpty, duration != "null" {
            items.append(DetailMetaItem(icon: "clock", text: duration))
        }
        if !country.isEmpty {
            items.append(DetailMetaItem(icon: "globe", text: country))
        }
        if let age {
            items.append(DetailMetaItem(text: "رده سنی \(age)", tint: Theme.textTertiary))
        }
        return items
    }

    /// The backend embeds the age rating in the long description ("رده سنی:  16").
    static func ageRating(from description: String) -> String? {
        guard !description.isEmpty else { return nil }
        let pattern = #"رده\s*سنی\s*:?\s*\+?\s*([0-9۰-۹]{1,2})"#
        guard let range = description.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(description[range])
        let digits = match.replacingOccurrences(of: #"[^0-9۰-۹]"#, with: "", options: .regularExpression)
        guard !digits.isEmpty else { return nil }
        return digits + "+"
    }
}

// MARK: Genre chips

struct GenreChipRow: View {
    let genres: [Genre]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres) { genre in
                    Text(genre.title)
                        .font(.ccloud(11.5, weight: .medium))
                        .foregroundStyle(Theme.accentSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.32), lineWidth: 1))
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 30)
    }
}

// MARK: Hero

/// Full-bleed rounded cover backdrop with poster thumb, title, meta row and genre chips.
struct DetailHero: View {
    let title: String
    let coverURL: URL?
    let posterURL: URL?
    let meta: [DetailMetaItem]
    let genres: [Genre]
    let isFavorite: Bool
    let onBack: () -> Void
    let onFavorite: () -> Void

    @StateObject private var backHover = HoverState()
    @StateObject private var heartHover = HoverState()

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop
            scrim
            content
            topButtons
        }
        .frame(height: 336)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var backdrop: some View {
        CachedAsyncImage(url: coverURL ?? posterURL, placeholderIcon: "photo.on.rectangle")
            .frame(maxWidth: .infinity)
            .frame(height: 336)
            .clipped()
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.08), location: 0.0),
                .init(color: Color.black.opacity(0.30), location: 0.45),
                .init(color: Theme.bg.opacity(0.94), location: 0.94),
                .init(color: Theme.bg, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: 22) {
            poster
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.ccloud(30, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                if !meta.isEmpty {
                    DetailMetaRow(items: meta)
                }
                if !genres.isEmpty {
                    GenreChipRow(genres: genres)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var poster: some View {
        CachedAsyncImage(url: posterURL)
            .frame(width: 132, height: 198)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 14, y: 7)
    }

    private var topButtons: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(backHover.isHovering ? 0.72 : 0.48)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .onHover { backHover.isHovering = $0 }
            .help("بازگشت")

            Spacer(minLength: 0)

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isFavorite ? Theme.red : .white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(heartHover.isHovering ? 0.72 : 0.48)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .scaleEffect(heartHover.isHovering ? 1.06 : 1)
            }
            .buttonStyle(.plain)
            .onHover { heartHover.isHovering = $0 }
            .help(isFavorite ? "حذف از علاقه‌مندی‌ها" : "افزودن به علاقه‌مندی‌ها")
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: Section card

struct DetailSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentSoft)
                }
                Text(title)
                    .font(.ccloud(15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 6)
                if let subtitle {
                    Text(subtitle)
                        .font(.ccloud(11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: Theme.corner, fill: Theme.card)
    }
}

// MARK: Story

/// The story block on detail pages. The backend `description` is a full metadata sheet, so only the
/// plot is shown — always in full, as a readable paragraph with an accent rule.
struct StoryText: View {
    let text: String

    private let readingWidth: CGFloat = 760

    private var story: String? {
        PlotSummary.plot(from: text)
    }

    var body: some View {
        Group {
            if let story {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accentBright, Theme.accent.opacity(0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)

                    Text(story)
                        .font(.ccloud(13.5))
                        .foregroundStyle(Theme.text.opacity(0.9))
                        .lineSpacing(7)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: readingWidth, alignment: .leading)
    }

    private var emptyState: some View {
        HStack(spacing: 9) {
            Image(systemName: "text.quote")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("خلاصه‌ای برای این عنوان ثبت نشده است.")
                .font(.ccloud(12))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

// MARK: Media source row

/// One playable quality/source: quality label, kind badge, play + copy + download actions.
struct MediaSourceRow: View {
    let source: MediaSource
    var isSelected: Bool = false
    var playTitle: String = "پخش"
    let onPlay: () -> Void
    var onCopy: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil

    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 12) {
            qualityBlock

            if isSelected {
                Text("پیشنهادی")
                    .font(.ccloud(9.5, weight: .bold))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.green.opacity(0.14)))
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                if let onCopy {
                    IconActionButton(systemName: "doc.on.doc", help: "کپی لینک", tint: Theme.textSecondary, action: onCopy)
                }
                if let onDownload {
                    IconActionButton(systemName: "arrow.down.circle", help: "دانلود", tint: Theme.textSecondary, action: onDownload)
                }
                Button(action: onPlay) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        Text(playTitle)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hover.isHovering ? Theme.cardHover : Theme.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.55) : Theme.stroke, lineWidth: 1)
        )
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hover.isHovering)
    }

    private var qualityBlock: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.qualityLabel)
                    .font(.ccloud(13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(source.kindLabel)
                    .font(.ccloud(9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(0.6)
            }
            if let resolution = source.resolutionLabel {
                Text(resolution)
                    .font(.ccloud(10, weight: .bold))
                    .foregroundStyle(Theme.accentBright)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
            }
        }
    }
}

// MARK: - Similar titles rail model (genre-based)

@MainActor
final class SimilarTitlesModel: ObservableObject {
    @Published private(set) var items: [Movie] = []
    @Published private(set) var isLoading = false

    private var loadedKey: String?

    func load(genre: Genre?, isSeries: Bool, excludingID: Int, hiding: ContentHiding) async {
        guard let genre else { return }
        let key = "\(genre.id)|\(isSeries)|\(excludingID)|\(hiding.isActive)"
        guard loadedKey != key else { return }
        loadedKey = key
        isLoading = true
        defer { isLoading = false }

        var collected: [Movie] = []
        var seen = Set<String>()
        for page in 0..<2 {
            do {
                let batch: [Movie]
                if isSeries {
                    batch = try await APIClient.shared.series(page: page, genreId: genre.id)
                        .map { Movie(from: $0) }
                } else {
                    batch = try await APIClient.shared.movies(page: page, genreId: genre.id)
                }
                for movie in batch where !hiding.isHidden(movie) {
                    let id = "\(movie.type.lowercased()):\(movie.id)"
                    guard !seen.contains(id) else { continue }
                    guard !(movie.id == excludingID && movie.isSeries == isSeries) else { continue }
                    seen.insert(id)
                    collected.append(movie)
                }
            } catch {
                break
            }
            if collected.count >= 14 { break }
        }
        items = Array(collected.prefix(14))
    }
}

// MARK: - QA helpers (only active with a debug CLI flag, e.g. `--debug-scroll-bottom`)

enum DetailQA {
    /// Scrolls long detail pages to their bottom so the snapshot hook can capture the
    /// source list / episode list that otherwise sits below the fold in QA renders.
    static var scrollToBottom: Bool {
        CommandLine.arguments.contains("--debug-scroll-bottom")
    }
}

// MARK: Toast helper (local, non-AppState)

@MainActor
final class LocalToastCenter: ObservableObject {
    @Published var message: String?
    private var task: Task<Void, Never>?

    func show(_ message: String) {
        self.message = message
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) { self?.message = nil }
            }
        }
    }
}

struct LocalToastOverlay: View {
    let message: String?

    var body: some View {
        Group {
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    Text(message).font(.ccloud(12, weight: .medium)).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}
