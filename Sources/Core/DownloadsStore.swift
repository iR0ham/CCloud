import Foundation
import AppKit

// MARK: - In-app download manager
//
// Downloads progressive files (mp4/mkv/…) straight into ~/Downloads/CCloud. HLS/DASH playlists are
// not downloadable as a single file, so callers fall back to copying the link. Metadata is stored
// in Application Support; an interrupted download is reported as failed and can be retried.

@MainActor
final class DownloadsStore: ObservableObject {

    enum State: String, Codable {
        case downloading, completed, failed
    }

    struct Item: Identifiable, Codable, Equatable {
        let id: UUID
        var title: String
        var subtitle: String?
        var posterURL: String?
        var sourceURL: String
        var fileName: String
        var kind: String
        var state: State
        var receivedBytes: Int64
        var totalBytes: Int64
        var createdAt: Date
        var errorMessage: String?

        var progress: Double {
            guard totalBytes > 0 else { return 0 }
            return min(max(Double(receivedBytes) / Double(totalBytes), 0), 1)
        }

        var fileURL: URL {
            DownloadsStore.directory.appendingPathComponent(fileName)
        }

        var fileExists: Bool {
            FileManager.default.fileExists(atPath: fileURL.path)
        }
    }

    enum StartResult {
        case started, duplicate, unsupported
    }

    /// Called on the main actor when a download finishes successfully.
    var onCompleted: ((Item) -> Void)?

    @Published private(set) var items: [Item] = []

    nonisolated static let directory: URL = {
        let fm = FileManager.default
        let downloads = (try? fm.url(for: .downloadsDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let dir = downloads.appendingPathComponent("CCloud", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let fileURL: URL
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var monitors: [UUID: Task<Void, Never>] = [:]

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("CCloudMac", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("downloads.json")
        load()
    }

    // MARK: Public actions

    @discardableResult
    func start(title: String,
               subtitle: String?,
               posterURL: String?,
               source: MediaSource) -> StartResult {
        guard source.isFileDownloadable, let url = source.urlValue else { return .unsupported }
        if items.contains(where: { $0.sourceURL == source.url && $0.state == .downloading }) {
            return .duplicate
        }
        let extensionName = source.downloadFileExtension
        let name = Self.fileName(title: title, quality: source.qualityLabel, extensionName: extensionName)
        startDownload(title: title,
                      subtitle: subtitle,
                      posterURL: posterURL,
                      url: url,
                      fileName: name,
                      kind: extensionName)
        return .started
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        monitors[id]?.cancel()
        monitors[id] = nil
        if let index = items.firstIndex(where: { $0.id == id }) {
            let item = items.remove(at: index)
            try? FileManager.default.removeItem(at: item.fileURL)
            save()
        }
    }

    func retry(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let url = URL(string: items[index].sourceURL) else { return }
        let item = items[index]
        startDownload(title: item.title,
                      subtitle: item.subtitle,
                      posterURL: item.posterURL,
                      url: url,
                      fileName: item.fileName,
                      kind: item.kind,
                      reuseID: item.id)
    }

    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].state == .downloading {
            cancel(id)
            return
        }
        items.remove(at: index)
        save()
    }

    /// Removes finished/failed entries from the list; downloaded files stay on disk.
    func clearFinished() {
        items.removeAll { $0.state != .downloading }
        save()
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.fileExists {
            NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
        } else {
            revealFolder()
        }
    }

    func revealFolder() {
        NSWorkspace.shared.open(Self.directory)
    }

    // MARK: Download lifecycle

    private func startDownload(title: String,
                               subtitle: String?,
                               posterURL: String?,
                               url: URL,
                               fileName: String,
                               kind: String,
                               reuseID: UUID? = nil) {
        let id = reuseID ?? UUID()
        let item = Item(id: id,
                        title: title,
                        subtitle: subtitle,
                        posterURL: posterURL,
                        sourceURL: url.absoluteString,
                        fileName: fileName,
                        kind: kind,
                        state: .downloading,
                        receivedBytes: 0,
                        totalBytes: 0,
                        createdAt: Date(),
                        errorMessage: nil)
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        save()

        var request = URLRequest(url: url)
        request.setValue("CCloudMac/2.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            Task { @MainActor [weak self] in
                self?.finish(id: id, tempURL: tempURL, status: status, error: error)
            }
        }
        tasks[id] = task
        task.resume()
        startMonitor(id: id)
    }

    private func startMonitor(id: UUID) {
        monitors[id]?.cancel()
        monitors[id] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self else { return }
                guard let task = self.tasks[id] else { return }
                guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                let total = task.countOfBytesExpectedToReceive
                let received = task.countOfBytesReceived
                self.items[index].receivedBytes = received
                if total > 0 { self.items[index].totalBytes = total }
            }
        }
    }

    private func finish(id: UUID, tempURL: URL?, status: Int?, error: Error?) {
        tasks[id] = nil
        monitors[id]?.cancel()
        monitors[id] = nil
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        if let error = error as? URLError, error.code == .cancelled { return }

        let item = items[index]
        guard error == nil, let status, (200..<300).contains(status), let tempURL else {
            items[index].state = .failed
            items[index].errorMessage = Self.persianError(error: error, status: status)
            save()
            return
        }

        do {
            if item.fileExists { try FileManager.default.removeItem(at: item.fileURL) }
            do {
                try FileManager.default.moveItem(at: tempURL, to: item.fileURL)
            } catch {
                try FileManager.default.copyItem(at: tempURL, to: item.fileURL)
            }
            items[index].state = .completed
            items[index].errorMessage = nil
            let size = (try? FileManager.default.attributesOfItem(atPath: item.fileURL.path)[.size] as? NSNumber)?.int64Value
            if let size { items[index].receivedBytes = size; items[index].totalBytes = size }
            save()
            onCompleted?(items[index])
        } catch {
            items[index].state = .failed
            items[index].errorMessage = "ذخیرهٔ فایل ممکن نشد: \(error.localizedDescription)"
            save()
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              var stored = try? decoder.decode([Item].self, from: data) else { return }
        for index in stored.indices {
            switch stored[index].state {
            case .downloading:
                stored[index].state = .failed
                stored[index].errorMessage = "دانلود پیش از پایان قطع شد."
            case .completed where !stored[index].fileExists:
                stored[index].state = .failed
                stored[index].errorMessage = "فایل از پوشهٔ دانلودها حذف شده است."
            default:
                break
            }
        }
        items = stored
    }

    private func save() {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Helpers

    private static func fileName(title: String, quality: String, extensionName: String) -> String {
        var base = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "CCloud" }
        if base.count > 90 { base = String(base.prefix(90)) }
        return "\(base) \(quality).\(extensionName)"
    }

    private static func persianError(error: Error?, status: Int?) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "پاسخ سرور دیر رسید."
            case .notConnectedToInternet: return "اینترنت در دسترس نیست."
            case .cannotFindHost, .dnsLookupFailed: return "سرور پیدا نشد."
            case .networkConnectionLost: return "اتصال شبکه قطع شد."
            default: return error.localizedDescription
            }
        }
        if let error { return error.localizedDescription }
        if let status { return "سرور با کد \(status) پاسخ داد." }
        return "دانلود ناموفق بود."
    }
}
