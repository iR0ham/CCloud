import 'dart:convert';
import 'dart:io';

import 'package:ccloud/core/channel_identity.dart';
import 'package:ccloud/core/live_catalog.dart' show liveNameKey;
import 'package:ccloud/core/live_catalog_store.dart';
import 'package:ccloud/core/live_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Task B4-2D: the Dart half of the live catalog persistence seam.
//
// `test/live_contracts_test.dart` proves the codec reads and writes a document, and
// `test/channel_identity_test.dart` proves `seedSingletonChannels` makes a catalog mergeable. Neither proves
// the two can be joined without losing user data, which is what `LiveCatalogStore` exists for. The
// expectations below are therefore about the boundaries a device hits and a library test cannot see: an empty
// preferences store, a value that is not text at all, truncated JSON, a document from a newer build, and a
// storage layer that refuses a write or a removal.
//
// Three rules carry the suite, because breaking any of them loses a user's playlists:
//
//  * a load never writes (reading happens on every start, so a read that persisted would rewrite the document
//    before the user does anything);
//  * an unreadable document is reported and left exactly where it is (`LinkHealthStore` may reset its cache at
//    `link_health.dart:105`, a catalog may not);
//  * a write is proven by asking storage afterwards, so `refused` means the caller keeps its own state instead
//    of showing a catalog that vanishes on relaunch.
//
// These are the same three rules `Tests/webos/live_catalog_store.test.js` and the Swift block in
// `Tests/live-foundation/main.swift` pin, with the same five status words and the same two refusal messages, so
// one bug report describes any platform. Verdicts are checked against the *real* codec and identity functions
// rather than a stub — a seam that agreed with a fake codec would prove nothing about the schema preflight it
// is supposed to inherit.
//
// Two Dart-specific facts shape the tests and are worth stating, because they are the reason this port cannot
// copy the webOS or Swift test bodies verbatim. `SharedPreferences` caches in memory and updates that cache
// *before* the platform answers, so a refused write still looks present locally; the seam therefore re-syncs
// through `reload()`, and the `_RefusingStore` below is what makes that rule observable. And `getString` casts
// (`shared_preferences_legacy.dart:127`), so a key holding an int throws rather than returning null; the seam
// asks `containsKey` and then the untyped `get`, and the non-string test pins that combination.
//
// Everything here runs in the Dart VM against an in-memory storage implementation. No Android emulator, iOS
// simulator or Windows host is involved, so the suite cannot show that a real device's storage survives an app
// update, a full data partition, or process death; that stays unverified and is recorded as such in
// `EXECUTION_LOG.md`.
final DateTime _at = DateTime.utc(2026, 11, 25, 12, 0, 0);

PlaylistRecord _playlist(String id, {PlaylistSourceType sourceType = PlaylistSourceType.remoteUrl}) =>
    PlaylistRecord(
      playlistId: id,
      name: id,
      sourceType: sourceType,
      locationRef: 'https://cdn.example/$id.m3u',
      enabled: true,
      createdAt: _at,
    );

ChannelMember _member({
  required String memberId,
  required String name,
  String playlistId = 'playlist:a',
  String providerId = '',
  String? country,
}) => ChannelMember(
  memberId: memberId,
  playlistId: playlistId,
  providerNamespace: 'famelack',
  providerChannelId: providerId,
  displayName: name,
  normalizedName: liveNameKey(name),
  ordinal: 0,
  countryCode: country,
);

ChannelSourceRecord _source({
  required String sourceId,
  required String memberId,
  String playlistId = 'playlist:a',
  int priority = 0,
}) => ChannelSourceRecord(
  sourceId: sourceId,
  channelId: memberId,
  memberId: memberId,
  playlistId: playlistId,
  providerNamespace: 'famelack',
  label: priority == 0 ? 'منبع اصلی' : 'منبع $priority',
  protocolHint: 'hls',
  origin: SourceOrigin.playlist,
  priority: priority,
  enabled: true,
  health: SourceHealth.unverified,
  streamUrl: 'https://cdn.example/$sourceId.m3u8',
);

