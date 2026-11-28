import 'channel_identity.dart';
import 'live_contracts.dart';

// MARK: - Unified catalog view (Task B3-D)
//
// [buildUnifiedChannels] is the single place the persisted state becomes the list a user sees. It is a
// projection, never a second source of truth: it mutates nothing, and the caller may diff it freely.
// Two consequences of that framing are asserted in `test/channel_identity_test.dart`:
//
// * A disabled playlist disappears from the view while its member and source rows stay in the state, so
//   re-enabling restores exactly what the user had.
// * A disabled *source* stays in its channel's `sources` list, because the user manages it; playback
//   eligibility is `enabled`, and that filter belongs to the recovery chain (Phase C), not to the view.

/// Builds one [LogicalChannel] per logical ID that has at least one member in an enabled playlist.
///
/// Channels are ordered by explicit `userOrder` first (ascending, unset last), then by the order their
/// preferred member appears in the catalog, so a list is stable across refreshes and never reorders itself
/// because a preference was edited for an unrelated channel.
List<LogicalChannel> buildUnifiedChannels(LiveCatalogState state) {
  final enabledPlaylists = {
    for (final PlaylistRecord playlist in state.playlists)
      if (playlist.enabled) playlist.playlistId,
  };
  final memberById = {
    for (final ChannelMember member in state.members) member.memberId: member,
  };
  final preferenceByChannel = {
    for (final ChannelPreference preference in state.preferences)
      preference.channelId: preference,
  };

  // Members grouped by logical ID, in catalog appearance order. Disabled playlists contribute nothing,
  // which is also how a member whose playlist row was removed stays out of the view: an absent playlist
  // record is not enabled.
  final memberIdsByChannel = <String, List<String>>{};
  for (final ChannelMember member in state.members) {
    if (!enabledPlaylists.contains(member.playlistId)) continue;
    memberIdsByChannel
        .putIfAbsent(
          logicalIdOf(state, member.memberId),
          () => <String>[],
        )
        .add(member.memberId);
  }
  // An association records the user's own member order, which is what the channel's source list and
  // metadata-preference refer to; catalog order is only the fallback for rows added later.
  for (final MapEntry<String, List<String>> entry in memberIdsByChannel.entries) {
    if (entry.value.length < 2) continue;
    for (final ChannelAssociation association in state.associations) {
      final ordered = association.memberIds
          .where((String id) => entry.value.contains(id))
          .toList();
      if (ordered.length != entry.value.length) continue;
      entry.value
        ..clear()
        ..addAll(ordered);
      break;
    }
  }

  // Sources follow their member's logical channel, not their stored `channelId`. The field is the
  // authoritative user decision, and a row written before an association (or by an older port) may still
  // name its member ID.
  final sourcesByChannel = <String, List<ChannelSourceRecord>>{};
  for (final ChannelSourceRecord source in state.sources) {
    final member = memberById[source.memberId];
    if (member == null) continue;
    final channelId = logicalIdOf(state, member.memberId);
    if (!memberIdsByChannel.containsKey(channelId)) continue;
    sourcesByChannel.putIfAbsent(channelId, () => <ChannelSourceRecord>[]).add(source);
  }
  for (final List<ChannelSourceRecord> sources in sourcesByChannel.values) {
    sources.sort((ChannelSourceRecord a, ChannelSourceRecord b) {
      final byPriority = a.priority.compareTo(b.priority);
      return byPriority != 0 ? byPriority : a.sourceId.compareTo(b.sourceId);
    });
  }

  final entries = memberIdsByChannel.entries.toList();
  final appearanceIndex = {
    for (var i = 0; i < entries.length; i++) entries.elementAt(i).key: i,
  };
  // Dart's List.sort is not stable, so the appearance index is part of the comparator rather than an
  // assumption about it.
  entries.sort((MapEntry<String, List<String>> a, MapEntry<String, List<String>> b) {
    final orderA = preferenceByChannel[a.key]?.userOrder;
    final orderB = preferenceByChannel[b.key]?.userOrder;
    if (orderA != null || orderB != null) {
      if (orderA == null) return 1;
      if (orderB == null) return -1;
      final byOrder = orderA.compareTo(orderB);
      if (byOrder != 0) return byOrder;
    }
    return appearanceIndex[a.key]!.compareTo(appearanceIndex[b.key]!);
  });

  return List<LogicalChannel>.unmodifiable(
    entries.map((MapEntry<String, List<String>> entry) {
      final preferred = memberById[entry.value.first]!;
      final preference = preferenceByChannel[entry.key];
      return LogicalChannel(
        channelId: entry.key,
        displayName: preferred.displayName,
        normalizedName: preferred.normalizedName,
        memberIds: List<String>.unmodifiable(entry.value),
        sources: List<ChannelSourceRecord>.unmodifiable(
          sourcesByChannel[entry.key] ?? const <ChannelSourceRecord>[],
        ),
        logoUrl: preferred.logoUrl,
        category: preference?.category ?? preferred.group,
        countryCode: preferred.countryCode,
        languages: preferred.languages,
        favorite: preference?.favorite ?? false,
        hidden: preference?.hidden ?? false,
        userOrder: preference?.userOrder,
        automaticFailoverEnabled: preference?.automaticFailoverEnabled ?? true,
        sourcePolicy: preference?.sourcePolicy ?? const SourcePolicy(),
        lastSuccessfulSourceId: preference?.lastSuccessfulSourceId,
      );
    }),
  );
}
