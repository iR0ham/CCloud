import Foundation

// Behaviour-neutral live row composer (task B4-3 slice S1).
//
// The JavaScript half is `webos_app/app/js/live_source_composer.js`, the Dart half is
// `flutter_app/lib/core/live_source_composer.dart`, and all three read the same bytes from
// `Tests/fixtures/live-composer/composer_cases.json`. S1 adds the join without adding a call site: nothing in
// the shipping app reads this file yet. What it answers is the question S2 has to ask at the live screens —
// "today's built-in row list, plus whatever the stored catalog would contribute, in the row type the screens
// already render" — and it must answer it with today's list identical whenever the stored document is absent,
// empty, or unreadable. That neutrality claim, not the merge, is what the suites here pin.
//
// The pipeline, in the order that keeps each stage's contract intact:
//
// 1. `registerBuiltInChannels` turns the host rows into members and sources. That adapter is the only bridge
//    between the built-in list and the catalog, so the composer calls it rather than restating its recipes.
// 2. Registered members are appended to the stored rows, deduplicated by the provider identity the adapter
//    writes (`playlistId` + `providerNamespace` + `providerChannelId`) rather than by `memberId`. A stored row
//    always wins, so a document that already carries the built-in half keeps its own ids — which is also what
//    lets the shared fixture name a built-in member literally instead of making three ports reproduce a
//    `stableKeyHash` digest. A folded member's sources are retargeted onto the survivor, because the view drops
//    a source whose member is unknown, and deduplicated by (member, address) rather than `sourceId`.
// 3. An enabled `builtin:live` playlist record is injected only when the state carries none. Without a record
//    the view hides every built-in member (`UnifiedLiveCatalog.swift:34` gates members on an enabled playlist),
//    so the list a user has always seen would vanish. The injection is forced by neutrality, and it is not the
//    open owner decision about an enable-flag default: a record the user did write is never overwritten.
// 4. `buildUnifiedChannels` is called, not reimplemented. Grouping, association order and source priority are
//    its rules; the composer reads them out of its result instead of deriving them a second time.
// 5. The result is projected back onto host rows. A channel containing a built-in member adds its addresses to
//    that row; a channel with no built-in half becomes one new row.
//
// Two asymmetries inside step 5 are deliberate:
//
// * An anchored row keeps its own stream text. The catalog stores a canonicalized address, which can differ in
//   case or default port from what the provider wrote, and today's player is handed the provider's text — so
//   normalizing it here would be exactly the behaviour change S2 must decide on. Deduplication compares
//   canonical forms, so a re-spelled origin does not become a second entry.
// * A credential-bearing address is refused only among the addresses being added. One already in the built-in
//   list is today's behavior; one arriving from the catalog would be a new plaintext address handed to
//   `PlaybackRequest` and shown by the copy-address action, so it is dropped and counted instead.
//
// `issues` carries §18.5's measurement rather than a verdict. The composer must not fold-normalize built-in
// names, so `LiveMatchKey.key(name)` and the same fold over `LiveTVM3UText.displayName(name)` are allowed to
// differ; each difference is reported as one `builtinFoldGap`. That is a known-gap count for the reports, never
// a production failure, and with no call site yet it cannot fail anything.
//
// Ordering is the host comparator, never the catalog's `userOrder`-then-appearance order (invariant I3). The
// built-in prefix keeps the order the fetch already produced and new rows are inserted where that comparator
// puts them, so the function is a literal identity when the state adds nothing. Sorting the whole list instead
// would let an unstable sort swap two same-named rows between refreshes, which is a behaviour change hiding
// inside a "no-op" path.

/// Issue codes the composer emits, spelled like `LivePlaylistParser` spells its own.
///
/// `secretStorageUnavailable` is that parser's existing refusal word (`LivePlaylistParser.swift:693`), reused
/// so one condition has one name across the parse and display paths. `builtinFoldGap` is the only code this
/// file owns. Both are counted by name in the shared fixture, on all three ports.
enum LiveComposerIssueCode {
    static let secretRefusal = "secretStorageUnavailable"
    static let foldGap = "builtinFoldGap"
}

/// The built-in list's playlist and provider identity, mirroring the adapter call sites rather than inventing
/// a fourth spelling of either.
enum LiveSourceComposer {
    static let builtInPlaylistId = "builtin:live"
    static let builtInProviderNamespace = "famelack"
}

// MARK: - Composition