/// A registered-looking catalog: rows and sources, and no logical ids at all, which is exactly what
/// `registerParsedPlaylist` produces and what makes the load-time seed observable.
LiveCatalogState _catalog() => LiveCatalogState(
  playlists: [_playlist('playlist:a'), _playlist('playlist:b')],
  members: [
    _member(memberId: 'member:c1', name: 'IRIB 1', providerId: 'IRIB1', country: 'IR'),
    _member(memberId: 'member:c2', name: 'پرس تی‌وی', playlistId: 'playlist:b', providerId: 'PressTV', country: 'IR'),
    _member(memberId: 'member:c3', name: 'Press TV', playlistId: 'playlist:b', providerId: 'PressTV2', country: 'IR'),
  ],
  sources: [
    _source(sourceId: 'source:c1', memberId: 'member:c1'),
    _source(sourceId: 'source:c2', memberId: 'member:c2', playlistId: 'playlist:b'),
    _source(sourceId: 'source:c3', memberId: 'member:c3', playlistId: 'playlist:b', priority: 1),
  ],
);

Matcher _identityError(String code) => isA<ArgumentError>().having(
  (ArgumentError error) => error.message,
  'message',
  'ChannelIdentityError.$code',
);

/// A storage implementation that answers every mutation with failure while still reporting its own contents.
///
/// The plugin's built-in `InMemorySharedPreferencesStore` always succeeds, so without this the two branches the
/// seam exists for — a write the platform refused and a removal it refused — could not be exercised at all on
/// this port, while webOS (`refuseWrites`) and Swift (a planted blocker file) do exercise them. `extends` rather
/// than `implements`, as the platform interface requires, so the un-overridden members keep their defaults.
class _RefusingStore extends SharedPreferencesStorePlatform {
  _RefusingStore(Map<String, Object> appKeyed)
    : stored = <String, Object>{
        for (final MapEntry<String, Object> entry in appKeyed.entries) _pluginPrefix + entry.key: entry.value,
      };

  /// The namespace `SharedPreferences` adds in front of every key, so this fake hands the plugin the same
  /// shape a real platform does and `getAll` results strip cleanly.
  static const String _pluginPrefix = 'flutter.';

  /// Keys as the platform holds them, that is with the plugin's own namespace included.
  final Map<String, Object> stored;

  int writeAttempts = 0;
  int removalAttempts = 0;

  /// Whether storage still holds `value` under an app-visible key.
  bool holds(String appKey, Object value) => stored[_pluginPrefix + appKey] == value;

  /// Whether the app-visible key is still present at all.
  bool holdsKey(String appKey) => stored.containsKey(_pluginPrefix + appKey);

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.from(stored);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writeAttempts += 1;
    return false;
  }

  @override
  Future<bool> remove(String key) async {
    removalAttempts += 1;
    return false;
  }

  @override
  Future<bool> clear() async => false;
}

/// A storage double that answers every call *optimistically* while its backing map does whatever the flags say.
///
/// The plugin's own in-memory double always succeeds and always agrees with itself, so the three shapes this
/// seam has to survive cannot be produced with it: a write that is accepted and then dropped, a listing that
/// throws so the read-back cannot run at all, and a document that exists in storage but not in the cache this
/// instance was built with. `_RefusingStore` above covers the blunt case (every mutation says no); this covers
/// the ones where a mutation *says yes*, which is where a seam that trusts the boolean would go wrong.
///
/// Each test below sets exactly one flag and asserts the counters, so a verdict can only come from the shape
/// that test claims to exercise.
class _OptimisticStore extends SharedPreferencesStorePlatform {
  _OptimisticStore(Map<String, Object> appKeyed)
    : stored = <String, Object>{
        for (final MapEntry<String, Object> entry in appKeyed.entries) _pluginPrefix + entry.key: entry.value,
      };

