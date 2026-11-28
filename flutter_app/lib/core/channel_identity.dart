import 'package:flutter/foundation.dart';

import 'live_contracts.dart';

// MARK: - Logical channel identity (Task B3-D)
//
// This file owns the only two operations that can change which members one
// channel is: [associateChannels] and [separateChannel]. Everything else in the
// multi-source feature reads the result. The rules come from
// `docs/superpowers/plans/2026-11-25-multi-source-subtitles.md:1441-1543` and are mirrored by
// `Sources/Core/LiveTVChannelIdentity.swift` (B3-S) and `webos_app/app/js/channel_identity.js` (B3-J), so
// the scoring table, the ambiguity floor and the five error codes are wire-visible behaviour on three
// platforms rather than Dart preferences.
//
// The load-bearing invariant is that similarity never decides anything. [findChannelCandidate] is a
// suggestion for the UI; a logical ID only moves when a user asks, because the whole point of Multi-Source is
// that two playlists disagreeing about a station is a fact about the playlists, not a bug to hide.

/// Why two members look like the same station, strongest evidence first.
enum MatchEvidence {
  exactProviderId,
  exactNameCountryLogo,
  exactNameCountry,
  exactNameLogo,
  exactNameOnly,
}

/// Declared reasons an association request is refused. The message is
/// `ChannelIdentityError.<code>`, which is what the Swift and JavaScript ports throw too, so a UI string can
/// be keyed on the code instead of on a localized sentence.
enum ChannelIdentityErrorCode {
  fewerThanTwoMembers,
  unknownMember,
  duplicateMember,
  memberAssociatedElsewhere,
  unknownPreferredLogicalChannel,
}

/// One merge suggestion. Scores below [channelCandidateAmbiguityFloor] are reported as ambiguous so the UI
/// cannot present them as an obvious merge.
@immutable
class ChannelMatchCandidate {
  const ChannelMatchCandidate({
    required this.leftMemberId,
    required this.rightMemberId,
    required this.score,
    required this.evidence,
    required this.ambiguous,
  });

  final String leftMemberId;
  final String rightMemberId;
  final int score;
  final MatchEvidence evidence;
  final bool ambiguous;
}

/// Candidates at or above this score are the only ones the UI may offer without a warning.
const int channelCandidateAmbiguityFloor = 85;

ChannelMatchCandidate? _candidate(
  ChannelMember left,
  ChannelMember right,
  int score,
  MatchEvidence evidence, {
  required bool providerConflict,
  required bool countryConflict,
}) {
  return ChannelMatchCandidate(
    leftMemberId: left.memberId,
    rightMemberId: right.memberId,
    score: score,
    evidence: evidence,
    ambiguous: score < channelCandidateAmbiguityFloor || providerConflict || countryConflict,
  );
}

String? _country(String? value) {
  if (value == null) return null;
  final trimmed = value.trim().toUpperCase();
  return trimmed.isEmpty ? null : trimmed;
}

