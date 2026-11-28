import 'package:ccloud/core/builtin_catalog_adapter.dart';
import 'package:ccloud/core/channel_identity.dart';
import 'package:ccloud/core/identity_hash.dart';
import 'package:ccloud/core/live_catalog.dart' show liveNameKey;
import 'package:ccloud/core/live_contracts.dart';
import 'package:ccloud/core/models.dart' show LiveTvChannel;
import 'package:ccloud/core/playlist_parser.dart';
import 'package:ccloud/core/source_registry.dart';
import 'package:ccloud/core/unified_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

// Task B3-D. These are the eleven assertion groups the plan names at
// `docs/superpowers/plans/2026-11-25-multi-source-subtitles.md:1527-1538`, and they are the contract
// the Swift (`Sources/Core/LiveTVChannelIdentity.swift`, task B3-S) and webOS
// (`webos_app/app/js/channel_identity.js`, task B3-J) mirrors must satisfy too. Two properties carry more
// weight here than any single expectation:
//
// * **Nothing merges on its own.** A candidate is a suggestion for the UI; only `associateChannels` moves a
//   logical ID. Every group that produces a candidate therefore also asserts the state still separates it.
// * **Every input state is unmodifiable.** The lists and maps below are built with `List.unmodifiable` /
//   `Map.unmodifiable`, so an implementation that validated lazily and mutated in place would fail with
//   `UnsupportedError` instead of the declared `ChannelIdentityError.*`. "Validation completes before any
//   state mutation" is only a comment until something can observe the difference; this is that something.
final DateTime _at = DateTime.utc(2026, 11, 28, 12, 0, 0);

/// One playlist row, enabled unless a test says otherwise.
PlaylistRecord _playlist(String id, {bool enabled = true, String? name}) =>
    PlaylistRecord(
      playlistId: id,
      name: name ?? id,
      sourceType: PlaylistSourceType.builtIn,
      locationRef: 'builtin:$id',
      enabled: enabled,
      createdAt: _at,
    );

ChannelMember _member({
  required String memberId,
  String playlistId = 'playlist:a',
  String namespace = 'famelack',
  String providerId = '',
  required String name,
  String? country,
  String? logo,
  String? group,
  int ordinal = 0,
}) => ChannelMember(
  memberId: memberId,
  playlistId: playlistId,
  providerNamespace: namespace,
  providerChannelId: providerId,
  displayName: name,
  normalizedName: liveNameKey(name),
  ordinal: ordinal,
  logoUrl: logo,
  group: group,
  countryCode: country,
);

ChannelSourceRecord _source({
  required String sourceId,
  required String memberId,
  String? channelId,
  String playlistId = 'playlist:a',
  String namespace = 'famelack',
  String url = 'https://cdn.example/a.m3u8',
  int priority = 0,
  bool enabled = true,
  SourceHealth health = SourceHealth.unverified,
}) => ChannelSourceRecord(
  sourceId: sourceId,
  channelId: channelId ?? memberId,
  memberId: memberId,
  playlistId: playlistId,
  providerNamespace: namespace,
  label: priority == 0 ? 'منبع اصلی' : 'منبع $priority',
  protocolHint: 'hls',
  origin: SourceOrigin.playlist,
  priority: priority,
  enabled: enabled,
  health: health,
  streamUrl: url,
);

/// Builds a state whose collections reject in-place mutation.
LiveCatalogState _state({
  List<PlaylistRecord> playlists = const [],
  List<ChannelMember> members = const [],
  List<ChannelSourceRecord> sources = const [],
  List<ChannelAssociation> associations = const [],
  List<ChannelPreference> preferences = const [],
  Map<String, String> logicalIdByMemberId = const {},
}) => LiveCatalogState(
  playlists: List<PlaylistRecord>.unmodifiable(playlists),
  members: List<ChannelMember>.unmodifiable(members),
  sources: List<ChannelSourceRecord>.unmodifiable(sources),
  associations: List<ChannelAssociation>.unmodifiable(associations),
  preferences: List<ChannelPreference>.unmodifiable(preferences),
  logicalIdByMemberId: Map<String, String>.unmodifiable(logicalIdByMemberId),
);

Matcher _identityError(String code) => isA<ArgumentError>().having(
  (ArgumentError error) => error.message,
  'message',
  'ChannelIdentityError.$code',
);

