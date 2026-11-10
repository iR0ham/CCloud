import SwiftUI
import Foundation

// OWNER: ui-browse — Categories gallery: every genre as a coloured tile → category feed.

enum CategoryStyle {
    static func icon(for title: String) -> String {
        let name = title.lowercased()
        if name.contains("اکشن") || name.contains("action") { return "flame" }
        if name.contains("ماجرا") || name.contains("adventure") { return "map" }
        if name.contains("انیمیشن") || name.contains("animation") { return "paintpalette" }
        if name.contains("کمدی") || name.contains("comedy") { return "face.smiling" }
        if name.contains("جنایی") || name.contains("crime") { return "eye" }
        if name.contains("مستند") || name.contains("documentary") { return "doc.text" }
        if name.contains("درام") || name.contains("drama") { return "theatermasks" }
        if name.contains("خانواده") || name.contains("family") { return "person.2" }
        if name.contains("فانتزی") || name.contains("fantasy") { return "wand.and.stars" }
        if name.contains("تاریخ") || name.contains("history") { return "building.columns" }
        if name.contains("ترسناک") || name.contains("horror") { return "moon.stars" }
        if name.contains("موزیک") || name.contains("music") { return "music.note" }
        if name.contains("معمایی") || name.contains("mystery") { return "questionmark.bubble" }
        if name.contains("عاشقانه") || name.contains("romance") { return "heart" }
        if name.contains("علمی") || name.contains("science") { return "atom" }
        if name.contains("ورزش") || name.contains("sport") { return "figure.run" }
        if name.contains("هیجان") || name.contains("thriller") { return "bolt" }
        if name.contains("جنگ") || name.contains("war") { return "shield" }
        if name.contains("وسترن") || name.contains("western") { return "sun.max" }
        if name.contains("بیوگرافی") || name.contains("biography") { return "person.text.rectangle" }
        if name.contains("کودک") || name.contains("kids") { return "teddybear" }
        if name.contains("مذهبی") || name.contains("religious") { return "book" }
        return "film"
    }

    static func gradient(for id: Int) -> [Color] {
        let palettes: [[UInt32]] = [
            [0x3D5AFE, 0x1B2E8F],
            [0x8E5BFE, 0x3A1B8F],
            [0xE8506A, 0x7A1B2C],
            [0x24B47E, 0x0F5B40],
            [0xD9A21B, 0x6E4E0B],
            [0x20A4D8, 0x0D5472],
            [0xC85BD8, 0x5E1B6A],
            [0x5B78FF, 0x25348F]
        ]
        let pair = palettes[abs(id) % palettes.count]
        return [Color(hex: pair[0]), Color(hex: pair[1])]
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore

    private var visibleGenres: [Genre] {
        settings.hideRegionalOrigins
            ? app.genres.filter { !OriginFilter.hidesGenre($0.title) }
            : app.genres
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            BrowseHeader(title: "دسته‌بندی‌ها", subtitle: subtitle)

            content
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .task { await app.loadGenresIfNeeded() }
        .onChange(of: app.refreshTick) { _, _ in
            Task { await app.loadGenres() }
        }
    }

    private var subtitle: String {
        if !visibleGenres.isEmpty {
            return browseSubtitle(count: visibleGenres.count, noun: "دسته", trailing: "فیلم و سریال")
        }
        if !app.genres.isEmpty, settings.contentHiding.isActive { return "همهٔ دسته‌ها پنهان شده‌اند" }
        if app.genresError != nil { return "اتصال به سرور برقرار نشد" }
        return "در حال دریافت دسته‌بندی‌ها…"
    }

    @ViewBuilder
    private var content: some View {
        if let error = app.genresError, app.genres.isEmpty {
            ErrorStateView(message: error) {
                Task { await app.loadGenres() }
            }
            .frame(maxHeight: .infinity)
        } else if app.genres.isEmpty {
            ScrollView(showsIndicators: false) {
                CategorySkeletonGrid()
                    .padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)
        } else if visibleGenres.isEmpty {
            EmptyStateView(icon: "eye.slash",
                           title: "دستهٔ قابل نمایشی نیست",
                           message: "همهٔ دسته‌ها در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.")
                .frame(maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: BrowseMetrics.categoryColumns,
                          alignment: .trailing,
                          spacing: BrowseMetrics.gridSpacing) {
                    ForEach(visibleGenres) { genre in
                        CategoryCard(genre: genre) {
                            app.openCategory(genre)
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Category tile

struct CategoryCard: View {
    let genre: Genre
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: CategoryStyle.icon(for: genre.title))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(genre.title)
                        .font(.ccloud(15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("فیلم‌ها و سریال‌ها")
                        .font(.ccloud(10.5))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(hover.isHovering ? 0.9 : 0.55))
            }
            .padding(.horizontal, 14)
            .frame(height: 82)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(LinearGradient(colors: CategoryStyle.gradient(for: genre.id),
                                         startPoint: .topTrailing,
                                         endPoint: .bottomLeading))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(hover.isHovering ? 0.38 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(hover.isHovering ? 0.42 : 0.24),
                    radius: hover.isHovering ? 13 : 6,
                    y: hover.isHovering ? 6 : 3)
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .scaleEffect(hover.isHovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.16), value: hover.isHovering)
    }
}

// MARK: - Skeleton

struct CategorySkeletonGrid: View {
    var count: Int = 12

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.6) / 1.6
            let pulse = 0.25 + ((sin(phase * 2 * .pi) + 1) / 2) * 0.5
            LazyVGrid(columns: BrowseMetrics.categoryColumns,
                      alignment: .trailing,
                      spacing: BrowseMetrics.gridSpacing) {
                ForEach(0..<count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .fill(Theme.card)
                        .frame(height: 82)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                .fill(Theme.cardHover.opacity(pulse))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                .strokeBorder(Theme.stroke, lineWidth: 1)
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
