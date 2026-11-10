import SwiftUI
import Foundation

// OWNER: ui-browse — Live search: 350 ms debounce, recent-query chips (UserDefaults),
// movie/series result grid with type badges, empty/loading/error states.

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [Movie] = []
    @Published private(set) var filters = MediaFilters()
    @Published private(set) var hiding = ContentHiding()
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasSearched = false
    @Published private(set) var lastQuery = ""
    @Published private(set) var recents: [String] = []

    var isPostFiltering: Bool { filters.isActive || hiding.isActive }

    var visibleResults: [Movie] {
        guard isPostFiltering else { return results }
        return results.filter {
            !hiding.isHidden($0) && (!filters.isActive || filters.matches($0))
        }
    }

    private var debounceTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var generation = 0

    private let recentsKey = "ccloud.recentSearchQueries"
    private let maxRecents = 8

    init() {
        recents = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        filters = MediaFilters.qaSeed()
    }

    // MARK: Query input

    /// Called from the TextField binding: schedules a debounced search.
    func updateQuery(_ text: String) {
        query = text
        debounceTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelSearch()
            clearResults()
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.startSearch(trimmed, remember: false)
        }
    }

    /// Enter (or the search glyph) — immediate search, remembered in recents.
    func submit() {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        startSearch(trimmed, remember: true)
    }

    /// Clicking a recent chip.
    func runRecent(_ term: String) {
        debounceTask?.cancel()
        query = term
        startSearch(term, remember: true)
    }

    /// Adopts a query coming from outside (e.g. AppState demo hook / tab switch).
    func adopt(_ text: String) {
        guard text != query else { return }
        guard !text.isEmpty else {
            cancelSearch()
            clearResults()
            query = ""
            return
        }
        query = text
        debounceTask?.cancel()
        startSearch(text, remember: true)
    }

    func clear() {
        debounceTask?.cancel()
        cancelSearch()
        query = ""
        clearResults()
    }

    func clearRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }

    func applyFilters(_ new: MediaFilters) {
        guard new != filters else { return }
        filters = new
    }

    func setHiding(_ new: ContentHiding) {
        hiding = new
    }

    /// Re-runs the last query against a refreshed API.
    func refresh() {
        let trimmed = lastQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        startSearch(trimmed, remember: false)
    }

    // MARK: Searching

    private func startSearch(_ term: String, remember: Bool) {
        generation += 1
        let generation = generation
        searchTask?.cancel()
        isLoading = true
        error = nil
        lastQuery = term
        if remember { rememberTerm(term) }

        searchTask = Task { [weak self] in
            do {
                let items = try await APIClient.shared.search(query: term)
                guard let self, self.generation == generation else { return }
                self.results = items
                self.hasSearched = true
                self.isLoading = false
            } catch {
                guard let self, self.generation == generation else { return }
                self.results = []
                self.hasSearched = true
                self.isLoading = false
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func cancelSearch() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        isLoading = false
    }

    private func clearResults() {
        results = []
        error = nil
        hasSearched = false
        lastQuery = ""
    }

    private func rememberTerm(_ term: String) {
        var updated = recents.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        updated.insert(term, at: 0)
        recents = Array(updated.prefix(maxRecents))
        UserDefaults.standard.set(recents, forKey: recentsKey)
    }
}

struct SearchView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = SearchModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            BrowseHeader(title: "جستجو", subtitle: subtitle)

            HStack(spacing: 10) {
                searchField
                MediaFilterButton(filters: model.filters,
                                  showsKind: true,
                                  onChange: { model.applyFilters($0) })
            }
            .padding(.top, 18)

            if model.filters.isActive {
                ActiveMediaFilterChips(filters: model.filters,
                                       onChange: { model.applyFilters($0) })
                    .padding(.top, 10)
            }

            content
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onAppear {
            model.setHiding(settings.contentHiding)
            if !app.searchQuery.isEmpty, app.searchQuery != model.query {
                model.adopt(app.searchQuery)
            }
        }
        .onChange(of: app.searchQuery) { _, newValue in
            model.adopt(newValue)
        }
        .onChange(of: model.query) { _, newValue in
            if app.searchQuery != newValue { app.searchQuery = newValue }
        }
        .onChange(of: app.searchFocusTick) { _, _ in
            focusSoon()
        }
        .onChange(of: app.refreshTick) { _, _ in
            model.refresh()
            Task { await app.loadGenres() }
        }
    }

    private func focusSoon() {
        searchFocused = true
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            searchFocused = true
        }
    }

    private var subtitle: String {
        if model.isLoading && model.results.isEmpty { return "در حال جستجو…" }
        let visible = model.visibleResults
        if !visible.isEmpty {
            return model.isPostFiltering
                ? "\(browseNumber(visible.count)) از \(browseNumber(model.results.count)) نتیجه"
                : "\(browseNumber(visible.count)) نتیجه"
        }
        if model.hasSearched, !model.results.isEmpty, model.filters.isActive {
            return "نتیجه‌ای با این فیلترها نیست"
        }
        if model.hasSearched, !model.results.isEmpty, model.hiding.isActive {
            return "همهٔ نتایج پنهان شده‌اند"
        }
        if model.hasSearched { return "نتیجه‌ای یافت نشد" }
        return "نام فیلم یا سریال را بنویسید"
    }

    // MARK: Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Button(action: { model.submit() }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.query.isEmpty ? Theme.textTertiary : Theme.accentBright)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("جستجو")

            TextField("",
                      text: Binding(get: { model.query }, set: { model.updateQuery($0) }),
                      prompt: Text("نام فیلم یا سریال…").foregroundColor(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(.ccloud(14))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .focused($searchFocused)
                .onSubmit { model.submit() }

            if !model.query.isEmpty {
                Button(action: { model.clear() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("پاک کردن")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(model.isLoading ? Theme.accent.opacity(0.55) : Theme.stroke, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.results.isEmpty {
            ScrollView(showsIndicators: false) {
                BrowseSkeletonGrid(count: 10)
                    .padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)
        } else if let error = model.error {
            ErrorStateView(message: error) {
                model.submit()
            }
            .frame(maxHeight: .infinity)
        } else if !model.visibleResults.isEmpty {
            resultsView
        } else if !model.results.isEmpty, model.filters.isActive {
            MediaFilteredEmptyView(hasMore: false,
                                   onScanMore: {},
                                   onClear: { model.applyFilters(MediaFilters()) })
                .frame(maxHeight: .infinity)
        } else if !model.results.isEmpty, model.hiding.isActive {
            EmptyStateView(icon: "eye.slash",
                           title: "همهٔ نتایج پنهان شده‌اند",
                           message: "برای «\(model.lastQuery)» نتیجه‌ای هست، اما همه در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.")
                .frame(maxHeight: .infinity)
        } else if model.hasSearched {
            EmptyStateView(icon: "magnifyingglass",
                           title: "نتیجه‌ای پیدا نشد",
                           message: "برای «\(model.lastQuery)» چیزی پیدا نشد. عبارت دیگری را امتحان کنید.")
                .frame(maxHeight: .infinity)
        } else {
            idleView
        }
    }

    private var resultsView: some View {
        VStack(alignment: .trailing, spacing: 12) {
            HStack(spacing: 8) {
                if model.isLoading {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                }
                Text(resultsCaption)
                    .font(.ccloud(11.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }

            ScrollView(showsIndicators: false) {
                BrowseMovieGrid(movies: model.visibleResults, showsBadge: true) { movie in
                    app.openMovie(movie)
                }
                .padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var resultsCaption: String {
        if model.isPostFiltering {
            return "\(browseNumber(model.visibleResults.count)) از \(browseNumber(model.results.count)) نتیجه برای «\(model.lastQuery)» • فیلترشده"
        }
        return "نتایج برای «\(model.lastQuery)»"
    }

    private var idleView: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if !model.recents.isEmpty {
                HStack(spacing: 10) {
                    Text("جستجوهای اخیر")
                        .font(.ccloud(12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    Button(action: { model.clearRecents() }) {
                        Text("پاک کردن")
                            .font(.ccloud(11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.recents, id: \.self) { term in
                            FilterChip(title: term, isSelected: false) {
                                model.runRecent(term)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(height: 34)
            }

            EmptyStateView(icon: "magnifyingglass",
                           title: "جستجو در CCloud",
                           message: "نام فیلم یا سریال مورد نظر را بنویسید؛ نتایج به‌صورت خودکار نمایش داده می‌شوند.")
                .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