/// Join today's built-in rows with whatever [state] would contribute.
///
/// A nil state means "no usable document" — absent, undecodable, or refused by the persistence seam. That is
/// the identity case: [built] comes back as it went in, which makes corrupt-document neutrality a property of
/// this function rather than a promise about its caller.
func composeLiveRows(_ built: [LiveTVChannel], _ state: LiveCatalogState?) -> (
    rows: [LiveTVChannel], issues: [CatalogIssue]
) {
    // The fold gap is a fact about the built-in names, not about the join, so it is measured on every path.
    var issues = LiveSourceComposer.foldGapIssues(for: built)
    guard let state else {
        return (rows: built, issues: issues)
    }
    return (rows: LiveSourceComposer.compose(built: built, from: state, issues: &issues), issues: issues)
}

extension LiveSourceComposer {

    /// One issue per built-in row whose raw name folds differently from its noise-stripped display name.
    ///
    /// This is the measurement §18.5 asks for in place of a normalization: the built-in path keeps provider
    /// text verbatim, so such a row can never produce a merge candidate for a clean-named parsed sibling. The
    /// gap stays open (task B4 owns it); what changes is that it is now counted.
    static func foldGapIssues(for built: [LiveTVChannel]) -> [CatalogIssue] {
        var issues: [CatalogIssue] = []
        for row in built where LiveMatchKey.key(row.name)
            != LiveMatchKey.key(LiveTVM3UText.displayName(row.name)) {
            issues.append(CatalogIssue(
                code: LiveComposerIssueCode.foldGap,
                message: "Built-in name keeps a quality token, so its match key differs from the playlist-path display name",
                line: nil
            ))
        }
        return issues
    }

    static func compose(
        built: [LiveTVChannel],
        from state: LiveCatalogState,
        issues: inout [CatalogIssue]
    ) -> [LiveTVChannel] {
        let registered = registerBuiltInChannels(
            built,
            playlistId: builtInPlaylistId,
            providerNamespace: builtInProviderNamespace
        )
        let merged = merge(stored: state, registered: registered, builtInCount: built.count)
        let view = buildUnifiedChannels(merged)
        let anchored = anchorIndexes(for: built, members: merged.members)

        // Which built-in row, if any, each channel belongs to. A channel reaches a row through the member the
        // adapter minted from it, so the join follows recorded identity rather than name similarity.
        var channelForRow: [Int: LogicalChannel] = [:]
        for channel in view {
            guard let index = smallestAnchor(in: channel.memberIds, from: anchored) else { continue }
            // One channel per built row. A second channel claiming the same row would otherwise duplicate it,
            // and duplicating a row the user has always seen once is not something a display layer may do.
            if channelForRow[index] == nil { channelForRow[index] = channel }
        }

        var rows: [LiveTVChannel] = []
        for (index, row) in built.enumerated() {
            guard let channel = channelForRow[index] else {
                rows.append(row)
                continue
            }
            rows.append(union(anchor: row, with: channel, issues: &issues))
        }

        var minted: [LiveTVChannel] = []
        let claimed = Set(channelForRow.values.map { $0.channelId })
        for channel in view where !claimed.contains(channel.channelId) {
            if let row = row(for: channel, issues: &issues) { minted.append(row) }
        }

        return insert(minted: sortedByHostName(minted), into: rows)
    }

    /// The built-in row each merged member was registered from, as an index into the caller's list.
    ///
    /// Matching uses the fields the adapter itself wrote — `displayName` is the row's name verbatim and
    /// `tvgId` its trimmed provider id — because re-deriving the `name:`-prefix fallback here would put a
    /// second copy of that recipe in the codebase, which is how a refresh ends up with two members for one
    /// station.
    static func anchorIndexes(for built: [LiveTVChannel], members: [ChannelMember]) -> [String: Int] {
        var rowsByTvgId: [String: Int] = [:]
        var rowsByName: [String: Int] = [:]
        for (index, row) in built.enumerated() {
            let trimmed = row.nanoid.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, rowsByTvgId[trimmed] == nil { rowsByTvgId[trimmed] = index }
            if rowsByName[row.name] == nil { rowsByName[row.name] = index }
        }

        var anchored: [String: Int] = [:]
        for member in members {
            guard member.playlistId == builtInPlaylistId,
                  member.providerNamespace == builtInProviderNamespace,
                  anchored[member.memberId] == nil else { continue }
            if let tvgId = member.tvgId, let index = rowsByTvgId[tvgId] {
                anchored[member.memberId] = index
            } else if let index = rowsByName[member.displayName] {
                anchored[member.memberId] = index
            }
        }
        return anchored
    }