  static const String _pluginPrefix = 'flutter.';

  /// Keys as the platform holds them, that is with the plugin's own namespace included.
  final Map<String, Object> stored;

  /// Report a successful write while keeping nothing, which is what a quota-limited or private-mode layer does
  /// when it accepts the call and discards the bytes.
  bool dropsWrittenValues = false;

  /// Fail every listing, so `reload()` cannot reach storage and the read-back is impossible rather than merely
  /// negative. Set this *after* `getInstance()`, because the first listing is what builds the instance.
  bool refusesToList = false;

  /// Report an empty world on the listing `getInstance()` makes, then answer truthfully. That is the shape a
  /// document has when another process wrote it after this instance cached its keys.
  bool hidesFirstListing = false;

  int writeAttempts = 0;
  int removalAttempts = 0;
  int listings = 0;

  /// Whether storage still holds `value` under an app-visible key.
  bool holds(String appKey, Object value) => stored[_pluginPrefix + appKey] == value;

  /// Whether the app-visible key is still present at all.
  bool holdsKey(String appKey) => stored.containsKey(_pluginPrefix + appKey);

  @override
  Future<Map<String, Object>> getAll() async {
    listings += 1;
    if (refusesToList) {
      throw Exception('storage listing refused');
    }
    if (hidesFirstListing && listings == 1) {
      return <String, Object>{};
    }
    return Map<String, Object>.from(stored);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writeAttempts += 1;
    if (!dropsWrittenValues) {
      stored[key] = value;
    }
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    removalAttempts += 1;
    stored.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    stored.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Opens preferences over the ordinary succeeding in-memory store, with `initial` under app-visible keys.
  Future<SharedPreferences> open([Map<String, Object> initial = const <String, Object>{}]) async {
    SharedPreferences.setMockInitialValues(initial);
    return SharedPreferences.getInstance();
  }

  /// Opens preferences over [_RefusingStore], which still serves reads but reports failure for every mutation.
  Future<SharedPreferences> openRefusing([Map<String, Object> initial = const <String, Object>{}]) async {
    // `setMockInitialValues` first, because it also clears the cached singleton; the instance is replaced
    // afterwards so `getInstance()` loads through the fake rather than the always-succeeding in-memory double.
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    SharedPreferencesStorePlatform.instance = _RefusingStore(initial);
    return SharedPreferences.getInstance();
  }

  /// Opens preferences over a caller-built [_OptimisticStore], whose flags a test may change after the instance
  /// exists — the only way to model storage that changes, or stops answering, between startup and the call.
  Future<SharedPreferences> openOptimistic(_OptimisticStore platform) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    SharedPreferencesStorePlatform.instance = platform;
    return SharedPreferences.getInstance();
  }

