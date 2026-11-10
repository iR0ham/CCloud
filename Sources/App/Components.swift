import SwiftUI
import AppKit
import Combine

// MARK: - Image loading (memory + URL cache, no third-party deps)

@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    /// Active API host, used to rewrite poster URLs pinned to a dead backend host
    /// (the helper hosts mirror /uploads, verified by the API harness).
    var preferredAPIHost: String?

    private static let apiHosts: Set<String> = [
        "server-hi-speed-iran.info", "hostinnegar.com", "windowsdiba.info"
    ]

    private func normalized(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(), Self.apiHosts.contains(host),
              let preferred = preferredAPIHost, preferred.lowercased() != host,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.host = preferred
        return components.url ?? url
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 25
        config.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024,
                                   diskPath: "ccloud-images")
        config.httpAdditionalHeaders = ["User-Agent": "CCloudMac/2.0"]
        config.httpMaximumConnectionsPerHost = 14
        return URLSession(configuration: config)
    }()

    private init() {
        memory.countLimit = 400
    }

    func image(for originalURL: URL) async -> NSImage? {
        let url = normalized(originalURL)
        let key = url.absoluteString as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if let running = inFlight[url.absoluteString] { return await running.value }

        let task = Task<NSImage?, Never> { [session] in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let image = NSImage(data: data) else { return nil }
                return image
            } catch {
                return nil
            }
        }
        inFlight[url.absoluteString] = task
        let image = await task.value
        inFlight[url.absoluteString] = nil
        if let image { memory.setObject(image, forKey: key) }
        return image
    }
}

/// Local state holder for a remote image (no @State — see PROJECT.md toolchain note).
@MainActor
final class RemoteImageModel: ObservableObject {
    @Published var image: NSImage?
    @Published var didFail = false
    @Published var isLoading = false

    func load(_ url: URL?) async {
        image = nil
        didFail = false
        guard let url else { didFail = true; return }
        isLoading = true
        let loaded = await ImageCache.shared.image(for: url)
        guard !Task.isCancelled else { return }
        isLoading = false
        if let loaded { image = loaded } else { didFail = true }
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderIcon: String = "photo"

    @StateObject private var model = RemoteImageModel()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.card

                if let image = model.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if model.didFail || url == nil {
                    Image(systemName: placeholderIcon)
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.textSecondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: url) {
            await model.load(url)
        }
    }
}

// MARK: - Local UI state helpers (macro-free)

@MainActor
final class HoverState: ObservableObject {
    @Published var isHovering = false
}

// MARK: - Shared atoms

struct RatingBadge: View {
    let imdb: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9))
            Text(String(format: "%.1f", imdb)).font(.ccloud(11, weight: .bold))
        }
        .foregroundStyle(Theme.gold)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.62), in: Capsule())
    }
}

struct TypeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ccloud(10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.88), in: Capsule())
    }
}

/// Poster card used in every grid (2:3 poster, hover lift, optional rating/type badges).
struct PosterCard: View {
    let title: String
    let posterURL: URL?
    var year: Int = 0
    var imdb: Double = 0
    var badge: String? = nil
    var subtitle: String? = nil
    /// Optional watch progress (0…1) drawn along the bottom edge of the poster.
    var progress: Double? = nil
    var action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            VStack(alignment: .trailing, spacing: 9) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .fill(Theme.card)

