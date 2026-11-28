import Foundation

// MARK: - Unified catalog view (Task B3-S)
//
// Swift half of `flutter_app/lib/core/unified_catalog.dart`; the JavaScript mirror is
// `webos_app/app/js/unified_catalog.js`. This is the single place the persisted state becomes the list a user
// sees, and it is a projection rather than a second source of truth: it mutates nothing, returns fresh values,
// and the caller may diff or rebuild it freely.
//
// Two consequences of that framing, asserted in `Tests/live-foundation/main.swift` exactly as the Dart suite
// asserts them:
//
// * A disabled playlist disappears from the view while its member and source rows stay in the state, so
//   re-enabling restores precisely what the user had.
// * A disabled *source* stays in its channel's `sources` list, because the user manages it. Playback
//   eligibility is `enabled`, and that filter belongs to the recovery chain (Phase C), not to the view.

/// Builds one `LogicalChannel` per logical ID that has at least one member in an enabled playlist.
///
/// Channels are ordered by explicit `userOrder` first (ascending, unset last), then by the order their
/// preferred member appears in the catalog, so a list stays stable across refreshes and never reorders itself
/// because a preference was edited for an unrelated channel.
func buildUnifiedChannels(_ state: LiveCatalogState) -> [LogicalChannel] {
    let enabledPlaylists = Set(state.playlists.filter { $0.enabled }.map { $0.playlistId })
    var memberById: [String: ChannelMember] = [:]
    for member in state.members { memberById[member.memberId] = member }
    var preferenceByChannel: [String: ChannelPreference] = [:]
    for preference in state.preferences { preferenceByChannel[preference.channelId] = preference }

    // Members grouped by logical ID, in catalog appearance order. Disabled playlists contribute nothing, which
    // is also how a member whose playlist row was removed stays out of the view: an absent playlist record is
    // not an enabled one.
    var memberIdsByChannel: [String: [String]] = [:]
    var appearanceOrder: [String] = []
    for member in state.members {
        guard enabledPlaylists.contains(member.playlistId) else { continue }
        let logicalId = logicalIdOf(state, member.memberId)
        if memberIdsByChannel[logicalId] == nil {
            memberIdsByChannel[logicalId] = []
            appearanceOrder.append(logicalId)
        }
        memberIdsByChannel[logicalId]?.append(member.memberId)
    }

    // An association records the user's own member order, which is what the channel's source list and metadata
    // refer to; catalog order is only the fallback for rows added later. The pass walks `appearanceOrder`
    // rather than the dictionary, because Swift's dictionary iteration order is unspecified while Dart's map
    // preserves insertion order — and both ports must pick the same association when two cover one group.
    for logicalId in appearanceOrder {
        guard var group = memberIdsByChannel[logicalId], group.count >= 2 else { continue }
        let visible = Set(group)
        for association in state.associations {
            let ordered = association.memberIds.filter { visible.contains($0) }
            guard ordered.count == group.count else { continue }
            group = ordered
            break
        }
        memberIdsByChannel[logicalId] = group
    }

    // Sources follow their member's logical channel, not their stored `channelId`. The mapping is the
    // authoritative user decision, and a row written before an association (or by an older port) may still
    // name its member ID. A source whose member is unknown, or whose member's playlist is disabled, is not
    // shown — and is not deleted, so it returns with the playlist.
    var sourcesByChannel: [String: [ChannelSourceRecord]] = [:]
    for source in state.sources {
        guard let member = memberById[source.memberId] else { continue }
        let logicalId = logicalIdOf(state, member.memberId)
        guard memberIdsByChannel[logicalId] != nil else { continue }
        sourcesByChannel[logicalId, default: []].append(source)
    }
    for (logicalId, sources) in sourcesByChannel {
        // Priority first, then the source ID, so two rows sharing a priority still order identically on every
        // platform. The tiebreak is explicit because no port promises a stable sort.
        sourcesByChannel[logicalId] = sources.sorted { left, right in
            if left.priority != right.priority { return left.priority < right.priority }
            return left.sourceId < right.sourceId
        }
    }

    var appearanceIndex: [String: Int] = [:]
    for (index, logicalId) in appearanceOrder.enumerated() { appearanceIndex[logicalId] = index }
    // Explicit tiebreak inside the comparator for the same reason: `Array.sorted` is not documented stable.
    let orderedChannels = appearanceOrder.sorted { left, right in
        let orderLeft = preferenceByChannel[left]?.userOrder
        let orderRight = preferenceByChannel[right]?.userOrder
        if orderLeft != nil || orderRight != nil {
            // An unset order is "not manually placed", so it sorts after every placed channel.
            guard let orderLeft else { return false }
            guard let orderRight else { return true }
            if orderLeft != orderRight { return orderLeft < orderRight }
        }
        return (appearanceIndex[left] ?? 0) < (appearanceIndex[right] ?? 0)
    }

    return orderedChannels.compactMap { logicalId -> LogicalChannel? in
        guard let group = memberIdsByChannel[logicalId],
              let firstId = group.first,
              let preferred = memberById[firstId] else {
            // Unreachable by construction: a group is created only while walking real members. Returning no
            // channel here instead of crashing keeps a projection total, and keeps the ports identical.
            return nil
        }
        let preference = preferenceByChannel[logicalId]
        return LogicalChannel(
            channelId: logicalId,
            displayName: preferred.displayName,
            normalizedName: preferred.normalizedName,
            logoUrl: preferred.logoUrl,
            // A user's category wins over the provider's group, because the group came from one playlist while
            // the channel may now span several.
            category: preference?.category ?? preferred.group,
            countryCode: preferred.countryCode,
            languages: preferred.languages,
            memberIds: group,
            sources: sourcesByChannel[logicalId] ?? [],
            favorite: preference?.favorite ?? false,
            hidden: preference?.hidden ?? false,
            userOrder: preference?.userOrder,
            automaticFailoverEnabled: preference?.automaticFailoverEnabled ?? true,
            // `SourcePolicy.standard` is the same declared default the Dart `const SourcePolicy()` carries;
            // naming it here keeps the fallback an explicit contract value rather than four literals.
            sourcePolicy: preference?.sourcePolicy ?? SourcePolicy.standard,
            lastSuccessfulSourceId: preference?.lastSuccessfulSourceId
        )
    }
}
