import SwiftUI
import Foundation

// OWNER: ui-browse — Countries gallery: image tiles with Persian titles, tap → CountryDetailView.

@MainActor
final class CountriesModel: ObservableObject {
    @Published private(set) var countries: [Country] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var started = false

    func loadIfNeeded() {
        guard !started else { return }
        started = true
        reload()
    }

    func reload() {
        isLoading = true
        error = nil
        Task { [weak self] in
            do {
                let countries = try await APIClient.shared.countries()
                guard let self else { return }
                self.countries = countries
                self.isLoading = false
            } catch {
                guard let self else { return }
                self.countries = []
                self.isLoading = false
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

struct CountriesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = CountriesModel()

    private var visibleCountries: [Country] {
        settings.hideRegionalOrigins
            ? model.countries.filter { !OriginFilter.hides($0) }
            : model.countries
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            BrowseHeader(title: "کشورها", subtitle: subtitle)

            content
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .task { model.loadIfNeeded() }
        .onChange(of: app.refreshTick) { _, _ in
            model.reload()
        }
    }

    private var subtitle: String {
        if !visibleCountries.isEmpty {
            return browseSubtitle(count: visibleCountries.count, noun: "کشور",
                                  trailing: "بر اساس کشور سازنده")
        }
        if model.error != nil { return "اتصال به سرور برقرار نشد" }
        if !model.countries.isEmpty, settings.contentHiding.isActive { return "همهٔ کشورها پنهان شده‌اند" }
        return "در حال دریافت کشورها…"
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error, model.countries.isEmpty {
            ErrorStateView(message: error) {
                model.reload()
            }
            .frame(maxHeight: .infinity)
        } else if model.countries.isEmpty, model.isLoading {
            ScrollView(showsIndicators: false) {
                BrowseCountrySkeletonGrid()
                    .padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)
        } else if model.countries.isEmpty {
            EmptyStateView(icon: "globe.europe.africa",
                           title: "کشوری برای نمایش نیست",
                           message: "فهرست کشورها از سرور دریافت نشد؛ دوباره تلاش کنید.")
                .frame(maxHeight: .infinity)
        } else if visibleCountries.isEmpty {
            EmptyStateView(icon: "eye.slash",
                           title: "کشوری برای نمایش نیست",
                           message: "همهٔ کشورها در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.")
                .frame(maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: BrowseMetrics.countryColumns,
                          alignment: .trailing,
                          spacing: BrowseMetrics.gridSpacing) {
                    ForEach(visibleCountries) { country in
                        BrowseCountryCard(country: country) {
                            app.openCountry(country)
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Country tile

struct BrowseCountryCard: View {
    let country: Country
    var action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.card)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(
                    CachedAsyncImage(url: country.imageURL, placeholderIcon: "globe")
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                )
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.66)],
                                   startPoint: .center, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                )
                .overlay(alignment: .bottomLeading) {
                    Text(country.title)
                        .font(.ccloud(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(hover.isHovering ? Theme.accent.opacity(0.9) : Theme.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(hover.isHovering ? 0.5 : 0.22),
                        radius: hover.isHovering ? 14 : 6,
                        y: hover.isHovering ? 7 : 3)
                .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .scaleEffect(hover.isHovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.16), value: hover.isHovering)
    }
}

// MARK: - Loading skeleton for the country grid

struct BrowseCountrySkeletonGrid: View {
    var count: Int = 10

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.6) / 1.6
            let pulse = 0.25 + ((sin(phase * 2 * .pi) + 1) / 2) * 0.5
            LazyVGrid(columns: BrowseMetrics.countryColumns,
                      alignment: .trailing,
                      spacing: BrowseMetrics.gridSpacing) {
                ForEach(Array(0..<count), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .fill(Theme.card)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
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
