import 'identity_hash.dart';
import 'live_catalog.dart' show liveNameKey;
import 'live_contracts.dart';
import 'models.dart' show LiveTvChannel, faDigits;
import 'playlist_parser.dart' show canonicalStreamUrl, isSensitiveUrl, protocolHintFor;

// MARK: - Built-in catalog adapter (Task B3-D)
//
// The built-in Iran list already exists as runtime `LiveTvChannel` rows (famelack, see
// `live_catalog.dart`'s merge and `models.dart`). This adapter is the only bridge that lets those rows live
// in the multi-source catalog, and its whole job is to add nothing: no channel the provider does not state,
// no capability a player has not proven, no logo the dataset does not carry.
//
// Mirrors `Sources/Core/BuiltInLiveCatalogAdapter.swift` (B3-S) and
// `webos_app/app/js/builtin_catalog_adapter.js` (B3-J).

/// What the built-in rows contribute: members, their sources, and the untouched runtime row list.
class RegisteredBuiltInCatalog {
  const RegisteredBuiltInCatalog({
    required this.members,
    required this.sources,
    required this.channels,
  });

  final List<ChannelMember> members;
  final List<ChannelSourceRecord> sources;

  /// The runtime list the caller passed in, returned verbatim so the player keeps working from the same
  /// rows while the catalog gains its member/source records.
  final List<LiveTvChannel> channels;
}

/// Turns built-in [channels] into catalog members and sources.
///
/// Identity uses the same recipes as [registerParsedPlaylist], because a built-in row and a parsed playlist
/// row from the same provider are the same member — that is what lets a user add an external playlist that
/// re-lists IRIB 1 without the list doubling.
///
/// Deliberate choices, each of which the Swift and JavaScript ports must reproduce:
///
/// * A row without a provider ID still needs a stable one, so the name-fold becomes the provider ID under
///   the `name:` prefix. It is provider-namespaced, so it can never collide with a real ID.
/// * Rows sharing a provider ID merge into one member with gapless priorities rather than producing a
///   duplicate member.
/// * No logo is invented: the built-in dataset has none, so `logoUrl` stays null and a name+country pair is
///   scored as 75 rather than pretending to be 85.
/// * Credential-bearing addresses are refused, not stored. `RegisteredBuiltInCatalog` has no issue channel
///   (unlike the parse path), so a refused address simply disappears; the caller never sees a credential in
///   persisted text, which is the property that matters here.
RegisteredBuiltInCatalog registerBuiltInChannels({
  required List<LiveTvChannel> channels,
  required String playlistId,
  required String providerNamespace,
}) {
  final members = <ChannelMember>[];
  final sources = <ChannelSourceRecord>[];
  final memberIds = <String>{};
  final priorityByMember = <String, int>{};
  final seenByUrl = <String, Set<String>>{};

  for (final LiveTvChannel channel in channels) {
    final trimmedId = channel.nanoid.trim();
    final providerChannelId = trimmedId.isNotEmpty
        ? trimmedId
        : 'name:${liveNameKey(channel.name)}';
    final memberId = 'member:${stableKeyHash(
      '$playlistId\nprovider\n$providerNamespace\n$providerChannelId',
    )}';

    // `Set.add` is the dedup: a second Famelack row carrying the same nanoid contributes URLs to the
    // member that already exists instead of minting a duplicate.
    if (memberIds.add(memberId)) {
      members.add(
        ChannelMember(
          memberId: memberId,
          playlistId: playlistId,
          providerNamespace: providerNamespace,
          providerChannelId: providerChannelId,
          displayName: channel.name,
          normalizedName: liveNameKey(channel.name),
          ordinal: members.length,
          languages: channel.languages,
          countryCode: _country(channel.country),
          tvgId: trimmedId.isNotEmpty ? trimmedId : null,
        ),
      );
    }

    final seen = seenByUrl.putIfAbsent(memberId, () => <String>{});
    var priority = priorityByMember[memberId] ?? 0;
    for (final raw in channel.streams) {
      final canonical = canonicalStreamUrl(raw);
      if (canonical == null || !seen.add(canonical)) continue;
      if (isSensitiveUrl(canonical)) continue;
      sources.add(
        ChannelSourceRecord(
          sourceId: 'source:${stableKeyHash('$memberId\nurl\n$canonical')}',
          // Rule 4 again: a built-in row is its own channel until the user associates it.
          channelId: memberId,
          memberId: memberId,
          playlistId: playlistId,
          providerNamespace: providerNamespace,
          label: priority == 0 ? 'منبع اصلی' : 'منبع ${faDigits(priority + 1)}',
          streamUrl: canonical,
          protocolHint: protocolHintFor(canonical),
          origin: SourceOrigin.playlist,
          priority: priority,
          enabled: true,
          health: SourceHealth.unverified,
        ),
      );
      priority++;
    }
    priorityByMember[memberId] = priority;
  }

  return RegisteredBuiltInCatalog(
    members: List<ChannelMember>.unmodifiable(members),
    sources: List<ChannelSourceRecord>.unmodifiable(sources),
    channels: List<LiveTvChannel>.unmodifiable(channels),
  );
}

String? _country(String value) {
  final trimmed = value.trim().toUpperCase();
  return trimmed.isEmpty ? null : trimmed;
}
