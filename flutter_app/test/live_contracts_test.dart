import 'dart:convert';
import 'dart:io';

import 'package:ccloud/core/live_catalog_codec.dart';
import 'package:ccloud/core/live_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

// Most of this file drives the codec through `LiveCatalogMigration`, which is the entry
// point its callers use. One test below reaches `LiveCatalogStateCodec` directly, on
// purpose: the cross-port contract names `supportedSchemaVersion` as a symbol the Swift and
// webOS ports must mirror by that exact name, and a claim about an interface is only proven
// where the interface is spelled. Indirection through the migration facade would keep
// compiling if the constant were renamed, made private, or given a different home.
void main() {
  test('the codec publishes the schema-version interface the other ports mirror', () {
    // Spelled against the symbol, not the number: B1-S (`Sources/Core/
    // LiveTVCatalogCodec.swift`) and B1-J (`webos_app/app/js/playlist_contracts.js`) are
    // specified to expose `supportedSchemaVersion`, and an interface claim that only the
    // migration facade exercises would still pass if this port renamed it, made it private
    // or moved it. The decode/encode pair is called directly for the same reason — the
    // preflight lives on the codec, and a facade-only test could not tell which object
    // actually owns it.
    expect(LiveCatalogStateCodec.supportedSchemaVersion, 1);
    final raw = '{"schemaVersion":1,"playlists":[],"members":[],"sources":[],"associations":[],"preferences":[],"logicalIdByMemberId":{}}';
    final decoded = LiveCatalogStateCodec.decode(raw);
    expect(decoded.schemaVersion, LiveCatalogStateCodec.supportedSchemaVersion);
    final reEncoded = jsonDecode(LiveCatalogStateCodec.encode(decoded));
    expect(reEncoded['schemaVersion'], LiveCatalogStateCodec.supportedSchemaVersion);
  });

  test('absent state migrates to an empty v1 state', () {
    final state = LiveCatalogMigration.migrate(null);
    expect(state.schemaVersion, 1);
    expect(state.playlists, isEmpty);
    expect(state.members, isEmpty);
    expect(state.sources, isEmpty);
  });

  test('v1 fixture round-trips and secret URLs are not serialized', () {
    final raw = File('../Tests/fixtures/migration/catalog-v1.json')
        .readAsStringSync();
    final state = LiveCatalogMigration.migrate(raw);
    final withSecret = LiveCatalogState(
      playlists: state.playlists,
      sources: const [
        ChannelSourceRecord(
          sourceId: 'source:test',
          channelId: 'member:test',
          memberId: 'member:test',
          playlistId: 'builtin:live',
          providerNamespace: 'builtin:ccloud',
          label: 'منبع تست',
          streamSecretRef: 'secret:test',
          protocolHint: 'hls',
          origin: SourceOrigin.playlist,
          priority: 0,
          enabled: true,
          health: SourceHealth.unverified,
        ),
      ],
    );
    final encoded = LiveCatalogMigration.encode(withSecret);
    expect(jsonDecode(encoded)['schemaVersion'], 1);
    // The canonical wire text form is pinned: RFC 3339 UTC with exactly three
    // fractional digits, which is what DateTime.toIso8601String() emits and what
    // the webOS store already writes. Without this assertion,
    // encode(migrate(fixture)) would not be textually stable and no test would
    // notice, while the Swift and JavaScript ports must emit byte-comparable
    // documents.
    expect((jsonDecode(encoded)['playlists'] as List).first['createdAt'],
        '2026-01-01T00:00:00.000Z');
    // Decoding stays lenient about the seconds-precision form the frozen fixture
    // uses: both accepted spellings normalize to the same UTC instant. The
    // payload is rebuilt from the fixture's own decoded map so no schema field
    // is hand-copied here.
    final Map<String, dynamic> lenient =
        jsonDecode(raw) as Map<String, dynamic>;
    final Map<String, dynamic> lenientPlaylist =
        (lenient['playlists'] as List<dynamic>).first as Map<String, dynamic>;
    lenientPlaylist['createdAt'] = '2026-01-01T00:00:00Z';
    final String secondsForm = jsonEncode(lenient);
    lenientPlaylist['createdAt'] = '2026-01-01T00:00:00.000Z';
    final String millisecondForm = jsonEncode(lenient);
    final secondsInstant =
        LiveCatalogMigration.migrate(secondsForm).playlists.single.createdAt;
    final millisecondInstant = LiveCatalogMigration.migrate(millisecondForm)
        .playlists
        .single
        .createdAt;
    expect(secondsInstant, millisecondInstant);
    expect(secondsInstant.isUtc, isTrue);
    expect(millisecondInstant.isUtc, isTrue);
    expect(state.playlists.single.createdAt.isUtc, isTrue);
    expect(encoded, isNot(contains('https://')));
    expect(encoded, isNot(contains('streamUrl')));
    final decoded = LiveCatalogMigration.migrate(encoded);
    expect(decoded.sources.single.streamSecretRef, 'secret:test');
    expect(decoded.sources.single.streamUrl, isEmpty);
    expect(decoded.sources.single.rendererCapability, 'Not Yet Verified');
    final invalidCapability = jsonDecode(encoded) as Map<String, dynamic>;
    (invalidCapability['sources'] as List).first['rendererCapability'] = 'maybe';
    expect(
      () => LiveCatalogMigration.migrate(jsonEncode(invalidCapability)),
      throwsFormatException,
    );
  });

  test('additive v1 preference defaults to the standard source policy', () {
    final raw = '{"schemaVersion":1,"playlists":[],"members":[],"sources":[],"associations":[],"preferences":[{"channelId":"member:test"}],"logicalIdByMemberId":{}}';
    final policy = LiveCatalogMigration.migrate(raw).preferences.single.sourcePolicy;
    expect(policy.maxAutomaticAttempts, 3);
    expect(policy.sameSourceRetries, 2);
    expect(policy.connectTimeoutMs, 15000);
    expect(policy.backoffMs, [500, 1500, 4000]);
    expect(policy.failedCooldownSeconds, 600);
    expect(policy.bufferingThresholdMs, 30000);
  });

  test('future and corrupt states fail closed', () {
    expect(
      () => LiveCatalogMigration.migrate('{"schemaVersion":2}'),
      throwsFormatException,
    );
    expect(
      () => LiveCatalogMigration.migrate('{not-json'),
      throwsFormatException,
    );
  });

  test('encode rejects a schema version the codec cannot decode', () {
    expect(
      () => LiveCatalogMigration.encode(
        const LiveCatalogState(schemaVersion: 2),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          startsWith('Unsupported live catalog schema'),
        ),
      ),
    );
  });

  test('legacy preference keys are not rewritten by migration', () {
    final raw = File('../Tests/fixtures/migration/flutter-legacy-prefs.json')
        .readAsStringSync();
    final before = jsonDecode(raw) as Map<String, dynamic>;
    LiveCatalogMigration.migrate(null);
    final after = jsonDecode(raw) as Map<String, dynamic>;
    expect(after, before);
    expect(after.keys, containsAll([
      'ccloud.favorites',
      'ccloud.history',
      'ccloud.appearance',
      'ccloud.preferredQuality',
    ]));
  });
}