                    CachedAsyncImage(url: posterURL)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        if let badge { TypeBadge(text: badge) }
                        Spacer(minLength: 0)
                    }
                    .padding(7)

                    VStack {
                        Spacer()
                        HStack {
                            if imdb > 0 { RatingBadge(imdb: imdb) }
                            Spacer()
                        }
                    }
                    .padding(7)
                }
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if let progress, progress > 0.001 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.black.opacity(0.45))
                                Rectangle()
                                    .fill(Theme.accentBright)
                                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                            }
                        }
                        .frame(height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .padding(.horizontal, 1)
                        .padding(.bottom, 1)
                        .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(hover.isHovering ? Theme.accent.opacity(0.9) : Theme.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(hover.isHovering ? 0.55 : 0.28),
                        radius: hover.isHovering ? 16 : 7,
                        y: hover.isHovering ? 8 : 3)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(title)
                        .font(.ccloud(13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.ccloud(11, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    } else if year > 0 {
                        Text(String(year))
                            .font(.ccloud(11, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .scaleEffect(hover.isHovering ? 1.025 : 1)
        .animation(.easeOut(duration: 0.16), value: hover.isHovering)
    }
}

struct FilterChip: View {
    let title: String
    var isSelected: Bool = false
    var action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ccloud(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Theme.accent : (hover.isHovering ? Theme.cardHover : Theme.card))
                )
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.ccloud(20, weight: .bold))
                .foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.ccloud(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct LoadingView: View {
    var text: String = "در حال بارگذاری…"

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Theme.accent)
            Text(text).font(.ccloud(13)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    var retryTitle: String = "تلاش دوباره"
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.red)
            Text(message)
                .font(.ccloud(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let retry {
                Button(action: retry) { Text(retryTitle) }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.ccloud(15, weight: .semibold)).foregroundStyle(Theme.text)
            if let message {
                Text(message)
                    .font(.ccloud(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ccloud(compact ? 13 : 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 16 : 22)
            .padding(.vertical, compact ? 8 : 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent)
                    .brightness(configuration.isPressed ? -0.12 : 0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ccloud(compact ? 12 : 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 7 : 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.cardHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct IconActionButton: View {
    let systemName: String
    var help: String = ""
    var tint: Color = Theme.text
    var action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(hover.isHovering ? Theme.cardHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .help(help)
    }
}

// MARK: - Pagination helper (0-based pages, 30 items each)

@MainActor
final class PagedFeed<Item: Identifiable & Hashable>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true

    private var page = 0
    private var generation = 0
    private let loader: (Int) async throws -> [Item]

    init(loader: @escaping (Int) async throws -> [Item]) {
        self.loader = loader
    }

    /// Bridges this feed's changes into the screen model that owns it. A nested
    /// `ObservableObject` is invisible to SwiftUI, so without this the grid would only ever
    /// render the first page: later pages arrive but never trigger a re-render.
    func forwardChanges<Parent: ObservableObject>(to parent: Parent) -> AnyCancellable
    where Parent.ObjectWillChangePublisher == ObservableObjectPublisher {
        objectWillChange.sink { [weak parent] _ in
            parent?.objectWillChange.send()
        }
    }

    func start() async {
        guard items.isEmpty, !isLoading else { return }
        await load(reset: true)
    }

    func retry() async {
        await load(reset: true)
    }

    func reset() async {
        items = []
        page = 0
        hasMore = true
        await load(reset: true)
    }

    func loadMoreIfNeeded(current item: Item) async {
        guard !isLoading, !isLoadingMore, hasMore, error == nil else { return }
        guard let idx = items.firstIndex(of: item) else { return }
        if idx >= max(items.count - 6, 0) {
            await load(reset: false)
        }
    }

    /// Pulls the next page unconditionally (used by filter scanning, which may need to look
    /// past matching items before the grid's scroll trigger fires).
    func loadNextPage() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        if reset {
            generation += 1
            error = nil
            hasMore = true
            page = 0
            isLoading = items.isEmpty
        } else {
            isLoadingMore = true
        }
        let gen = generation
        let requestedPage = page

        do {
            let newItems = try await loader(requestedPage)
            guard gen == generation else { return }
            if reset { items = [] }
            let existing = Set(items.map { $0.id })
            items.append(contentsOf: newItems.filter { !existing.contains($0.id) })
            page = requestedPage + 1
            hasMore = !newItems.isEmpty
            error = nil
        } catch is CancellationError {
            guard gen == generation else { return }
        } catch {
            guard gen == generation else { return }
            if items.isEmpty {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
        isLoadingMore = false
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            Text(message).font(.ccloud(12, weight: .medium)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}