  group('surface', () {
    test('the seam reports five distinct verdicts on one documented key', () {
      expect(LiveCatalogStoreStatus.values, hasLength(5));
      expect(
        LiveCatalogStoreStatus.values.map((LiveCatalogStoreStatus s) => s.name).toSet(),
        <String>{'ok', 'absent', 'corrupt', 'saved', 'refused'},
        reason: 'the webOS and Swift ports use these words, so a rename here splits one behaviour into three vocabularies',
      );
      expect(
        LiveCatalogStore.storageKey,
        'ccloud.liveCatalog',
        reason: 'the flat app-visible naming every persisted value on this port uses, beside ccloud.linkHealth',
      );
    });

    test('only corrupt and refused withhold the state a caller renders', () async {
      // Two halves, because either one alone hides a bug. The property is pinned on hand-built outcomes: a
      // verdict is usable exactly when it carries a state, whatever its label says. The mapping is pinned on
      // the paths the seam really takes, because a `corrupt` result that quietly carried an empty state would
      // still satisfy the property while letting a screen paint nothing over unreadable bytes.
      const LiveCatalogState state = LiveCatalogState();
      expect(LiveCatalogStoreOutcome(LiveCatalogStoreStatus.ok, state: state).isUsable, isTrue);
      expect(LiveCatalogStoreOutcome(LiveCatalogStoreStatus.absent, state: state).isUsable, isTrue);
      expect(LiveCatalogStoreOutcome(LiveCatalogStoreStatus.saved, state: state).isUsable, isTrue);
      expect(LiveCatalogStoreOutcome(LiveCatalogStoreStatus.corrupt).isUsable, isFalse);
      expect(LiveCatalogStoreOutcome(LiveCatalogStoreStatus.refused).isUsable, isFalse);
      expect(
        LiveCatalogStoreOutcome(LiveCatalogStoreStatus.corrupt, state: state).isUsable,
        isTrue,
        reason: 'isUsable answers about the state, not the label — so the seam, not the caller, must withhold it',
      );

      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      expect(store.load().isUsable, isTrue, reason: 'an absent device still hands back a seeded empty state');
      final LiveCatalogStoreOutcome saved = await store.save(_catalog());
      expect(saved.status, LiveCatalogStoreStatus.saved);
      expect(saved.isUsable, isTrue, reason: 'a write that landed returns the state it wrote');
      final LiveCatalogStoreOutcome refused = await store.save(const LiveCatalogState(schemaVersion: 2));
      expect(refused.status, LiveCatalogStoreStatus.refused);
      expect(refused.isUsable, isFalse, reason: 'a refused write may not leave the caller holding a state');
      final LiveCatalogStoreOutcome corrupt = LiveCatalogStore(
        await open(<String, Object>{LiveCatalogStore.storageKey: '{oops'}),
      ).load();
      expect(corrupt.status, LiveCatalogStoreStatus.corrupt);
      expect(corrupt.isUsable, isFalse, reason: 'nothing may be rendered over bytes this build cannot read');
    });
  });

