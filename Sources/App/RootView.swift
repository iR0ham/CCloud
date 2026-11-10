import SwiftUI
import AppKit

// MARK: - Root layout: sidebar (right, RTL) + content router + splash/toast/sheets

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarView()
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 1)
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if app.showSplash {
                SplashView()
                    .environmentObject(app)
                    .transition(.opacity)
                    .zIndex(20)
            }

            if let toast = app.toast {
                VStack {
                    Spacer()
                    ToastView(message: toast)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(30)
                .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        // Global default typeface: every Text that does not set its own font inherits Vazirmatn.
        .font(.ccloud(13))
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $app.showAbout) {
            AboutView()
                .environmentObject(app)
                .environmentObject(settings)
                .environmentObject(favorites)
                .font(.ccloud(13))
                .environment(\.layoutDirection, .rightToLeft)
                .frame(minWidth: 640, minHeight: 540)
        }
        .onAppear {
            settings.applyAppearance()
            // Views far from the scene cannot reach `openWindow`, so `AppState.play` asks for the
            // player window through this one.
            app.playerWindowOpener = { request in
                openWindow(id: "Player", value: request)
            }
            Task {
                await app.loadGenresIfNeeded()
                await app.runDemoIfRequested()
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.45)) { app.showSplash = false }
                }
            }
        }
        .animation(.easeInOut(duration: 0.24), value: app.toast)
        .animation(.easeInOut(duration: 0.4), value: app.showSplash)
        .animation(.easeInOut(duration: 0.22), value: app.path)
    }

    @ViewBuilder
    private var contentArea: some View {
        Group {
            if let route = app.path.last {
                switch route {
                case .movie(let movie):
                    MovieDetailView(movie: movie)
                case .series(let series):
                    SeriesDetailView(series: series)
                case .country(let country):
                    CountryDetailView(country: country)
                case .category(let genre):
                    CategoryDetailView(genre: genre)
                }
            } else {
                switch app.tab {
                case .home:
                    HomeView()
                case .movies:
                    MoviesView()
                case .series:
                    SeriesView()
                case .categories:
                    CategoriesView()
                case .live:
                    LiveTVView()
                case .search:
                    SearchView()
                case .favorites:
                    FavoritesView()
                case .history:
                    HistoryView()
                case .countries:
                    CountriesView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .padding(.horizontal, isHome ? 0 : 32)
        .padding(.top, isHome ? 0 : 34)
        .padding(.bottom, isHome ? 0 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Home draws its own edge-to-edge hero, so the shared content insets are skipped there.
    private var isHome: Bool {
        app.path.isEmpty && app.tab == .home
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            brand
                .padding(.top, 38)
                .padding(.horizontal, 20)

            navItems
                .padding(.top, 26)
                .padding(.horizontal, 12)

            Spacer(minLength: 12)

            VStack(spacing: 2) {
                Button {
                    app.refresh()
                } label: {
                    SidebarRowLabel(icon: "arrow.clockwise", title: "تازه‌سازی", isSelected: false)
                }
                .buttonStyle(.plain)
                .help("تازه‌سازی همهٔ داده‌ها (⌘R)")

                navRow(tab: .settings)
                Button {
                    app.showAbout = true
                } label: {
                    SidebarRowLabel(icon: "info.circle", title: "درباره", isSelected: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)

            backendStatus
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }

    private var brand: some View {
        HStack(spacing: 11) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text("CCloud")
                    .font(.ccloud(20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("نسخه مک")
                    .font(.ccloud(10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            BrandLogo(size: 38)
        }
    }

    private var navItems: some View {
        VStack(spacing: 3) {
            ForEach(AppState.Tab.allCases.filter { $0 != .settings }, id: \.self) { tab in
                navRow(tab: tab)
            }
        }
    }

    private func navRow(tab: AppState.Tab) -> some View {
        let selected = app.tab == tab && app.path.isEmpty
        return Button {
            app.select(tab: tab)
        } label: {
            SidebarRowLabel(icon: tab.icon, title: tab.title, isSelected: selected)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut(for: tab), modifiers: .command)
    }

    private func shortcut(for tab: AppState.Tab) -> KeyEquivalent {
        switch tab {
        case .home: return "0"
        case .movies: return "1"
        case .series: return "2"
        case .live: return "3"
        case .search: return "4"
        case .favorites: return "5"
        case .history: return "8"
        case .countries: return "6"
        case .categories: return "7"
        case .settings: return ","
        }
    }

    private var backendStatus: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(app.isOffline ? Theme.gold : (app.genresError == nil ? Theme.green : Theme.red))
                .frame(width: 6, height: 6)
            Text(app.isOffline ? "آفلاین • \(app.backendHost)" : app.backendHost)
                .font(.ccloud(9.5))
                .foregroundStyle(app.isOffline ? Theme.gold : Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .help(app.isOffline ? "اتصال به سرور برقرار نشد؛ محتوای ذخیره‌شده نمایش داده می‌شود" : "سرور فعال")
    }
}

struct SidebarRowLabel: View {
    let icon: String
    let title: String
    let isSelected: Bool

    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Text(title)
                .font(.ccloud(13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                .frame(width: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Theme.accent : (hover.isHovering ? Theme.cardHover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hover.isHovering = $0 }
    }
}

struct BrandLogo: View {
    var size: CGFloat = 38
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = colorScheme == .dark ? Self.darkLogoImage : Self.logoImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "cloud.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.22)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
    }

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }

    private static let logoImage: NSImage? = load("logo.png")
    private static let darkLogoImage: NSImage? = load("logo-dark.png") ?? load("logo.png")
}
