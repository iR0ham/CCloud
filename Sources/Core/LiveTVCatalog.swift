import Foundation

// MARK: - Merged Live TV catalog
//
// Famelack's Iran file is the whole «ایران» list: it carries each channel's streams, language and
// geo-blocking. iptv-org's Iran and Persian playlists only back up those rows with extra stream
// URLs; the channels just it knows are mostly diaspora or dead links, so they stay out of the list.

enum LiveTVChannelMerge {

    static func extraStreams(for channel: LiveTVChannel, from addition: LiveTVChannel) -> [String]? {
        let extra = addition.streams.filter { url in
            !channel.streams.contains { existing in existing.caseInsensitiveCompare(url) == .orderedSame }
        }
        return extra.isEmpty ? nil : extra
    }

    static func sortedByName(_ channels: [LiveTVChannel]) -> [LiveTVChannel] {
        channels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Catalog

@MainActor
final class LiveTVCatalog {

    static let shared = LiveTVCatalog()

    private var cache: [LiveTVChannel]?
    private var inFlight: Task<[LiveTVChannel], Error>?

    private init() {}

    // MARK: Channels

    func channels(for country: LiveTVCountry) async throws -> [LiveTVChannel] {
        if country.code == "IR" { return try await load() }
        return try await LiveTVClient.shared.channels(countryCode: country.code)
    }

    func clearCache() {
        cache = nil
        LiveTVClient.shared.clearCache()
        LiveTVM3UClient.shared.clearCache()
    }

    // MARK: Loading

    private func load() async throws -> [LiveTVChannel] {
        if let cached = cache { return cached }
        if let running = inFlight { return try await running.value }

        let task = Task<[LiveTVChannel], Error> {
            // Either source can be down; the list is still worth showing when one answers.
            let famelack = (try? await LiveTVClient.shared.channels(countryCode: "IR")) ?? []
            let byCountry = (try? await LiveTVM3UClient.shared.countryChannels("ir")) ?? []
            let byLanguage = (try? await LiveTVM3UClient.shared.languageChannels("fas")) ?? []
            let channels = LiveTVIranList.build(famelack: famelack,
                                                byCountry: byCountry,
                                                byLanguage: byLanguage)
            guard !channels.isEmpty else { throw APIError.empty("live channels") }
            return channels
        }
        inFlight = task
        do {
            let channels = try await task.value
            inFlight = nil
            cache = channels
            return channels
        } catch {
            inFlight = nil
            throw error
        }
    }
}

// MARK: - Iranian list with iptv-org backup streams

private enum LiveTVIranList {

    /// iptv-org lists one channel under several ids and playlists; folded by name first.
    private struct Group {
        let entry: LiveTVM3U.Entry
        var countryCode: String
        var languages: [String]
        var streams: [String]

        var channel: LiveTVChannel {
            entry.channel(languages: languages, country: countryCode).replacingStreams(streams)
        }

        mutating func absorb(_ entry: LiveTVM3U.Entry, language: String?) {
            if countryCode.isEmpty { countryCode = entry.countryCode }
            if let language, !languages.contains(language) {
                languages.append(language)
            }
            for url in entry.streams
            where !streams.contains(where: { $0.caseInsensitiveCompare(url) == .orderedSame }) {
                streams.append(url)
            }
        }
    }

    static func build(famelack: [LiveTVChannel],
                      byCountry: [LiveTVM3U.Entry],
                      byLanguage: [LiveTVM3U.Entry]) -> [LiveTVChannel] {
        var groups: [String: Group] = [:]
        var playlist: [(entry: LiveTVM3U.Entry, language: String?)] = []
        byCountry.forEach { playlist.append(($0, nil)) }
        byLanguage.forEach { playlist.append(($0, "fas")) }

        for item in playlist {
            let key = LiveTVNameKey.key(item.entry.name)
            guard !key.isEmpty, !item.entry.streams.isEmpty else { continue }
            if var group = groups[key] {
                group.absorb(item.entry, language: item.language)
                groups[key] = group
            } else {
                groups[key] = Group(entry: item.entry,
                                    countryCode: item.entry.countryCode,
                                    languages: item.language.map { [$0] } ?? [],
                                    streams: item.entry.streams)
            }
        }

        // iptv-org backs up famelack's rows and adds no channels of its own: its Iran and Persian
        // playlists are full of diaspora and dead links that do not belong in the Iranian list.
        return LiveTVChannelMerge.sortedByName(famelack.map { channel in
            let key = LiveTVNameKey.key(channel.name)
            guard let group = key.isEmpty ? nil : groups[key],
                  let extra = LiveTVChannelMerge.extraStreams(for: channel, from: group.channel)
            else { return channel }
            return channel.replacingStreams(channel.streams + extra)
        })
    }
}