  group('an empty device', () {
    test('reads as absent, hands back a seeded empty state, and creates no key', () async {
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.absent);
      expect(read.message, isNull, reason: 'an empty device is not a failure and must not look like one');
      expect(read.isUsable, isTrue);
      expect(read.state!.schemaVersion, 1);
      expect(read.state!.members, isEmpty);
      expect(read.state!.logicalIdByMemberId, isEmpty);
      expect(prefs.getKeys(), isEmpty, reason: 'rule 1: a load that persisted would write before the user acts');
      expect(store.hasStoredDocument, isFalse);
    });

    test('an empty string is the canonical empty document, not a corrupt one', () async {
      final SharedPreferences prefs = await open(<String, Object>{LiveCatalogStore.storageKey: ''});
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.ok);
      expect(read.state!.schemaVersion, 1);
      expect(read.state!.members, isEmpty);
      expect(prefs.getString(LiveCatalogStore.storageKey), '', reason: 'and it is still found exactly as it was');
    });
  });

  group('a real round trip', () {
    test('a saved catalog stores codec text and reads back without losing a row', () async {
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogState state = _catalog();
      final LiveCatalogStoreOutcome written = await store.save(state);
      expect(written.status, LiveCatalogStoreStatus.saved);
      expect(identical(written.state, state), isTrue, reason: 'the caller keeps the state it handed in');
      expect(store.hasStoredDocument, isTrue);

      final String? text = prefs.getString(LiveCatalogStore.storageKey);
      expect(text, isNotNull);
      final Map<String, Object?> json = jsonDecode(text!) as Map<String, Object?>;
      expect(json['schemaVersion'], 1);
      expect((json['members'] as List<Object?>).length, 3);
      expect(
        json['logicalIdByMemberId'],
        isEmpty,
        reason: 'the file holds what the caller had: seeding is a read-side rule, so a save cannot rewrite '
            'stored data behind the user',
      );

      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.ok);
      expect(read.state!.playlists.length, 2);
      expect(read.state!.sources.length, 3);
      expect(
        read.state!.members.map((ChannelMember m) => m.memberId).toList(),
        <String>['member:c1', 'member:c2', 'member:c3'],
        reason: 'row order is identity input, so a store that reordered members would change the catalog',
      );
    });

    test('loading seeds the map, so the first merge a user attempts works', () async {
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogState state = _catalog();
      expect(state.logicalIdByMemberId, isEmpty, reason: 'registration produces exactly this shape');
      await store.save(state);

      final LiveCatalogState loaded = store.load().state!;
      expect(
        loaded.logicalIdByMemberId,
        seedSingletonChannels(state).logicalIdByMemberId,
        reason: 'the seam applies the library rule from task B4-1, not a store-side copy of it',
      );
      expect(loaded.logicalIdByMemberId['member:c1'], 'member:c1');

      final LiveCatalogState merged = associateChannels(
        state: loaded,
        memberIds: const <String>['member:c1', 'member:c2'],
        preferredLogicalId: 'member:c1',
      );
      expect(merged.logicalIdByMemberId['member:c2'], 'member:c1');
      expect(
        () => associateChannels(
          state: state,
          memberIds: const <String>['member:c1', 'member:c2'],
          preferredLogicalId: 'member:c1',
        ),
        throwsA(_identityError('unknownPreferredLogicalChannel')),
        reason: 'without the load step the same document is still unmergeable, which is the gap this slice closes',
      );
    });

    test('a load never rewrites the stored bytes', () async {
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      await store.save(_catalog());
      final String before = prefs.getString(LiveCatalogStore.storageKey)!;
      store.load();
      store.load();
      expect(
        prefs.getString(LiveCatalogStore.storageKey),
        before,
        reason: 'rule 1, second half: reading a readable document changes nothing',
      );
    });
  });

  group('unreadable documents', () {
    test('truncated JSON is corrupt, reported, and left where it is', () async {
      const String broken = '{"schemaVersion":1,"members":';
      final SharedPreferences prefs = await open(<String, Object>{LiveCatalogStore.storageKey: broken});
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.corrupt);
      expect(read.state, isNull, reason: 'a document this build cannot read must never arrive as an empty catalog');
      expect((read.message ?? '').isEmpty, isFalse, reason: 'the caller needs something to log, not a bare status');
      expect(read.isUsable, isFalse);
      expect(prefs.getString(LiveCatalogStore.storageKey), broken, reason: 'the truncated write survives this read');
      expect(store.hasStoredDocument, isTrue);
    });

    test('a stored value that is not text is corrupt, not empty', () async {
      // The plugin would *throw* on `getString` here, which is why the seam asks `containsKey` first and then
      // the untyped `get`. Without that, a foreign value under this key would either crash the screen or read
      // as an empty device that the next save overwrites.
      final SharedPreferences prefs = await open(<String, Object>{LiveCatalogStore.storageKey: 7});
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.corrupt);
      expect(read.message, 'live catalog document is not JSON text');
      expect(read.state, isNull);
      expect(store.hasStoredDocument, isTrue);
    });

    test('a newer schema refuses instead of clearing the user catalog', () async {
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      await store.save(_catalog());
      final Map<String, Object?> json = jsonDecode(prefs.getString(LiveCatalogStore.storageKey)!) as Map<String, Object?>;
      json['schemaVersion'] = 2;
      final String future = jsonEncode(json);
      // A fresh instance over a document this build cannot read, which is what a downgraded app finds on disk.
      final LiveCatalogStore reloaded = LiveCatalogStore(await open(<String, Object>{
        LiveCatalogStore.storageKey: future,
      }));

      final LiveCatalogStoreOutcome read = reloaded.load();
      expect(read.status, LiveCatalogStoreStatus.corrupt);
      expect(
        read.message,
        'Unsupported live catalog schema',
        reason: 'the refusal text is the cross-port codec message, so one diagnostic means one thing everywhere',
      );
      expect(read.state, isNull);
      expect(reloaded.hasStoredDocument, isTrue);
      expect(reloaded.load().message, read.message, reason: 'reading a v2 document repeatedly never consumes it');
    });

    test('a corrupt document does not stop an explicit save from replacing it', () async {
      final SharedPreferences prefs = await open(<String, Object>{LiveCatalogStore.storageKey: '{oops'});
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      expect(store.load().status, LiveCatalogStoreStatus.corrupt);
      final LiveCatalogStoreOutcome written = await store.save(_catalog());
      expect(
        written.status,
        LiveCatalogStoreStatus.saved,
        reason: 'fail-closed protects a read, not a decision: when the user acts, the new document is the answer',
      );
      expect(store.load().status, LiveCatalogStoreStatus.ok);
    });
  });

  group('refused writes', () {
    test('a state the codec rejects is refused before anything is written', () async {
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogState broken = LiveCatalogState(
        schemaVersion: 2,
        playlists: <PlaylistRecord>[_playlist('playlist:a')],
        members: <ChannelMember>[_member(memberId: 'member:c1', name: 'IRIB 1')],
      );
      final LiveCatalogStoreOutcome written = await store.save(broken);
      expect(written.status, LiveCatalogStoreStatus.refused);
      expect(
        written.message,
        'Unsupported live catalog schema',
        reason: 'the refusal comes from the codec, so the seam cannot invent a second version rule',
      );
      expect(written.state, isNull);
      expect(
        prefs.containsKey(LiveCatalogStore.storageKey),
        isFalse,
        reason: 'an unencodable state must not leave a half-written document behind',
      );
    });

    test('a platform that refuses the write is refused, and storage keeps the old document', () async {
      // The branch the plugin's own double cannot produce: the cache is updated before the platform is asked,
      // so `!wrote` plus a re-sync is what stops the seam from reporting a save that never reached storage.
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      await store.save(_catalog());
      final String oldText = prefs.getString(LiveCatalogStore.storageKey)!;

      final SharedPreferences stuck = await openRefusing(<String, Object>{
        LiveCatalogStore.storageKey: oldText,
      });
      final _RefusingStore platform = SharedPreferencesStorePlatform.instance as _RefusingStore;
      final LiveCatalogStore refusingStore = LiveCatalogStore(stuck);
      expect(refusingStore.load().status, LiveCatalogStoreStatus.ok, reason: 'the document is readable at first');

      // Deliberately a different catalog, so "still three rows" below can only come from storage, not the cache.
      final LiveCatalogState replacement = LiveCatalogState(
        playlists: <PlaylistRecord>[_playlist('playlist:a')],
        members: <ChannelMember>[_member(memberId: 'member:only', name: 'IRIB 1')],
      );
      final LiveCatalogStoreOutcome written = await refusingStore.save(replacement);
      expect(written.status, LiveCatalogStoreStatus.refused);
      expect(written.message, 'live catalog write did not reach storage');
      expect(written.state, isNull);
      expect(
        written.isUsable,
        isFalse,
        reason: 'a caller must not mark the user decision recorded on a storage layer that said no',
      );
      expect(platform.writeAttempts, 1, reason: 'the seam asked once, so the refusal is the platform answer, not a skipped write');
      expect(
        platform.holds(LiveCatalogStore.storageKey, oldText),
        isTrue,
        reason: 'the document the platform holds is untouched by the refused write',
      );
      final LiveCatalogStoreOutcome after = refusingStore.load();
      expect(after.status, LiveCatalogStoreStatus.ok);
      expect(
        after.state!.members.map((ChannelMember m) => m.memberId).toList(),
        <String>['member:c1', 'member:c2', 'member:c3'],
        reason: 'the cache was re-synced, so a later read describes storage rather than what this process hoped',
      );
    });
  });

  group('storage that answers yes without meaning it', () {
    test('a write the platform accepts but does not keep is refused, not saved', () async {
      // Rule 3's whole reason for existing, on the branch `_RefusingStore` cannot reach: a platform that says
      // `true` and stores nothing. Dropping the read-back comparison from `save` turns this red, because the
      // plugin boolean alone would report a save the device never got.
      final _OptimisticStore platform = _OptimisticStore(<String, Object>{});
      platform.dropsWrittenValues = true;
      final SharedPreferences prefs = await openOptimistic(platform);
      final LiveCatalogStore store = LiveCatalogStore(prefs);

      final LiveCatalogStoreOutcome written = await store.save(_catalog());
      expect(written.status, LiveCatalogStoreStatus.refused);
      expect(written.message, 'live catalog write did not reach storage');
      expect(written.state, isNull, reason: 'a save that cannot be shown to exist may not be handed to a caller');
      expect(written.isUsable, isFalse);
      expect(platform.writeAttempts, 1, reason: 'the seam asked once, and the refusal is the read-back, not the answer');
      expect(
        platform.holdsKey(LiveCatalogStore.storageKey),
        isFalse,
        reason: 'nothing reached storage, which is the fact the verdict has to describe',
      );
      expect(
        store.hasStoredDocument,
        isFalse,
        reason: 'the cache was re-synced, so the instance no longer believes its own optimistic write',
      );
    });

    test('a save whose read-back cannot run is saved, and says it was unverified', () async {
      // The other degraded edge: not a storage layer that lied, but one that cannot be asked. `refused` here
      // would lose the user's action on a device whose write did land; a bare `saved` would claim evidence this
      // call does not have. The status vocabulary stays at five, and only the message carries the difference.
      final _OptimisticStore platform = _OptimisticStore(<String, Object>{});
      final SharedPreferences prefs = await openOptimistic(platform);
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      expect(store.load().message, isNull, reason: 'setup: the ordinary verdict carries no note');

      platform.refusesToList = true;
      final LiveCatalogState state = _catalog();
      final LiveCatalogStoreOutcome written = await store.save(state);
      expect(
        written.status,
        LiveCatalogStoreStatus.saved,
        reason: 'an unrunnable listing is not evidence of a failed write, so it may not become a refusal',
      );
      expect(identical(written.state, state), isTrue);
      expect(
        written.message,
        LiveCatalogStore.unverifiedSaveMessage,
        reason: 'the caller has to be able to log that this save rests on the plugin boolean alone',
      );
      expect(written.isUsable, isTrue);
      expect(platform.writeAttempts, 1);
      expect(
        platform.holds(LiveCatalogStore.storageKey, LiveCatalogMigration.encode(state)),
        isTrue,
        reason: 'storage really does hold the document, which is why refusing would have been the wrong verdict',
      );
    });

    test('clear deletes a document the plugin cache never saw', () async {
      // The review finding this closes: `clear` used to answer from `containsKey`, which only knows what this
      // instance cached at startup. A document another process wrote would read as "nothing to remove", so the
      // wipe would report success while the bytes stayed — a user who asked to forget their playlists keeping
      // them silently. Restoring that early return turns the two storage assertions below red.
      final String text = LiveCatalogMigration.encode(_catalog());
      final _OptimisticStore platform = _OptimisticStore(<String, Object>{LiveCatalogStore.storageKey: text});
      platform.hidesFirstListing = true;
      final SharedPreferences prefs = await openOptimistic(platform);
      final LiveCatalogStore store = LiveCatalogStore(prefs);

      expect(store.hasStoredDocument, isFalse, reason: 'setup: the cache really is blind to the document');
      expect(platform.holdsKey(LiveCatalogStore.storageKey), isTrue, reason: 'setup: storage holds it');

      expect(
        await store.clear(),
        isTrue,
        reason: 'storage ends up holding nothing, which is the only thing the caller asked about',
      );
      expect(platform.removalAttempts, 1, reason: 'the platform was asked even though this instance saw no key');
      expect(
        platform.holdsKey(LiveCatalogStore.storageKey),
        isFalse,
        reason: 'and the document is gone, rather than merely unlisted by a stale cache',
      );
      expect(store.hasStoredDocument, isFalse);
    });
  });

  group('clearing', () {
    test('clear reports whether storage really holds nothing', () async {
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      await store.save(_catalog());
      expect(store.hasStoredDocument, isTrue);
      expect(await store.clear(), isTrue);
      expect(store.hasStoredDocument, isFalse);
      expect(store.load().status, LiveCatalogStoreStatus.absent);
    });

    test('clearing a device that never stored anything is success', () async {
      final LiveCatalogStore store = LiveCatalogStore(await open());
      expect(await store.clear(), isTrue, reason: 'the caller goal, no stored catalog, already holds');
      expect(store.hasStoredDocument, isFalse);
    });

    test('clearing unreadable bytes removes them, so a user can recover', () async {
      final SharedPreferences prefs = await open(<String, Object>{LiveCatalogStore.storageKey: '{oops'});
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      expect(store.load().status, LiveCatalogStoreStatus.corrupt);
      expect(await store.clear(), isTrue);
      expect(store.load().status, LiveCatalogStoreStatus.absent);
    });

    test('a removal the platform refused is not reported as a wipe', () async {
      final String text = LiveCatalogMigration.encode(_catalog());
      final SharedPreferences stuck = await openRefusing(<String, Object>{
        LiveCatalogStore.storageKey: text,
      });
      final _RefusingStore platform = SharedPreferencesStorePlatform.instance as _RefusingStore;
      final LiveCatalogStore store = LiveCatalogStore(stuck);
      expect(store.load().status, LiveCatalogStoreStatus.ok);
      expect(
        await store.clear(),
        isFalse,
        reason: 'the plugin empties its cache before the platform answers, so the boolean is the only truth here',
      );
      expect(platform.removalAttempts, 1, reason: 'the seam asked once and was told no');
      expect(
        platform.holdsKey(LiveCatalogStore.storageKey),
        isTrue,
        reason: 'the document is still on the platform, which is the whole reason clear reports a bool',
      );
      expect(
        store.hasStoredDocument,
        isTrue,
        reason: 'and the re-sync leaves the object describing real storage, not this process intentions',
      );
      expect(
        store.load().status,
        LiveCatalogStoreStatus.ok,
        reason: 'the catalog the user asked to forget is still readable',
      );
    });
  });

  group('a document another build wrote', () {
    test('the frozen v1 fixture loads through the seam and stays readable', () async {
      // `Tests/fixtures/migration/catalog-v1.json` is the byte-level contract all three ports read, written by
      // neither this seam nor this codec's writer. Storing it verbatim proves the seam neither requires a
      // document of its own making nor rejects one it did not write.
      final File fixture = File('../Tests/fixtures/migration/catalog-v1.json');
      expect(
        fixture.existsSync(),
        isTrue,
        reason: 'a missing fixture must fail loudly rather than skip and still report green',
      );
      final String raw = fixture.readAsStringSync();
      final LiveCatalogStore store = LiveCatalogStore(await open(<String, Object>{
        LiveCatalogStore.storageKey: raw,
      }));
      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.ok);
      expect(read.state!.schemaVersion, 1);
      expect(
        read.state!.playlists.map((PlaylistRecord p) => p.playlistId).toList(),
        <String>['builtin:live'],
        reason: 'the fixture playlist survives the seam untouched',
      );
      expect(read.state!.logicalIdByMemberId, isEmpty, reason: 'the fixture has no members to seed');
    });
  });
}
