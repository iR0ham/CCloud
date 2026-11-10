import Foundation

// MARK: - Dead-link memory
//
// Every source that fails to play is counted here, so a link that has already burned twice in
// earlier sessions is tried last instead of first. Records expire after a week: hosts get fixed,
// and a stale blacklist would hide a link that started working again.

@MainActor
enum LinkHealth {

    static let failuresBeforeLastTry = 2

    private struct Record: Codable {
        var failures: Int
        var lastFailure: Date
    }

    private static let storageKey = "ccloud.linkHealth"
    private static let recordTTL: TimeInterval = 7 * 24 * 3600
    private static let maxRecords = 300
    private static var memory: [String: Record]?

    static func failureCount(for urlString: String) -> Int {
        records[key(for: urlString)]?.failures ?? 0
    }

    static func isDeprioritized(_ urlString: String) -> Bool {
        failureCount(for: urlString) >= failuresBeforeLastTry
    }

    static func recordFailure(_ urlString: String) {
        let key = key(for: urlString)
        var records = Self.records
        let record = records[key] ?? Record(failures: 0, lastFailure: Date())
        records[key] = Record(failures: record.failures + 1, lastFailure: Date())
        save(records)
    }

    /// A link that played is no longer treated as dead, even if it failed before.
    static func recordSuccess(_ urlString: String) {
        var records = Self.records
        guard records.removeValue(forKey: key(for: urlString)) != nil else { return }
        save(records)
    }

    // MARK: Internals

    /// HLS links carry expiring query tokens, so the identity of a link is origin + path.
    private static func key(for urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }
        components.query = nil
        components.fragment = nil
        return components.string ?? urlString
    }

    private static var records: [String: Record] {
        if let memory { return memory }
        var loaded: [String: Record] = [:]
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            let deadline = Date().timeIntervalSince1970 - recordTTL
            loaded = decoded.filter { $0.value.lastFailure.timeIntervalSince1970 > deadline }
        }
        memory = loaded
        return loaded
    }

    private static func save(_ records: [String: Record]) {
        var kept = records
        if kept.count > maxRecords {
            let newest = kept.sorted { $0.value.lastFailure > $1.value.lastFailure }.prefix(maxRecords)
            kept = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        memory = kept
        if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
