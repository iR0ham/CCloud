import Foundation

// MARK: - Built-in catalog adapter (Task B3-S)
//
// Swift mirror of `flutter_app/lib/core/builtin_catalog_adapter.dart` (and, in JavaScript,
// `webos_app/app/js/builtin_catalog_adapter.js`). The built-in Iran list already exists as runtime
// `LiveTVChannel` rows (famelack, see `LiveTVCatalog.swift` and `LiveTVModels.swift`), and this adapter is the
// only bridge that lets those rows live in the multi-source catalog. Its whole job is to add nothing: no
// channel the provider does not state, no capability a player has not proven, no logo the dataset does not
// carry.
//
// Identity uses the same recipes as `LiveSourceRegistry.register`, because a built-in row and a parsed
// playlist row from the same provider are the same member — that is what lets a user add an external playlist
// that re-lists IRIB 1 without the list doubling.
//
// Deliberate choices, each of which the Dart and JavaScript ports reproduce:
//
// * A row without a provider ID still needs a stable one, so the name-fold becomes the provider ID under the
//   `name:` prefix. It is provider-namespaced, so it can never collide with a real ID.
// * Rows sharing a provider ID merge into one member with gapless priorities rather than producing a duplicate.
// * No logo is invented: the built-in dataset carries none, so `logoUrl` stays nil and a name+country pair is
//   scored 75 rather than pretending to be 85.
// * Credential-bearing addresses are refused, not stored. `RegisteredBuiltInCatalog` has no issue channel
//   (unlike the parse path), so a refused address simply disappears; the property that matters is that the
//   caller can never see a credential in persisted text.
// * Display names arrive exactly as the provider stated them. `LiveTVM3UText.displayName` is the playlist-parse
//   path's noise strip and is not applied here, so a built-in row whose own name carries a `(720p)`-style token
//   yields no merge candidate for a clean-named sibling. That is the same known gap recorded for the Dart port
//   in `EXECUTION_LOG.md`; candidates only ever suggest, so it under-suggests rather than mis-merges, and B4
//   owns closing it.

/// What the built-in rows contribute: members, their sources, and the untouched runtime row list.
struct RegisteredBuiltInCatalog: Sendable {
    var members: [ChannelMember]
    var sources: [ChannelSourceRecord]

    /// The runtime list the caller passed in, returned as-is so the player keeps working from the same rows
    /// while the catalog gains its member and source records. Swift arrays are value types, so this cannot
    /// alias a mutable copy the way the Dart `List.unmodifiable` wrapper has to.
    var channels: [LiveTVChannel]
}

/// Turns built-in `channels` into catalog members and sources.
func registerBuiltInChannels(
    _ channels: [LiveTVChannel],
    playlistId: String,
    providerNamespace: String
) -> RegisteredBuiltInCatalog {
    var members: [ChannelMember] = []
    var sources: [ChannelSourceRecord] = []
    var seenMemberIds = Set<String>()
    var priorityByMember: [String: Int] = [:]
    var seenUrlByMember: [String: Set<String>] = [:]

    for channel in channels {
        let trimmedId = channel.nanoid.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerChannelId = trimmedId.isEmpty
            ? "name:\(LiveMatchKey.key(channel.name))"
            : trimmedId
        let memberId = "member:" + StableKeyHash.hash(
            "\(playlistId)\nprovider\n\(providerNamespace)\n\(providerChannelId)"
        )

        // The set is the dedup: a second Famelack row carrying the same provider ID contributes its URLs to
        // the member that already exists instead of minting a duplicate station.
        if !seenMemberIds.contains(memberId) {
            seenMemberIds.insert(memberId)
            let ordinal = members.count
            members.append(ChannelMember(
                memberId: memberId,
                playlistId: playlistId,
                providerNamespace: providerNamespace,
                providerChannelId: providerChannelId,
                displayName: channel.name,
                normalizedName: LiveMatchKey.key(channel.name),
                logoUrl: nil,
                group: nil,
                // `LiveTVChannel.countryCode` only uppercases; a padded value is still unknown-but-nonempty
                // there, so the adapter normalizes the same way the comparison layer does.
                countryCode: comparableBuiltInCountry(channel.country),
                languages: channel.languages,
                tvgId: trimmedId.isEmpty ? nil : trimmedId,
                ordinal: ordinal
            ))
        }

        var seenUrls = seenUrlByMember[memberId] ?? []
        var priority = priorityByMember[memberId] ?? 0
        for raw in channel.streams {
            guard let canonical = LivePlaylistParser.canonicalStreamURL(raw) else { continue }
            // Remembered before the credential test, so two spellings of one refused address are refused once
            // and the priority sequence stays gapless.
            if seenUrls.contains(canonical) { continue }
            seenUrls.insert(canonical)
            if LivePlaylistParser.isSensitiveURL(canonical) { continue }
            sources.append(ChannelSourceRecord(
                sourceId: "source:" + StableKeyHash.hash("\(memberId)\nurl\n\(canonical)"),
                // Rule 4 again: a built-in row is its own channel until the user associates it.
                channelId: memberId,
                memberId: memberId,
                playlistId: playlistId,
                providerNamespace: providerNamespace,
                label: priority == 0
                    ? "منبع اصلی"
                    : "منبع \(PersianNumber.string(priority + 1))",
                streamUrl: canonical,
                streamSecretRef: nil,
                protocolHint: LivePlaylistParser.protocolHint(for: canonical),
                // Parsing a row is not evidence about a decoder: nothing here claims support.
                rendererCapability: .notYetVerified,
                origin: .playlist,
                priority: priority,
                enabled: true,
                health: .unverified,
                lastSuccessfulPlaybackAt: nil,
                lastFailedPlaybackAt: nil,
                lastErrorCode: nil
            ))
            priority += 1
        }
        seenUrlByMember[memberId] = seenUrls
        priorityByMember[memberId] = priority
    }

    return RegisteredBuiltInCatalog(members: members, sources: sources, channels: channels)
}

/// A blank country is *unknown*, not a country named `""`: the comparison layer must be able to tell the two
/// apart, because an unknown value can neither match nor conflict.
private func comparableBuiltInCountry(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return trimmed.isEmpty ? nil : trimmed
}
