import 'dart:convert';
import 'dart:io';

import 'package:ccloud/core/live_catalog_codec.dart';
import 'package:ccloud/core/live_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