String? _logo(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _stated(String value) => value.trim().isNotEmpty;

/// Suggests whether [left] and [right] are the same station, or returns null when they share no evidence.
///
/// Provider IDs are only comparable inside one namespace: `famelack/IRIB1` and `iptv-org/IRIB1` are two
/// unrelated strings, so a cross-namespace pair falls through to the name tiers instead of scoring 90+. Two
/// IDs that disagree *within* a namespace is a contradiction, which is why it makes even an 85 ambiguous.
ChannelMatchCandidate? findChannelCandidate(ChannelMember left, ChannelMember right) {
  if (left.memberId == right.memberId) return null;

  final namesMatch = left.normalizedName.isNotEmpty &&
      left.normalizedName == right.normalizedName;
  final leftCountry = _country(left.countryCode);
  final rightCountry = _country(right.countryCode);
  final bothCountry = leftCountry != null && rightCountry != null;
  final countryMatch = bothCountry && leftCountry == rightCountry;
  final countryConflict = bothCountry && leftCountry != rightCountry;
  final leftLogo = _logo(left.logoUrl);
  final rightLogo = _logo(right.logoUrl);
  final logoMatch =
      leftLogo != null && rightLogo != null && leftLogo == rightLogo;

  final bothIds = _stated(left.providerChannelId) && _stated(right.providerChannelId);
  final namespaceMatch = left.providerNamespace == right.providerNamespace;
  final exactProvider =
      bothIds && namespaceMatch && left.providerChannelId == right.providerChannelId;
  // A different namespace says nothing either way, so it is neither exact evidence nor a conflict.
  final providerConflict =
      bothIds && namespaceMatch && left.providerChannelId != right.providerChannelId;

  if (exactProvider) {
    return _candidate(
      left,
      right,
      countryMatch ? 95 : 90,
      MatchEvidence.exactProviderId,
      providerConflict: false,
      countryConflict: countryConflict,
    );
  }
  if (!namesMatch) return null;
  if (countryMatch && logoMatch) {
    return _candidate(left, right, 85, MatchEvidence.exactNameCountryLogo,
        providerConflict: providerConflict, countryConflict: false);
  }
  if (countryMatch) {
    return _candidate(left, right, 75, MatchEvidence.exactNameCountry,
        providerConflict: providerConflict, countryConflict: false);
  }
  if (logoMatch) {
    return _candidate(left, right, 70, MatchEvidence.exactNameLogo,
        providerConflict: providerConflict, countryConflict: countryConflict);
  }
  return _candidate(left, right, 50, MatchEvidence.exactNameOnly,
      providerConflict: providerConflict, countryConflict: countryConflict);
}

/// The logical channel [memberId] currently belongs to.
///
/// An unmapped member is already a channel of its own, whose canonical ID is its member ID (spec rule 4).
/// Treating a missing mapping as "no channel" would make the first merge of a freshly parsed playlist fail.
String logicalIdOf(LiveCatalogState state, String memberId) =>
    state.logicalIdByMemberId[memberId] ?? memberId;

/// Members of one logical channel, in the order the user's association recorded, falling back to catalog
/// order. Members whose playlist is disabled are still counted here: the association is user data and must
/// survive a disable/enable round trip.
List<String> membersOfLogicalChannel(
  LiveCatalogState state,
  String logicalChannelId,
) {
  for (final association in state.associations) {
    final recorded = association.memberIds
        .where((String id) => logicalIdOf(state, id) == logicalChannelId)
        .toList();
    if (recorded.length > 1) return recorded;
  }
  return state.members
      .where((ChannelMember m) => logicalIdOf(state, m.memberId) == logicalChannelId)
      .map((ChannelMember m) => m.memberId)
      .toList();
}

void _require(bool condition, ChannelIdentityErrorCode code) {
  if (condition) return;
  throw ArgumentError('ChannelIdentityError.${code.name}');
}

/// Joins [memberIds] into one logical channel owned by [preferredLogicalId].
///
/// Only logical ownership moves: member IDs, source IDs, priorities, health, playback history and
/// preferences are carried over untouched, which is what makes an accidental merge reversible with
/// [separateChannel]. Validation is complete before anything is built, so a refused request can never leave
/// a half-applied association behind.
LiveCatalogState associateChannels({
  required LiveCatalogState state,
  required List<String> memberIds,
  required String preferredLogicalId,
}) {
  _require(memberIds.length >= 2, ChannelIdentityErrorCode.fewerThanTwoMembers);
  _require(
    memberIds.toSet().length == memberIds.length,
    ChannelIdentityErrorCode.duplicateMember,
  );
  final known = {for (final m in state.members) m.memberId};
  _require(
    memberIds.every((String id) => known.contains(id)),
    ChannelIdentityErrorCode.unknownMember,
  );
  // The preferred channel is the row the user is acting on; if that is gone, nothing below can be
  // interpreted, so this check comes before per-member conflicts.
  _require(
    state.logicalIdByMemberId.containsKey(preferredLogicalId),
    ChannelIdentityErrorCode.unknownPreferredLogicalChannel,
  );
  // A member already inside another multi-member channel would have to be taken from it without the user
  // deciding that; a member mapped to itself is unassociated and free to join.
  for (final id in memberIds) {
    final current = logicalIdOf(state, id);
    if (current == preferredLogicalId) continue;
    final size = membersOfLogicalChannel(state, current).length;
    _require(size < 2, ChannelIdentityErrorCode.memberAssociatedElsewhere);
  }

  final selected = memberIds.toSet();
  final kept = membersOfLogicalChannel(state, preferredLogicalId)
      .where((String id) => !selected.contains(id))
      .toList();
  final combined = <String>[
    ...state.members
        .map((ChannelMember m) => m.memberId)
        .where((String id) => kept.contains(id) || selected.contains(id))
        .where((String id) => logicalIdOf(state, id) == preferredLogicalId),
    ...memberIds.where((String id) => logicalIdOf(state, id) != preferredLogicalId),
  ];

  final logicalIdByMemberId = Map<String, String>.of(state.logicalIdByMemberId);
  for (final id in combined) {
    logicalIdByMemberId[id] = preferredLogicalId;
  }

  return LiveCatalogState(
    schemaVersion: state.schemaVersion,
    playlists: state.playlists,
    members: state.members,
    sources: state.sources
        .map(
          (ChannelSourceRecord source) => selected.contains(source.memberId)
              ? _moveSource(source, preferredLogicalId)
              : source,
        )
        .toList(),
    associations: [
      ...state.associations.where(
        (ChannelAssociation a) => !a.memberIds.any((String id) => combined.contains(id)),
      ),
      ChannelAssociation(memberIds: combined),
    ],
    preferences: state.preferences,
    recentWatches: state.recentWatches,
    logicalIdByMemberId: logicalIdByMemberId,
  );
}

/// Takes one member out of its channel and gives it the canonical logical ID (its own member ID).
///
/// The other members keep their channel, so splitting a three-way merge is one user action rather than a
/// rebuild. Preferences stay where they were: the leaving branch inherits nothing, and the settings it had
/// before it joined are still keyed on its own member ID, which is why a merge followed by a split restores
/// what the user had.
LiveCatalogState separateChannel({
  required LiveCatalogState state,
  required String memberId,
}) {
  final known = {for (final m in state.members) m.memberId};
  _require(known.contains(memberId), ChannelIdentityErrorCode.unknownMember);
  final current = logicalIdOf(state, memberId);
  final group = membersOfLogicalChannel(state, current);
  _require(group.length >= 2, ChannelIdentityErrorCode.fewerThanTwoMembers);

  final remaining = group.where((String id) => id != memberId).toList();
  final logicalIdByMemberId = Map<String, String>.of(state.logicalIdByMemberId);
  logicalIdByMemberId[memberId] = memberId;

  return LiveCatalogState(
    schemaVersion: state.schemaVersion,
    playlists: state.playlists,
    members: state.members,
    sources: state.sources
        .map(
          (ChannelSourceRecord source) => source.memberId == memberId
              ? _moveSource(source, memberId)
              : source,
        )
        .toList(),
    associations: [
      ...state.associations.where(
        (ChannelAssociation a) => !a.memberIds.contains(memberId),
      ),
      if (remaining.length >= 2) ChannelAssociation(memberIds: remaining),
    ],
    preferences: state.preferences,
    recentWatches: state.recentWatches,
    logicalIdByMemberId: logicalIdByMemberId,
  );
}

/// Re-parents a source without touching its identity, priority or history.
ChannelSourceRecord _moveSource(ChannelSourceRecord source, String channelId) {
  return ChannelSourceRecord(
    sourceId: source.sourceId,
    channelId: channelId,
    memberId: source.memberId,
    playlistId: source.playlistId,
    providerNamespace: source.providerNamespace,
    label: source.label,
    protocolHint: source.protocolHint,
    rendererCapability: source.rendererCapability,
    origin: source.origin,
    priority: source.priority,
    enabled: source.enabled,
    health: source.health,
    streamUrl: source.streamUrl,
    streamSecretRef: source.streamSecretRef,
    lastSuccessfulPlaybackAt: source.lastSuccessfulPlaybackAt,
    lastFailedPlaybackAt: source.lastFailedPlaybackAt,
    lastErrorCode: source.lastErrorCode,
  );
}
