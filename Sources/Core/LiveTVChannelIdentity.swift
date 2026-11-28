import Foundation

// MARK: - Logical channel identity (Task B3-S)
//
// Swift half of the three-port identity layer. The Dart original is
// `flutter_app/lib/core/channel_identity.dart`, the JavaScript mirror arrives in
// `webos_app/app/js/channel_identity.js`, and `Tests/live-foundation/main.swift` pins the same verdicts the Dart
// suite pins. The scoring table, the ambiguity floor and the five error codes are therefore wire-visible
// behaviour, not Swift preferences: a user who merges two rows on the Mac must see the same channel on a phone
// and on a TV, and a refusal must carry the same code on every platform.
//
// The load-bearing invariant is that similarity never decides anything. `findChannelCandidate` is a suggestion
// for the UI; a logical ID only moves when a user asks through `associateChannels`, because the whole point of
// Multi-Source is that two playlists disagreeing about a station is a fact about the playlists rather than a bug
// to hide.
//
// Deliberately dependency-free (no AVFoundation, no UI, no networking) so `Tests/live-foundation/run.sh` can
// compile it into the standalone hosted harness next to the contract types it reads.

// MARK: - Declared vocabulary

/// Why two members look like the same station, strongest evidence first. Raw values are the persisted and
/// logged names, matching the Dart `MatchEvidence` enum member-for-member.
enum MatchEvidence: String, Sendable {
    case exactProviderId
    case exactNameCountryLogo
    case exactNameCountry
    case exactNameLogo
    case exactNameOnly
}

/// Declared reasons an association request is refused. `message` is the text the Dart port throws as
/// `ArgumentError('ChannelIdentityError.<code>')` and the webOS port throws as
/// `Error('ChannelIdentityError.<code>')`, so a UI string can be keyed on the code instead of on a localized
/// sentence that would drift between ports.
enum ChannelIdentityError: Error, Equatable {
    case fewerThanTwoMembers
    case unknownMember
    case duplicateMember
    case memberAssociatedElsewhere
    case unknownPreferredLogicalChannel

    var message: String {
        switch self {
        case .fewerThanTwoMembers: return "ChannelIdentityError.fewerThanTwoMembers"
        case .unknownMember: return "ChannelIdentityError.unknownMember"
        case .duplicateMember: return "ChannelIdentityError.duplicateMember"
        case .memberAssociatedElsewhere: return "ChannelIdentityError.memberAssociatedElsewhere"
        case .unknownPreferredLogicalChannel: return "ChannelIdentityError.unknownPreferredLogicalChannel"
        }
    }
}

/// One merge suggestion. Candidates below `channelCandidateAmbiguityFloor` are reported ambiguous so the UI
/// cannot present them as an obvious merge — and a pair that contradicts itself on provider ID or country is
/// ambiguous even at the top of the table.
struct ChannelMatchCandidate: Sendable, Equatable {
    var leftMemberId: String
    var rightMemberId: String
    var score: Int
    var evidence: MatchEvidence
    var ambiguous: Bool
}

/// Candidates at or above this score are the only ones the UI may offer without a warning.
let channelCandidateAmbiguityFloor = 85

// MARK: - Field comparison

/// Trailing whitespace and a lowercase ISO code are storage noise, not a different country. An absent or blank
/// value is *unknown*, which matters twice: it cannot match, and it cannot conflict.
private func comparableCountry(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return trimmed.isEmpty ? nil : trimmed
}