void main() {
  group('candidate scoring', () {
    test('the six documented scores are the whole ladder, in order', () {
      final bothCountry = findChannelCandidate(
        _member(
          memberId: 'member:1',
          providerId: 'IRIB1',
          name: 'IRIB 1',
          country: 'IR',
        ),
        _member(
          memberId: 'member:2',
          playlistId: 'playlist:b',
          providerId: 'IRIB1',
          name: 'تلویزیون جمهوری اسلامی ۱',
          country: 'ir',
        ),
      );
      expect(bothCountry, isNotNull);
      expect(bothCountry!.score, 95);
      expect(bothCountry.evidence, MatchEvidence.exactProviderId);
      expect(bothCountry.ambiguous, isFalse);

      final providerOnly = findChannelCandidate(
        _member(memberId: 'member:1', providerId: 'IRIB1', name: 'IRIB 1'),
        _member(
          memberId: 'member:2',
          playlistId: 'playlist:b',
          providerId: 'IRIB1',
          name: 'IRIB One',
        ),
      );
      expect(providerOnly!.score, 90, reason: 'a provider match without a country is still exact');
      expect(providerOnly.evidence, MatchEvidence.exactProviderId);
      expect(providerOnly.ambiguous, isFalse);

      final nameCountryLogo = findChannelCandidate(
        _member(
          memberId: 'member:3',
          name: 'Press TV',
          country: 'IR',
          logo: 'https://img.example/press.png',
        ),
        _member(
          memberId: 'member:4',
          playlistId: 'playlist:b',
          name: 'Press TV',
          country: 'IR',
          logo: 'https://img.example/press.png',
        ),
      );
      expect(nameCountryLogo!.score, 85);
      expect(nameCountryLogo.evidence, MatchEvidence.exactNameCountryLogo);
      expect(nameCountryLogo.ambiguous, isFalse);

      final nameCountry = findChannelCandidate(
        _member(memberId: 'member:5', name: 'Jam Jam', country: 'IR'),
        _member(
          memberId: 'member:6',
          playlistId: 'playlist:b',
          name: 'Jam Jam',
          country: 'IR',
        ),
      );
      expect(nameCountry!.score, 75);
      expect(nameCountry.evidence, MatchEvidence.exactNameCountry);
      expect(nameCountry.ambiguous, isTrue, reason: 'the documented ambiguity floor is 85');

      final nameLogo = findChannelCandidate(
        _member(memberId: 'member:7', name: 'Namayesh', logo: 'https://i/n.png'),
        _member(
          memberId: 'member:8',
          playlistId: 'playlist:b',
          name: 'Namayesh',
          logo: 'https://i/n.png',
        ),
      );
      expect(nameLogo!.score, 70);
      expect(nameLogo.evidence, MatchEvidence.exactNameLogo);

      final nameOnly = findChannelCandidate(
        _member(memberId: 'member:9', name: 'Ahvaz TV'),
        _member(memberId: 'member:10', playlistId: 'playlist:b', name: 'Ahvaz TV'),
      );
      expect(nameOnly!.score, 50);
      expect(nameOnly.evidence, MatchEvidence.exactNameOnly);
    });

    test('the fold that produces a name match is the shared script fold, not a raw compare', () {
      // Arabic ك versus Persian ک, and a Persian digit versus an ASCII one: both are differences the two
      // live datasets actually contain, and both are folded by the shared `liveNameKey`.
      final letterVariant = findChannelCandidate(
        _member(memberId: 'member:fold1', name: 'كورد TV'),
        _member(memberId: 'member:fold2', playlistId: 'playlist:b', name: 'کورد TV'),
      );
      expect(letterVariant, isNotNull, reason: 'the two letter spellings are one station');
      expect(letterVariant!.score, 50);

      final persianDigit = findChannelCandidate(
        _member(memberId: 'member:fold3', name: 'شما ۲'),
        _member(memberId: 'member:fold4', playlistId: 'playlist:b', name: 'شما 2'),
      );
      expect(persianDigit, isNotNull);

      final unrelated = findChannelCandidate(
        _member(memberId: 'member:fold5', name: 'IRIB 1'),
        _member(memberId: 'member:fold6', playlistId: 'playlist:b', name: 'Press TV'),
      );
      expect(unrelated, isNull, reason: 'no shared evidence means no candidate at all');
    });

    test('stripping display-name noise is the parser\'s job, and identity relies on it', () {
      // Separation of concerns, asserted instead of assumed. `m3uDisplayName` drops ` (720p)` while the
      // playlist is being read; `liveNameKey` only folds script, case and digits. So two members whose
      // stored names still differ by the token must not pair, while the same row arriving through the
      // real parser must pair with the clean built-in name. A second fold inside the identity layer would
      // silently merge rows the caller believes are distinct, which is exactly what Phase B forbids.
      final rawToken = findChannelCandidate(
        _member(memberId: 'member:noise1', name: 'Press TV (720p)'),
        _member(memberId: 'member:noise2', playlistId: 'playlist:b', name: 'Press TV'),
      );
      expect(rawToken, isNull, reason: 'the identity layer invents no folding the parser did not perform');

      final parsedMember = registerParsedPlaylist(
        parsed: parsePlaylist(
          playlistId: 'playlist:b',
          text: '#EXTM3U\n'
              '#EXTINF:-1 tvg-id="PressTV.ir" group-title="News",Press TV (720p)\n'
              'https://cdn.example/p.m3u8\n',
        ),
        playlistId: 'playlist:b',
        providerNamespace: 'iptv-org',
      ).members.single;
      expect(parsedMember.displayName, 'Press TV');
      final candidate = findChannelCandidate(
        _member(memberId: 'member:noise3', name: 'Press TV'),
        parsedMember,
      );
      expect(candidate, isNotNull, reason: 'through the parser the two rows are one station');
      expect(candidate!.score, 50);
      expect(candidate.evidence, MatchEvidence.exactNameOnly);
    });

    test('a member is never a candidate for itself', () {
      final one = _member(memberId: 'member:self', providerId: 'X', name: 'X');
      expect(findChannelCandidate(one, one), isNull);
    });
  });

  group('provider evidence', () {
    test('identical namespaced provider IDs in different playlists stay two logical channels', () {
      final left = _member(
        memberId: 'member:p1',
        playlistId: 'playlist:a',
        providerId: 'GBTV',
        name: 'GEM TV',
        country: 'IR',
      );
      final right = _member(
        memberId: 'member:p2',
        playlistId: 'playlist:b',
        providerId: 'GBTV',
        name: 'GEM TV',
        country: 'IR',
      );
      final state = _state(
        playlists: [_playlist('playlist:a'), _playlist('playlist:b')],
        members: [left, right],
        sources: [
          _source(sourceId: 'source:p1', memberId: 'member:p1'),
          _source(sourceId: 'source:p2', memberId: 'member:p2', playlistId: 'playlist:b'),
        ],
        logicalIdByMemberId: const {
          'member:p1': 'member:p1',
          'member:p2': 'member:p2',
        },
      );
      final candidate = findChannelCandidate(left, right);
      expect(candidate!.evidence, MatchEvidence.exactProviderId);
      // The candidate exists so the UI can offer the merge; nothing here may take that as consent.
      final channels = buildUnifiedChannels(state);
      expect(channels.length, 2);
      expect(channels.map((LogicalChannel c) => c.channelId).toSet(), {
        'member:p1',
        'member:p2',
      });
      expect(channels.expand((LogicalChannel c) => c.memberIds).length, 2);
    });

    test('equal raw provider IDs in different namespaces are not exact-provider evidence', () {
      final candidate = findChannelCandidate(
        _member(
          memberId: 'member:n1',
          namespace: 'famelack',
          providerId: 'IRIB1',
          name: 'IRIB 1',
          country: 'IR',
          logo: 'https://i/1.png',
        ),
        _member(
          memberId: 'member:n2',
          playlistId: 'playlist:b',
          namespace: 'iptv-org',
          providerId: 'IRIB1',
          name: 'IRIB 1',
          country: 'IR',
          logo: 'https://i/1.png',
        ),
      );
      expect(candidate, isNotNull);
      expect(
        candidate!.evidence,
        isNot(MatchEvidence.exactProviderId),
        reason: 'an ID is only meaningful inside the namespace that minted it',
      );
      expect(candidate.score, 85);
      expect(candidate.ambiguous, isFalse);
    });

    test('a missing provider ID never produces an exact-provider candidate', () {
      final candidate = findChannelCandidate(
        _member(memberId: 'member:blank1', providerId: '', name: 'Solo TV'),
        _member(memberId: 'member:blank2', playlistId: 'playlist:b', providerId: '', name: 'Solo TV'),
      );
      expect(candidate, isNotNull, reason: 'identical names without provider IDs still yield a candidate');
      expect(candidate!.evidence, MatchEvidence.exactNameOnly);
      expect(candidate.score, 50);
      expect(candidate.ambiguous, isTrue);
    });

    test('conflicting provider IDs produce an ambiguous candidate and never merge', () {
      final left = _member(
        memberId: 'member:c1',
        playlistId: 'playlist:a',
        providerId: 'PRESS-A',
        name: 'Press TV',
        country: 'IR',
        logo: 'https://i/p.png',
      );
      final right = _member(
        memberId: 'member:c2',
        playlistId: 'playlist:b',
        providerId: 'PRESS-B',
        name: 'Press TV',
        country: 'IR',
        logo: 'https://i/p.png',
      );
      final candidate = findChannelCandidate(left, right);
      expect(candidate, isNotNull);
      expect(candidate!.ambiguous, isTrue, reason: 'two stated IDs that disagree is a conflict');
      final channels = buildUnifiedChannels(
        _state(
          playlists: [_playlist('playlist:a'), _playlist('playlist:b')],
          members: [left, right],
          logicalIdByMemberId: const {
            'member:c1': 'member:c1',
            'member:c2': 'member:c2',
          },
        ),
      );
      expect(channels.length, 2, reason: 'an ambiguous candidate must not collapse the rows');
    });

    test('conflicting countries make even an exact provider match ambiguous', () {
      final candidate = findChannelCandidate(
        _member(memberId: 'member:cc1', providerId: 'SAME', name: 'Same', country: 'IR'),
        _member(memberId: 'member:cc2', providerId: 'SAME', name: 'Same', country: 'US'),
      );
      expect(candidate!.score, 90);
      expect(candidate.evidence, MatchEvidence.exactProviderId);
      expect(candidate.ambiguous, isTrue);
    });
  });

  group('association', () {
    LiveCatalogState twoChannels() => _state(
      playlists: [_playlist('playlist:a'), _playlist('playlist:b', name: 'My list')],
      members: [
        _member(
          memberId: 'member:m1',
          playlistId: 'playlist:a',
          name: 'IRIB 1',
          group: 'سراسری',
        ),
        _member(memberId: 'member:m2', playlistId: 'playlist:b', name: 'IRIB One'),
        _member(memberId: 'member:m3', playlistId: 'playlist:b', name: 'IRIB Two'),
      ],
      sources: [
        _source(sourceId: 'source:s1', memberId: 'member:m1', priority: 0),
        _source(
          sourceId: 'source:s2',
          memberId: 'member:m2',
          playlistId: 'playlist:b',
          priority: 1,
        ),
        _source(
          sourceId: 'source:s3',
          memberId: 'member:m2',
          playlistId: 'playlist:b',
          priority: 0,
        ),
        _source(
          sourceId: 'source:s4',
          memberId: 'member:m3',
          playlistId: 'playlist:b',
        ),
      ],
      logicalIdByMemberId: const {
        'member:m1': 'member:m1',
        'member:m2': 'member:m2',
        'member:m3': 'member:m3',
      },
    );

    test('explicit association preserves source IDs and priority and changes only logical ownership', () {
      final state = twoChannels();
      final result = associateChannels(
        state: state,
        memberIds: const ['member:m1', 'member:m2'],
        preferredLogicalId: 'member:m1',
      );

      expect(result.logicalIdByMemberId['member:m1'], 'member:m1');
      expect(result.logicalIdByMemberId['member:m2'], 'member:m1');
      // The unselected member keeps its own channel: association is exactly what the user asked for.
      expect(result.logicalIdByMemberId['member:m3'], 'member:m3');

      expect(result.sources.map((ChannelSourceRecord s) => s.sourceId).toList(), [
        'source:s1',
        'source:s2',
        'source:s3',
        'source:s4',
      ], reason: 'source identity survives a merge untouched');
      expect(result.sources.map((ChannelSourceRecord s) => s.priority).toList(), [0, 1, 0, 0]);
      expect(result.sources.firstWhere((ChannelSourceRecord s) => s.sourceId == 'source:s2').channelId, 'member:m1');
      expect(result.sources.firstWhere((ChannelSourceRecord s) => s.sourceId == 'source:s3').channelId, 'member:m1');
      expect(result.sources.firstWhere((ChannelSourceRecord s) => s.sourceId == 'source:s4').channelId, 'member:m3');
      expect(
        result.sources.firstWhere((ChannelSourceRecord s) => s.sourceId == 'source:s1').streamUrl,
        'https://cdn.example/a.m3u8',
      );
      expect(result.associations.length, 1);
      expect(result.associations.single.memberIds, ['member:m1', 'member:m2']);
    });

    test('association keeps the preferred channel\'s member first and appends in user order', () {
      final state = _state(
        playlists: [_playlist('playlist:a')],
        members: [
          _member(memberId: 'member:k1', name: 'A'),
          _member(memberId: 'member:k2', name: 'B'),
          _member(memberId: 'member:k3', name: 'C'),
        ],
        associations: const [ChannelAssociation(memberIds: ['member:k1', 'member:k2'])],
        logicalIdByMemberId: const {
          'member:k1': 'member:k1',
          'member:k2': 'member:k1',
          'member:k3': 'member:k3',
        },
      );
      final result = associateChannels(
        state: state,
        memberIds: const ['member:k3', 'member:k1'],
        preferredLogicalId: 'member:k1',
      );
      expect(result.associations.single.memberIds, ['member:k1', 'member:k2', 'member:k3']);
      expect(result.logicalIdByMemberId['member:k3'], 'member:k1');
    });

    test('association preserves the preferred channel\'s preferences', () {
      final state = twoChannels();
      final withPreference = LiveCatalogState(
        playlists: state.playlists,
        members: state.members,
        sources: state.sources,
        associations: state.associations,
        preferences: [
          const ChannelPreference(
            channelId: 'member:m1',
            favorite: true,
            hidden: false,
            category: 'سراسری',
            userOrder: 4,
            automaticFailoverEnabled: false,
            lastSuccessfulSourceId: 'source:s1',
          ),
        ],
        logicalIdByMemberId: state.logicalIdByMemberId,
      );
      final result = associateChannels(
        state: withPreference,
        memberIds: const ['member:m1', 'member:m2'],
        preferredLogicalId: 'member:m1',
      );
      final preference = result.preferences.single;
      expect(preference.channelId, 'member:m1');
      expect(preference.favorite, isTrue);
      expect(preference.category, 'سراسری');
      expect(preference.userOrder, 4);
      expect(preference.automaticFailoverEnabled, isFalse);
      expect(preference.lastSuccessfulSourceId, 'source:s1');
    });

    test('separation produces two logical channels and no source ID changes', () {
      final associated = associateChannels(
        state: twoChannels(),
        memberIds: const ['member:m1', 'member:m2'],
        preferredLogicalId: 'member:m1',
      );
      final separated = separateChannel(state: associated, memberId: 'member:m2');

      expect(separated.logicalIdByMemberId['member:m1'], 'member:m1');
      expect(separated.logicalIdByMemberId['member:m2'], 'member:m2', reason: 'rule 4: a branch takes its own member ID');
      expect(separated.sources.map((ChannelSourceRecord s) => s.sourceId).toList(), [
        'source:s1',
        'source:s2',
        'source:s3',
        'source:s4',
      ]);
      expect(separated.sources.firstWhere((ChannelSourceRecord s) => s.sourceId == 'source:s2').channelId, 'member:m2');
      expect(separated.sources.firstWhere((ChannelSourceRecord s) => s.sourceId == 'source:s3').channelId, 'member:m2');
      expect(separated.sources.firstWhere((ChannelSourceRecord s) => s.sourceId == 'source:s1').channelId, 'member:m1');
      expect(
        buildUnifiedChannels(separated).map((LogicalChannel c) => c.channelId).toSet(),
        {'member:m1', 'member:m2', 'member:m3'},
      );
    });

    test('separating one of exactly two members leaves no association record behind', () {
      final associated = associateChannels(
        state: twoChannels(),
        memberIds: const ['member:m1', 'member:m2'],
        preferredLogicalId: 'member:m1',
      );
      final separated = separateChannel(state: associated, memberId: 'member:m2');
      expect(separated.associations, isEmpty);
    });

    test('separating one member of three keeps the remaining pair associated', () {
      final associated = associateChannels(
        state: twoChannels(),
        memberIds: const ['member:m1', 'member:m2', 'member:m3'],
        preferredLogicalId: 'member:m1',
      );
      expect(associated.associations.single.memberIds, ['member:m1', 'member:m2', 'member:m3']);
      final separated = separateChannel(state: associated, memberId: 'member:m3');
      expect(separated.associations.single.memberIds, ['member:m1', 'member:m2']);
      expect(separated.logicalIdByMemberId['member:m3'], 'member:m3');
    });

    test('changing a stream URL creates a new source ID while the member and logical ID stay stable', () {
      const original = '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="PressTV.ir" group-title="News",Press TV\n'
          'https://cdn.example/a.m3u8\n'
          'https://cdn.example/b.m3u8\n';
      const edited = '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="PressTV.ir" group-title="News",Press TV\n'
          'https://cdn.example/a.m3u8\n'
          'https://cdn.example/c.m3u8\n';
      final before = registerParsedPlaylist(
        parsed: parsePlaylist(playlistId: 'playlist:a', text: original),
        playlistId: 'playlist:a',
        providerNamespace: 'famelack',
      );
      final after = registerParsedPlaylist(
        parsed: parsePlaylist(playlistId: 'playlist:a', text: edited),
        playlistId: 'playlist:a',
        providerNamespace: 'famelack',
      );

      expect(before.members.single.memberId, after.members.single.memberId);
      expect(before.sources.length, 2);
      expect(after.sources.length, 2);
      final kept = after.sources.firstWhere(
        (ChannelSourceRecord s) => s.streamUrl == 'https://cdn.example/a.m3u8',
      );
      final moved = after.sources.firstWhere(
        (ChannelSourceRecord s) => s.streamUrl == 'https://cdn.example/c.m3u8',
      );
      final dropped = before.sources.firstWhere(
        (ChannelSourceRecord s) => s.streamUrl == 'https://cdn.example/b.m3u8',
      );
      expect(after.sources.any((ChannelSourceRecord s) => s.sourceId == dropped.sourceId), isFalse,
          reason: 'a different address is a different source, so its history stops applying');
      expect(kept.memberId, after.members.single.memberId);
      expect(moved.memberId, after.members.single.memberId);
      expect(moved.channelId, moved.memberId, reason: 'a new logical channel uses its member ID');
      expect(kept.sourceId == moved.sourceId, isFalse);
    });
  });

  group('invalid association input', () {
    LiveCatalogState base() => _state(
      playlists: [_playlist('playlist:a')],
      members: [
        _member(memberId: 'member:v1', name: 'One'),
        _member(memberId: 'member:v2', name: 'Two'),
        _member(memberId: 'member:v3', name: 'Three'),
      ],
      sources: [_source(sourceId: 'source:v1', memberId: 'member:v1')],
      associations: const [ChannelAssociation(memberIds: ['member:v2', 'member:v3'])],
      logicalIdByMemberId: const {
        'member:v1': 'member:v1',
        'member:v2': 'member:v2',
        'member:v3': 'member:v2',
      },
    );

    test('fewer than two distinct IDs throws before any mutation', () {
      expect(
        () => associateChannels(
          state: base(),
          memberIds: const ['member:v1'],
          preferredLogicalId: 'member:v1',
        ),
        throwsA(_identityError('fewerThanTwoMembers')),
      );
      expect(
        () => associateChannels(state: base(), memberIds: const [], preferredLogicalId: 'member:v1'),
        throwsA(_identityError('fewerThanTwoMembers')),
      );
    });

    test('a duplicate member ID throws before any mutation', () {
      expect(
        () => associateChannels(
          state: base(),
          memberIds: const ['member:v1', 'member:v1'],
          preferredLogicalId: 'member:v1',
        ),
        throwsA(_identityError('duplicateMember')),
      );
    });

    test('an unknown member ID throws before any mutation', () {
      expect(
        () => associateChannels(
          state: base(),
          memberIds: const ['member:v1', 'member:ghost'],
          preferredLogicalId: 'member:v1',
        ),
        throwsA(_identityError('unknownMember')),
      );
    });

    test('a member already associated elsewhere throws before any mutation', () {
      expect(
        () => associateChannels(
          state: base(),
          memberIds: const ['member:v1', 'member:v3'],
          preferredLogicalId: 'member:v1',
        ),
        throwsA(_identityError('memberAssociatedElsewhere')),
      );
      // Separation inherits the same discipline: one member alone is not an association to leave.
      expect(
        () => separateChannel(state: base(), memberId: 'member:v1'),
        throwsA(_identityError('fewerThanTwoMembers')),
      );
      expect(
        () => separateChannel(state: base(), memberId: 'member:ghost'),
        throwsA(_identityError('unknownMember')),
      );
    });

    test('an unknown preferred logical channel throws before any mutation', () {
      expect(
        () => associateChannels(
          state: base(),
          memberIds: const ['member:v1', 'member:v2'],
          preferredLogicalId: 'member:nowhere',
        ),
        throwsA(_identityError('unknownPreferredLogicalChannel')),
      );
    });

    test('no function automatically mutates associations from candidate lookup', () {
      final state = base();
      for (final left in state.members) {
        for (final right in state.members) {
          findChannelCandidate(left, right);
        }
      }
      expect(state.associations.length, 1);
      expect(Map<String, String>.of(state.logicalIdByMemberId), {
        'member:v1': 'member:v1',
        'member:v2': 'member:v2',
        'member:v3': 'member:v2',
      });
      // And building a snapshot is read-only too.
      final built = buildUnifiedChannels(state);
      expect(built.length, 2);
      expect(state.logicalIdByMemberId.length, 3);
    });
  });

  group('unified catalog', () {
    test('disabled playlists are omitted while their members stay untouched for re-enabling', () {
      final state = _state(
        playlists: [_playlist('playlist:on'), _playlist('playlist:off', enabled: false)],
        members: [
          _member(memberId: 'member:u1', playlistId: 'playlist:on', name: 'Kept'),
          _member(memberId: 'member:u2', playlistId: 'playlist:off', name: 'Hidden list'),
        ],
        sources: [
          _source(sourceId: 'source:u1', memberId: 'member:u1', playlistId: 'playlist:on'),
          _source(
            sourceId: 'source:u2',
            memberId: 'member:u2',
            playlistId: 'playlist:off',
          ),
        ],
        logicalIdByMemberId: const {
          'member:u1': 'member:u1',
          'member:u2': 'member:u2',
        },
      );
      final channels = buildUnifiedChannels(state);
      expect(channels.map((LogicalChannel c) => c.channelId), ['member:u1']);
      expect(state.members.length, 2, reason: 'omitting a playlist must not delete its member rows');
      expect(state.sources.length, 2);
    });

    test('a disabled source stays manageable but is never playback-eligible', () {
      final state = _state(
        playlists: [_playlist('playlist:on')],
        members: [_member(memberId: 'member:d1', playlistId: 'playlist:on', name: 'Two speeds')],
        sources: [
          _source(sourceId: 'source:d1', memberId: 'member:d1', playlistId: 'playlist:on', priority: 0),
          _source(
            sourceId: 'source:d2',
            memberId: 'member:d1',
            playlistId: 'playlist:on',
            priority: 1,
            enabled: false,
            health: SourceHealth.disabled,
          ),
        ],
        logicalIdByMemberId: const {'member:d1': 'member:d1'},
      );
      final channel = buildUnifiedChannels(state).single;
      expect(channel.sources.length, 2, reason: 'a disabled source is still the user\'s to re-enable');
      expect(channel.sources.map((ChannelSourceRecord s) => s.sourceId), ['source:d1', 'source:d2']);
      expect(
        channel.sources.where((ChannelSourceRecord s) => s.enabled).map((ChannelSourceRecord s) => s.sourceId).toList(),
        ['source:d1'],
      );
    });

    test('sources sort by priority then sourceId', () {
      final state = _state(
        playlists: [_playlist('playlist:on')],
        members: [_member(memberId: 'member:o1', playlistId: 'playlist:on', name: 'Order')],
        sources: [
          _source(sourceId: 'source:zz', memberId: 'member:o1', playlistId: 'playlist:on', priority: 0),
          _source(sourceId: 'source:aa', memberId: 'member:o1', playlistId: 'playlist:on', priority: 0),
          _source(sourceId: 'source:mid', memberId: 'member:o1', playlistId: 'playlist:on', priority: 2),
          _source(sourceId: 'source:first', memberId: 'member:o1', playlistId: 'playlist:on', priority: 1),
        ],
        logicalIdByMemberId: const {'member:o1': 'member:o1'},
      );
      expect(
        buildUnifiedChannels(state).single.sources.map((ChannelSourceRecord s) => s.sourceId).toList(),
        ['source:aa', 'source:zz', 'source:first', 'source:mid'],
      );
    });

    test('channel preferences are applied, and hidden channels are carried rather than dropped', () {
      final state = _state(
        playlists: [_playlist('playlist:on')],
        members: [
          _member(memberId: 'member:f1', playlistId: 'playlist:on', name: 'First', group: 'News'),
          _member(memberId: 'member:f2', playlistId: 'playlist:on', name: 'Second', group: 'Music'),
        ],
        sources: [
          _source(sourceId: 'source:f1', memberId: 'member:f1', playlistId: 'playlist:on'),
          _source(sourceId: 'source:f2', memberId: 'member:f2', playlistId: 'playlist:on'),
        ],
        preferences: [
          const ChannelPreference(
            channelId: 'member:f2',
            favorite: true,
            hidden: true,
            category: 'انتخابی',
            userOrder: 1,
            automaticFailoverEnabled: false,
            lastSuccessfulSourceId: 'source:f2',
          ),
        ],
        logicalIdByMemberId: const {
          'member:f1': 'member:f1',
          'member:f2': 'member:f2',
        },
      );
      final channels = buildUnifiedChannels(state);
      expect(channels.length, 2, reason: 'hiding is a view concern, not a deletion');
      expect(channels.first.channelId, 'member:f2', reason: 'an explicit userOrder sorts ahead');
      expect(channels.first.displayName, 'Second');
      expect(channels.first.category, 'انتخابی', reason: 'the preference outranks the parsed group');
      expect(channels.first.favorite, isTrue);
      expect(channels.first.hidden, isTrue);
      expect(channels.first.userOrder, 1);
      expect(channels.first.automaticFailoverEnabled, isFalse);
      expect(channels.first.lastSuccessfulSourceId, 'source:f2');
      expect(channels.last.category, 'News', reason: 'with no preference the parsed group survives');
      expect(channels.last.automaticFailoverEnabled, isTrue);
      expect(channels.last.lastSuccessfulSourceId, isNull);
    });

    test('the persisted last-successful-source preference reaches its logical channel', () {
      final state = _state(
        playlists: [_playlist('playlist:a'), _playlist('playlist:b')],
        members: [
          _member(memberId: 'member:l1', playlistId: 'playlist:a', name: 'Shared'),
          _member(memberId: 'member:l2', playlistId: 'playlist:b', name: 'Shared'),
        ],
        sources: [
          _source(sourceId: 'source:l1', memberId: 'member:l1', playlistId: 'playlist:a'),
          _source(
            sourceId: 'source:l2',
            memberId: 'member:l2',
            playlistId: 'playlist:b',
            priority: 3,
          ),
        ],
        associations: const [ChannelAssociation(memberIds: ['member:l1', 'member:l2'])],
        preferences: [
          const ChannelPreference(
            channelId: 'member:l1',
            lastSuccessfulSourceId: 'source:l2',
          ),
        ],
        logicalIdByMemberId: const {
          'member:l1': 'member:l1',
          'member:l2': 'member:l1',
        },
      );
      final channel = buildUnifiedChannels(state).single;
      expect(channel.channelId, 'member:l1');
      expect(channel.memberIds, ['member:l1', 'member:l2']);
      expect(channel.sources.map((ChannelSourceRecord s) => s.sourceId), [
        'source:l1',
        'source:l2',
      ]);
      expect(channel.lastSuccessfulSourceId, 'source:l2');
    });

    test('metadata comes from the preferred member and a member with no mapping stands alone', () {
      final state = _state(
        playlists: [_playlist('playlist:a')],
        members: [
          _member(
            memberId: 'member:x1',
            playlistId: 'playlist:a',
            name: 'You TV',
            country: 'IR',
            logo: 'https://i/y.png',
            group: 'مستند',
          ),
          _member(memberId: 'member:x2', playlistId: 'playlist:a', name: 'Unmapped'),
        ],
        logicalIdByMemberId: const {'member:x1': 'member:x1'},
      );
      final channels = buildUnifiedChannels(state);
      expect(channels.length, 2);
      final first = channels.first;
      expect(first.channelId, 'member:x1');
      expect(first.displayName, 'You TV');
      expect(first.normalizedName, liveNameKey('You TV'));
      expect(first.logoUrl, 'https://i/y.png');
      expect(first.category, 'مستند');
      expect(first.countryCode, 'IR');
      expect(first.memberIds, ['member:x1']);
      // Rule 4 again: no mapping is not the same as no channel.
      expect(channels.last.channelId, 'member:x2');
      expect(channels.last.sources, isEmpty);
    });
  });

  group('built-in catalog adapter', () {
    const List<LiveTvChannel> iranRows = [
      LiveTvChannel(
        nanoid: 'fam1',
        name: 'IRIB 1',
        streams: ['https://live.example/irib1.m3u8'],
        languages: ['fa'],
        country: 'IR',
        isGeoBlocked: false,
      ),
      LiveTvChannel(
        nanoid: 'fam2',
        name: 'Press TV',
        streams: [
          'https://live.example/presstv-720.m3u8',
          'https://live.example/presstv-1080.m3u8',
          'https://live.example/presstv-720.m3u8',
        ],
        languages: ['en'],
        country: 'IR',
        isGeoBlocked: true,
      ),
      LiveTvChannel(
        nanoid: '',
        name: 'بی بی سی فارسی',
        streams: [],
        languages: ['fa'],
        country: 'IR',
        isGeoBlocked: false,
      ),
    ];

    test('the adapter returns exactly the supplied rows and never an iptv-org-only row', () {
      final registered = registerBuiltInChannels(
        channels: iranRows,
        playlistId: 'playlist:builtin-iran',
        providerNamespace: 'famelack',
      );

      expect(registered.channels.length, iranRows.length);
      expect(registered.channels.map((LiveTvChannel c) => c.name).toList(), [
        'IRIB 1',
        'Press TV',
        'بی بی سی فارسی',
      ]);
      expect(
        registered.members.any((ChannelMember m) => liveNameKey(m.displayName) == liveNameKey('Manoto')),
        isFalse,
        reason: 'a row iptv-org knows and Famelack does not must never reach the list through here',
      );
      expect(registered.members.length, 3);
      expect(registered.members.map((ChannelMember m) => m.ordinal).toList(), [0, 1, 2]);
      for (final ChannelMember member in registered.members) {
        expect(member.playlistId, 'playlist:builtin-iran');
        expect(member.providerNamespace, 'famelack');
        expect(member.normalizedName, liveNameKey(member.displayName));
      }
      expect(registered.members[0].providerChannelId, 'fam1');
      expect(registered.members[1].providerChannelId, 'fam2');
      expect(
        registered.members[2].providerChannelId,
        'name:${liveNameKey('بی بی سی فارسی')}',
        reason: 'a Famelack row without a nanoid still needs a stable provider ID',
      );
    });

    test('every supplied URL becomes a playlist-origin, unverified, not-yet-verified source', () {
      final registered = registerBuiltInChannels(
        channels: iranRows,
        playlistId: 'playlist:builtin-iran',
        providerNamespace: 'famelack',
      );
      // Three URLs stated, one of them twice: the duplicate collapses, nothing else is invented.
      expect(registered.sources.length, 3);
      for (final ChannelSourceRecord source in registered.sources) {
        expect(source.origin, SourceOrigin.playlist);
        expect(source.health, SourceHealth.unverified);
        expect(source.rendererCapability, 'Not Yet Verified');
        expect(source.enabled, isTrue);
        expect(source.playlistId, 'playlist:builtin-iran');
        expect(source.providerNamespace, 'famelack');
        expect(source.streamUrl, contains('.m3u8'));
        expect(
          source.sourceId,
          'source:${stableKeyHash('${source.memberId}\nurl\n${source.streamUrl}')}',
        );
      }
      final press = registered.members[1];
      expect(registered.sources.where((ChannelSourceRecord s) => s.memberId == press.memberId).length, 2);
      expect(registered.sources.every((ChannelSourceRecord s) => s.channelId == s.memberId), isTrue);
      expect(
        registered.members[0].memberId,
        'member:${stableKeyHash('playlist:builtin-iran\nprovider\nfamelack\nfam1')}',
        reason: 'the built-in rows must mint the same IDs a parsed playlist mints',
      );
      expect(
        registered.sources.firstWhere((ChannelSourceRecord s) => s.memberId == press.memberId).label,
        'منبع اصلی',
      );
    });

    test('credential-bearing built-in URLs are refused exactly like parsed ones', () {
      final registered = registerBuiltInChannels(
        channels: const [
          LiveTvChannel(
            nanoid: 'fam3',
            name: 'Signed TV',
            streams: ['https://live.example/a.m3u8?token=abc', 'https://live.example/b.m3u8'],
            languages: ['fa'],
            country: 'IR',
            isGeoBlocked: false,
          ),
        ],
        playlistId: 'playlist:builtin-iran',
        providerNamespace: 'famelack',
      );
      expect(registered.members.length, 1, reason: 'the row stays manageable even when its URL is refused');
      expect(registered.sources.length, 1);
      expect(registered.sources.single.streamUrl, 'https://live.example/b.m3u8');
      expect(registered.sources.single.streamSecretRef, isNull);
      final encoded = LiveCatalogMigration.encode(
        _state(
          members: registered.members,
          sources: registered.sources,
          logicalIdByMemberId: {
            for (final ChannelMember member in registered.members)
              member.memberId: member.memberId,
          },
        ),
      );
      expect(encoded.contains('token'), isFalse, reason: 'no credential may reach persisted text');
    });

    test('rows sharing a provider ID merge their URLs instead of minting a duplicate member', () {
      final registered = registerBuiltInChannels(
        channels: const [
          LiveTvChannel(
            nanoid: 'dup',
            name: 'Dup TV',
            streams: ['https://dup.example/a.m3u8'],
            languages: ['fa'],
            country: 'IR',
            isGeoBlocked: false,
          ),
          LiveTvChannel(
            nanoid: 'dup',
            name: 'Dup TV',
            streams: ['https://dup.example/b.m3u8'],
            languages: ['fa'],
            country: 'IR',
            isGeoBlocked: false,
          ),
        ],
        playlistId: 'playlist:builtin-iran',
        providerNamespace: 'famelack',
      );
      expect(registered.channels.length, 2, reason: 'the runtime row list is the caller\'s, untouched');
      expect(registered.members.length, 1);
      expect(registered.sources.map((ChannelSourceRecord s) => s.streamUrl).toList(), [
        'https://dup.example/a.m3u8',
        'https://dup.example/b.m3u8',
      ]);
      expect(
        registered.sources.map((ChannelSourceRecord s) => s.priority).toList(),
        [0, 1],
        reason: 'priority is the user-visible order within one member, so it stays gapless',
      );
    });

    test('the adapter does not alter the list it is handed', () {
      final input = List<LiveTvChannel>.unmodifiable(iranRows);
      final registered = registerBuiltInChannels(
        channels: input,
        playlistId: 'playlist:builtin-iran',
        providerNamespace: 'famelack',
      );
      expect(registered.channels.length, 3);
      expect(input.map((LiveTvChannel c) => c.name).toList(), ['IRIB 1', 'Press TV', 'بی بی سی فارسی']);
    });
  });

  // Task B4 precondition. Every state above is built with a hand-written `logicalIdByMemberId`, which is the
  // same rule `seedSingletonChannels` now implements; a real catalog comes from `registerParsedPlaylist` and
  // has no map at all, so the first merge a user attempts is refused on all three ports until something seeds
  // it. These groups are the conditions under which that helper is allowed to exist: it reproduces the
  // fixture rule exactly, never rewrites a recorded decision, and does not change what a screen displays.
  group('singleton seeding', () {
    final members = [
      _member(memberId: 'member:sd1', name: 'One'),
      _member(memberId: 'member:sd2', name: 'Two', playlistId: 'playlist:b'),
      _member(memberId: 'member:sd3', name: 'Three', playlistId: 'playlist:c'),
    ];
    const seededMapping = {
      'member:sd1': 'member:sd1',
      'member:sd2': 'member:sd2',
      'member:sd3': 'member:sd3',
    };
    final unseeded = _state(members: members);

    test('an unseeded catalog refuses its first merge', () {
      expect(
        () => associateChannels(
          state: unseeded,
          memberIds: const ['member:sd1', 'member:sd2'],
          preferredLogicalId: 'member:sd1',
        ),
        throwsA(_identityError('unknownPreferredLogicalChannel')),
        reason: 'the map is keyed on member ids, so a fresh catalog has no key to name a preferred channel',
      );
      expect(unseeded.logicalIdByMemberId, isEmpty);
      expect(
        logicalIdOf(unseeded, 'member:sd1'),
        'member:sd1',
        reason: 'reading already treats an unmapped member as its own channel',
      );
    });

    test('seeding maps every member to itself and touches nothing else', () {
      final seeded = seedSingletonChannels(unseeded);
      expect(seeded.logicalIdByMemberId, seededMapping);
      expect(seeded.members.length, 3);
      expect(
        unseeded.logicalIdByMemberId,
        isEmpty,
        reason: 'the input state is unmodifiable and stays untouched',
      );
      expect(identical(seeded, unseeded), isFalse);
      expect(membersOfLogicalChannel(seeded, 'member:sd1'), ['member:sd1']);
    });

    test('seeding is idempotent and never rewrites a recorded merge', () {
      final once = seedSingletonChannels(unseeded);
      expect(
        identical(seedSingletonChannels(once), once),
        isTrue,
        reason: 'a second load adds nothing, so calling it on every start costs no new state',
      );
      final merged = associateChannels(
        state: once,
        memberIds: const ['member:sd2', 'member:sd3'],
        preferredLogicalId: 'member:sd2',
      );
      expect(merged.logicalIdByMemberId['member:sd3'], 'member:sd2');
      expect(
        identical(seedSingletonChannels(merged), merged),
        isTrue,
        reason: 'a user decision is data; a load-time helper must not get to revisit it',
      );
    });

    test('a seeded merge lands on the state the hand-mapped groups produce', () {
      final handMapped = _state(members: members, logicalIdByMemberId: seededMapping);
      expect(
        associateChannels(
          state: seedSingletonChannels(unseeded),
          memberIds: const ['member:sd2', 'member:sd3'],
          preferredLogicalId: 'member:sd2',
        ).logicalIdByMemberId,
        associateChannels(
          state: handMapped,
          memberIds: const ['member:sd2', 'member:sd3'],
          preferredLogicalId: 'member:sd2',
        ).logicalIdByMemberId,
        reason: 'seeding is the same starting point the suites already assumed',
      );
    });

    test('seeding changes what may be merged, not what a screen shows', () {
      List<String> ids(List<LogicalChannel> channels) =>
          channels.map((LogicalChannel c) => c.channelId).toList();
      expect(ids(buildUnifiedChannels(seedSingletonChannels(unseeded))),
          ids(buildUnifiedChannels(unseeded)),
          reason: 'three unassociated rows stay three rows, in the same order');
    });
  });
}