    static func smallestAnchor(in memberIds: [String], from anchored: [String: Int]) -> Int? {
        var best: Int?
        for memberId in memberIds {
            guard let index = anchored[memberId] else { continue }
            if best == nil || index < best! { best = index }
        }
        return best
    }

    /// Members and sources the document does not already carry, plus the built-in playlist record if absent.
    ///
    /// Appending rather than replacing keeps every id the state refers to through `logicalIdByMemberId` and
    /// `associations` valid, so the view's grouping — which is the user's own decision — survives the join.
    static func merge(
        stored: LiveCatalogState,
        registered: RegisteredBuiltInCatalog,
        builtInCount: Int
    ) -> LiveCatalogState {
        // Provider identity, not `memberId`, decides whether two rows are the same station. A registered member
        // whose provider key is already in the document is that station, so the stored row keeps its own id and
        // the minted one disappears — which is also what lets the shared fixture name a built-in member
        // literally instead of making three ports reproduce a `stableKeyHash` digest.
        var survivorForRegisteredId: [String: String] = [:]
        var membersByProviderKey: [String: String] = [:]
        for member in stored.members { membersByProviderKey[providerKey(of: member)] = member.memberId }

        var members = stored.members
        for member in registered.members {
            let key = providerKey(of: member)
            if let existing = membersByProviderKey[key] {
                survivorForRegisteredId[member.memberId] = existing
                continue
            }
            membersByProviderKey[key] = member.memberId
            members.append(member)
        }

        // A source follows the member it was registered from, so a folded member's addresses are retargeted
        // onto the survivor instead of being dropped: `buildUnifiedChannels` discards a source whose member is
        // unknown (`UnifiedLiveCatalog.swift:67`), and one new Famelack URL would otherwise vanish whenever the
        // stored document already named that station. Both id fields move together because the record is meant
        // to describe the surviving member; the view groups by member, not by these fields, so the remap only
        // keeps the ephemeral state internally consistent.
        //
        // The dedup key is (member, canonical address) rather than `sourceId`: the same address under two
        // spellings of the row id is one address, and appending it twice would duplicate a playable source in
        // the channel the user sees.
        var sources = stored.sources
        var seenAddresses = Set(stored.sources.map { addressKey(of: $0) })
        for source in registered.sources {
            var record = source
            if let survivor = survivorForRegisteredId[source.memberId] {
                record.memberId = survivor
                record.channelId = survivor
            }
            guard seenAddresses.insert(addressKey(of: record)).inserted else { continue }
            sources.append(record)
        }

        var playlists = stored.playlists
        if !playlists.contains(where: { $0.playlistId == builtInPlaylistId }) {
            playlists.append(PlaylistRecord(
                playlistId: builtInPlaylistId,
                name: "CCloud",
                sourceType: .builtIn,
                locationRef: builtInPlaylistId,
                // See the header: an enabled record is what keeps today's list visible. `createdAt` is the
                // epoch rather than `Date()` because this record is a view precondition, not an event, and an
                // impure timestamp would make the composed output differ between two runs of the same bytes.
                enabled: true,
                createdAt: Date(timeIntervalSince1970: 0),
                lastUpdatedAt: nil,
                lastSuccessfulRefresh: nil,
                refreshStatus: .ready,
                lastErrorCode: nil,
                channelCount: builtInCount,
                parsingVersion: 1
            ))
        }

        return LiveCatalogState(
            schemaVersion: stored.schemaVersion,
            playlists: playlists,
            members: members,
            sources: sources,
            associations: stored.associations,
            preferences: stored.preferences,
            recentWatches: stored.recentWatches,
            logicalIdByMemberId: stored.logicalIdByMemberId
        )
    }

    static func providerKey(of member: ChannelMember) -> String {
        "\(member.playlistId)\n\(member.providerNamespace)\n\(member.providerChannelId)"
    }

