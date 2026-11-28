import 'identity_hash.dart';
import 'live_catalog.dart' show liveNameKey;
import 'live_contracts.dart';
import 'models.dart' show faDigits;
import 'playlist_parser.dart';

/// What one parsed playlist contributes to the catalog: members, their sources, and issues.
///
/// The result is *proposed* state, not persisted state. Merging it with what the user already has
/// (retaining health, enabled flags, associations and preferences) is Task B4-D, which is why this
/// object carries no revision, no logical IDs and no `LiveCatalogState`.
class SourceRegistryResult {
  const SourceRegistryResult({
    required this.members,
    required this.sources,
    required this.issues,
  });

  final List<ChannelMember> members;
  final List<ChannelSourceRecord> sources;
  final List<CatalogIssue> issues;
}

/// Turns a parse result into catalog members and sources.
///
/// Identity follows the specification's rules exactly, because these IDs are what survive a refresh:
///
/// * `memberId = "member:" + stableKeyHash(playlistId + "\nprovider\n" + providerNamespace + "\n" +
///   providerChannelId)` (rule 1), so the same station name in two playlists, or under two
///   namespaces, stays two members rather than merging into one the user did not choose.
/// * `sourceId = "source:" + stableKeyHash(memberId + "\nurl\n" + canonicalStreamUrl)` (rule 3), so
///   an address that merely changes spelling — uppercase host, default port — keeps its identity,
///   while a real address change produces a new ID and the old one's history stops applying.
/// * `channelId` is set to the member ID (rule 4: a new logical channel uses its member ID). No
///   association is inferred here; cross-playlist merging needs explicit user action in B4.
///
/// Nothing in this function claims a stream works. Every source starts `unverified` with
/// `rendererCapability` at `Not Yet Verified` and no playback timestamps, because parsing a playlist
/// is not evidence about a decoder.
SourceRegistryResult registerParsedPlaylist({
  required PlaylistParseResult parsed,
  required String playlistId,
  required String providerNamespace,
}) {
  final members = <ChannelMember>[];
  final sources = <ChannelSourceRecord>[];
  final issues = <CatalogIssue>[];

  for (final channel in parsed.channels) {
    final memberId = 'member:' +
        stableKeyHash(
          '$playlistId\nprovider\n$providerNamespace\n${channel.providerChannelId}',
        );
    final ordinal = members.length;
    members.add(
      ChannelMember(
        memberId: memberId,
        playlistId: playlistId,
        providerNamespace: providerNamespace,
        providerChannelId: channel.providerChannelId,
        displayName: channel.displayName,
        normalizedName: liveNameKey(channel.displayName),
        ordinal: ordinal,
        logoUrl: channel.logoUrl,
        group: channel.group,
        countryCode: channel.countryCode,
        languages: channel.languages,
        tvgId: channel.tvgId,
      ),
    );

    final seen = <String>{};
    var priority = 0;
    for (final raw in channel.streamUrls) {
      final canonical = canonicalStreamUrl(raw);
      if (canonical == null) {
        // Defensive rather than redundant: the parser already canonicalized, so reaching here means
        // canonicalization stopped being idempotent, and that is a bug worth an visible issue
        // rather than a silently missing source.
        issues.add(CatalogIssue(
          code: 'invalidUrl',
          message: 'member $memberId offered an address that is not canonicalizable: line '
              '${channel.line}',
          line: channel.line,
        ));
        continue;
      }
      // Two spellings of one origin are one source. Deduplicating is not an error, so it reports
      // nothing: the ceilings in the parser own the `limitExceeded` cases.
      if (!seen.add(canonical)) continue;

      if (isSensitiveUrl(canonical)) {
        // No platform has a verified secret store yet, and the contract forbids persisting a
        // credential-bearing address as plaintext. Refusing with this code is the honest outcome:
        // once a secret store is verified, the same row becomes a `streamSecretRef` instead.
        issues.add(CatalogIssue(
          code: 'secretStorageUnavailable',
          message: 'a stream address for ${channel.displayName} carries a credential and was not '
              'stored, because no verified secret store exists on this platform',
          line: channel.line,
        ));
        continue;
      }

      sources.add(
        ChannelSourceRecord(
          sourceId: 'source:' +
              stableKeyHash('$memberId\nurl\n$canonical'),
          // Rule 4: a new logical channel uses its member ID until the user associates it.
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
  }

  return SourceRegistryResult(
    members: List<ChannelMember>.unmodifiable(members),
    sources: List<ChannelSourceRecord>.unmodifiable(sources),
    issues: List<CatalogIssue>.unmodifiable(issues),
  );
}