/// Logos are compared as given (trimmed) and never canonicalized: `irib1.png` and `/logos/irib1.png` are two
/// different statements about provenance, and guessing between them would invent evidence.
private func comparableLogo(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func isStated(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

// MARK: - Candidate scoring

/// Suggests whether `left` and `right` are the same station, or returns nil when they share no evidence.
///
/// Provider IDs are only comparable inside one namespace: `famelack/IRIB1` and `iptv-org/IRIB1` are two
/// unrelated strings, so a cross-namespace pair falls through to the name tiers rather than scoring 90+. Two
/// IDs that disagree *within* a namespace is a contradiction, which is why it makes even an 85 ambiguous.
///
/// Names are compared as stored `normalizedName` values and nothing else. Stripping a display-name token such
/// as `(720p)` is the parser's job (`LiveTVM3UText.displayName`), applied when the row is read; this layer adds
/// no folding of its own, so the same pair either matches on every port or on none.
func findChannelCandidate(_ left: ChannelMember, _ right: ChannelMember) -> ChannelMatchCandidate? {
    if left.memberId == right.memberId { return nil }

    let namesMatch = !left.normalizedName.isEmpty && left.normalizedName == right.normalizedName
    let leftCountry = comparableCountry(left.countryCode)
    let rightCountry = comparableCountry(right.countryCode)
    let bothCountry = leftCountry != nil && rightCountry != nil
    let countryMatch = bothCountry && leftCountry == rightCountry
    let countryConflict = bothCountry && leftCountry != rightCountry
    let leftLogo = comparableLogo(left.logoUrl)
    let rightLogo = comparableLogo(right.logoUrl)
    let logoMatch = leftLogo != nil && rightLogo != nil && leftLogo == rightLogo

    let bothIds = isStated(left.providerChannelId) && isStated(right.providerChannelId)
    let namespaceMatch = left.providerNamespace == right.providerNamespace
    let exactProvider = bothIds && namespaceMatch
        && left.providerChannelId == right.providerChannelId
    // A different namespace says nothing either way, so it is neither exact evidence nor a conflict.
    let providerConflict = bothIds && namespaceMatch
        && left.providerChannelId != right.providerChannelId

    func candidate(
        _ score: Int,
        _ evidence: MatchEvidence,
        providerConflict conflict: Bool
    ) -> ChannelMatchCandidate {
        ChannelMatchCandidate(
            leftMemberId: left.memberId,
            rightMemberId: right.memberId,
            score: score,
            evidence: evidence,
            ambiguous: score < channelCandidateAmbiguityFloor || conflict || countryConflict
        )
    }

    if exactProvider {
        return candidate(countryMatch ? 95 : 90, .exactProviderId, providerConflict: false)
    }
    if !namesMatch { return nil }
    if countryMatch && logoMatch {
        return candidate(85, .exactNameCountryLogo, providerConflict: providerConflict)
    }
    if countryMatch {
        return candidate(75, .exactNameCountry, providerConflict: providerConflict)
    }
    if logoMatch {
        return candidate(70, .exactNameLogo, providerConflict: providerConflict)
    }
    return candidate(50, .exactNameOnly, providerConflict: providerConflict)
}

// MARK: - Reading membership

/// The logical channel `memberId` currently belongs to.
///
/// An unmapped member is already a channel of its own, whose canonical ID is its member ID (spec rule 4).
/// Treating a missing mapping as "no channel" would make the first merge of a freshly parsed playlist fail.
func logicalIdOf(_ state: LiveCatalogState, _ memberId: String) -> String {
    state.logicalIdByMemberId[memberId] ?? memberId
}

/// Members of one logical channel, in the order the user's association recorded, falling back to catalog order.
/// Members whose playlist is disabled are still counted here: the association is user data and must survive a
/// disable/enable round trip, even though `buildUnifiedChannels` hides the channel in the meantime.
func membersOfLogicalChannel(_ state: LiveCatalogState, _ logicalChannelId: String) -> [String] {
    for association in state.associations {
        let recorded = association.memberIds.filter { logicalIdOf(state, $0) == logicalChannelId }
        if recorded.count > 1 { return recorded }
    }
    return state.members
        .filter { logicalIdOf(state, $0.memberId) == logicalChannelId }
        .map { $0.memberId }
}

private func require(_ condition: Bool, _ code: ChannelIdentityError) throws {
    if condition { return }
    throw code
}

/// Re-parents a source without touching its identity, priority or history.
///
/// A value copy rather than a field-by-field rebuild: `ChannelSourceRecord` is a struct, so this cannot
/// silently drop a field the way a hand-written initializer can when the contract grows. Only `channelId`
/// changes, which is the whole point — an association moves ownership and nothing else.
private func moveSource(_ source: ChannelSourceRecord, to channelId: String) -> ChannelSourceRecord {
    var moved = source
    moved.channelId = channelId
    return moved
}

// MARK: - Association

/// Joins `memberIds` into one logical channel owned by `preferredLogicalId`.
///
/// Validation is complete before anything is built, so a refused request can never leave a half-applied
/// association behind. Only logical ownership moves: member IDs, source IDs, priorities, health, playback
/// history and preferences are carried over untouched, which is what makes an accidental merge reversible with
/// `separateChannel`.
func associateChannels(
    _ state: LiveCatalogState,
    memberIds: [String],
    preferredLogicalId: String
) throws -> LiveCatalogState {
    // Counted before deduplication on purpose: "associate these two rows" where the caller repeated one row is
    // the caller's bug, and answering it by silently treating it as a single member would hide it.
    try require(memberIds.count >= 2, .fewerThanTwoMembers)
    try require(Set(memberIds).count == memberIds.count, .duplicateMember)
    let known = Set(state.members.map { $0.memberId })
    try require(memberIds.allSatisfy { known.contains($0) }, .unknownMember)
    // The preferred channel is the row the user is acting on; if that is gone, nothing below can be
    // interpreted, so this check comes before the per-member conflict loop.
    try require(state.logicalIdByMemberId[preferredLogicalId] != nil, .unknownPreferredLogicalChannel)
    // A member already inside another multi-member channel would have to be taken from it without the user
    // deciding that; a member mapped to itself is unassociated and free to join.
    for memberId in memberIds {
        let current = logicalIdOf(state, memberId)
        if current == preferredLogicalId { continue }
        try require(membersOfLogicalChannel(state, current).count < 2, .memberAssociatedElsewhere)
    }

    let selected = Set(memberIds)
    let kept = membersOfLogicalChannel(state, preferredLogicalId).filter { !selected.contains($0) }
    let keptSet = Set(kept)
    // Catalog order for the members already in the channel, then the newcomers in the order the user gave.
    var combined = state.members
        .map { $0.memberId }
        .filter { keptSet.contains($0) || selected.contains($0) }
        .filter { logicalIdOf(state, $0) == preferredLogicalId }
    combined.append(contentsOf: memberIds.filter { logicalIdOf(state, $0) != preferredLogicalId })

    var logicalIdByMemberId = state.logicalIdByMemberId
    for memberId in combined { logicalIdByMemberId[memberId] = preferredLogicalId }
    let combinedSet = Set(combined)

    return LiveCatalogState(
        schemaVersion: state.schemaVersion,
        playlists: state.playlists,
        members: state.members,
        sources: state.sources.map { source in
            selected.contains(source.memberId) ? moveSource(source, to: preferredLogicalId) : source
        },
        associations: state.associations
            .filter { association in !association.memberIds.contains { combinedSet.contains($0) } }
            + [ChannelAssociation(memberIds: combined)],
        preferences: state.preferences,
        recentWatches: state.recentWatches,
        logicalIdByMemberId: logicalIdByMemberId
    )
}

/// Takes one member out of its channel and gives it the canonical logical ID (its own member ID).
///
/// The other members keep their channel, so splitting a three-way merge is one user action rather than a
/// rebuild. Preferences stay where they were: the leaving branch inherits nothing, and the settings it had
/// before it joined are still keyed on its own member ID, which is why a merge followed by a split restores
/// what the user had.
func separateChannel(_ state: LiveCatalogState, memberId: String) throws -> LiveCatalogState {
    let known = Set(state.members.map { $0.memberId })
    try require(known.contains(memberId), .unknownMember)
    let current = logicalIdOf(state, memberId)
    let group = membersOfLogicalChannel(state, current)
    try require(group.count >= 2, .fewerThanTwoMembers)

    let remaining = group.filter { $0 != memberId }
    var logicalIdByMemberId = state.logicalIdByMemberId
    logicalIdByMemberId[memberId] = memberId

    return LiveCatalogState(
        schemaVersion: state.schemaVersion,
        playlists: state.playlists,
        members: state.members,
        sources: state.sources.map { source in
            source.memberId == memberId ? moveSource(source, to: memberId) : source
        },
        // Two members that were merged only with each other leave nothing to record; three leave a pair that is
        // still an explicit user statement and must survive.
        associations: state.associations
            .filter { association in !association.memberIds.contains(memberId) }
            + (remaining.count >= 2 ? [ChannelAssociation(memberIds: remaining)] : []),
        preferences: state.preferences,
        recentWatches: state.recentWatches,
        logicalIdByMemberId: logicalIdByMemberId
    )
}