    static func addressKey(of source: ChannelSourceRecord) -> String {
        "\(source.memberId)\n\(source.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// The anchor row, plus only the addresses it does not already list, in catalog priority order.
    ///
    /// Every other field stays the anchor's own: no catalog member can state a geo-block for a row the provider
    /// already described, and inheriting one would be an invention.
    static func union(
        anchor: LiveTVChannel,
        with channel: LogicalChannel,
        issues: inout [CatalogIssue]
    ) -> LiveTVChannel {
        let existing = anchor.sources.streams
        var known = Set(existing.compactMap { LivePlaylistParser.canonicalStreamURL($0)?.lowercased() })
        let extra = contributedURLs(from: channel.sources, known: &known, issues: &issues)
        return extra.isEmpty ? anchor : anchor.replacingStreams(existing + extra)
    }

    /// A catalog channel with no built-in half becomes one row carrying exactly what the catalog states.
    ///
    /// The row identity is the logical channel id, so it is never empty and the display layer's key stays
    /// unique. A streamless channel yields no row: today's fetch already refuses a streamless entry, so a
    /// channel that cannot play anything would be a new dead cell rather than a preserved behaviour.
    static func row(for channel: LogicalChannel, issues: inout [CatalogIssue]) -> LiveTVChannel? {
        var known = Set<String>()
        let urls = contributedURLs(from: channel.sources, known: &known, issues: &issues)
        guard !urls.isEmpty else { return nil }
        return LiveTVChannel(
            nanoid: channel.channelId,
            name: channel.displayName,
            sources: LiveTVStreams(streams: urls),
            languages: channel.languages,
            // The host row holds a plain string and `countryCode` uppercases it; the catalog's comparable form
            // is uppercase-or-nil, and an unknown country must not render as a country named "".
            country: channel.countryCode ?? "",
            // Nothing in the catalog models a geo-block at all — `ChannelMember` carries no such field — and the
            // adapter's answer to a claim it has no evidence for is nil rather than a guess. A row the provider
            // never described cannot be rendered as blocked.
            isGeoBlocked: false
        )
    }

    /// The addresses a channel contributes that are new, playable-shaped, and credential-free.
    ///
    /// `known` grows as it is consumed, so two sources spelling one address contribute it once even when they
    /// arrive in the same pass.
    static func contributedURLs(
        from sources: [ChannelSourceRecord],
        known: inout Set<String>,
        issues: inout [CatalogIssue]
    ) -> [String] {
        var urls: [String] = []
        for source in sources {
            // A disabled source stays in the channel's own list — the user manages it there — but this output is
            // the playable row list, and eligibility is `enabled`. Adding a turned-off address here would undo
            // the toggle.
            if !source.enabled { continue }
            // A secret-backed source carries no address in the document at all, so there is nothing to add and
            // no refusal to report; the recovery chain resolves it through the secret store in Phase C.
            if source.streamSecretRef != nil { continue }
            let trimmed = source.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let canonical = LivePlaylistParser.canonicalStreamURL(trimmed) else { continue }
            if LivePlaylistParser.isSensitiveURL(trimmed) {
                issues.append(CatalogIssue(
                    code: LiveComposerIssueCode.secretRefusal,
                    // No address text in the message: an issue list is allowed to reach a log, and the whole
                    // point of the refusal is that the credential does not travel.
                    message: "Credential-bearing address withheld from the composed row list",
                    line: nil
                ))
                continue
            }
            let key = canonical.lowercased()
            guard !known.contains(key) else { continue }
            known.insert(key)
            urls.append(trimmed)
        }
        return urls
    }

    /// Host-comparator order among the new rows.
    ///
    /// This restates `LiveTVChannelMerge.sortedByName` (`LiveTVCatalog.swift:18-20`) because that enum lives in
    /// a file the contract harness cannot compile — `LiveTVCatalog.swift` carries the URLSession client. The
    /// composer's own tests pin the resulting order, so a future change to the shipping comparator shows up as a
    /// RED suite rather than a silent divergence between the list a user sees and the list this joins onto.
    static func sortedByHostName(_ rows: [LiveTVChannel]) -> [LiveTVChannel] {
        // Index sort with an explicit tiebreak: `Array.sorted` is not documented stable, and two rows sharing
        // a name arriving in the opposite order between refreshes is a visible shuffle for no reason.
        var indexes = Array(rows.indices)
        indexes.sort { left, right in
            let order = rows[left].name.localizedCaseInsensitiveCompare(rows[right].name)
            if order != .orderedSame { return order == .orderedAscending }
            return left < right
        }
        return indexes.map { rows[$0] }
    }

    /// Place each new row where the host comparator puts it, leaving the built-in prefix untouched.
    ///
    /// Ties go to the built-in row, so a minted row can never overtake a same-named row the user already sees.
    static func insert(minted: [LiveTVChannel], into rows: [LiveTVChannel]) -> [LiveTVChannel] {
        guard !minted.isEmpty else { return rows }
        var out: [LiveTVChannel] = []
        var next = 0
        for row in rows {
            while next < minted.count,
                  minted[next].name.localizedCaseInsensitiveCompare(row.name) == .orderedAscending {
                out.append(minted[next])
                next += 1
            }
            out.append(row)
        }
        out.append(contentsOf: minted[next...])
        return out
    }
}
