import 'dart:convert';
import 'dart:io';

import 'package:ccloud/core/live_catalog_store.dart';
import 'package:ccloud/core/live_contracts.dart';
import 'package:ccloud/core/live_source_composer.dart';
import 'package:ccloud/core/models.dart' show LiveTvChannel;
import 'package:ccloud/core/unified_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Task B4-3 slice S1: the Dart half of the behaviour-neutral live row composer.
//
// `Sources/Core/LiveSourceComposer.swift`, `webos_app/app/js/live_source_composer.js` and this port's
// `lib/core/live_source_composer.dart` all read the same bytes from
// `Tests/fixtures/live-composer/composer_cases.json`, so a value pinned here is pinned on three platforms at
// once and cannot drift into three different behaviours. What the suites are for is not the merge — it is the
// claim that S1 changes nothing: with an absent, empty, or unreadable document the composed row list is today's
// row list. S2 owns the call sites; nothing in the shipping app imports the composer yet.
//
// `LiveTvChannel` has no `==` (identity equality only, `models.dart:356`), so every row comparison here goes
// through `_shape`, which reads the six persisted fields. That is deliberate rather than incidental: an
// identity check would pass on a composer that returned the caller's objects without looking at them, and a
// `name`-only comparison would pass on a composer that rewrote a row's stream list.
//
// Falsifiability, per assertion group, because a green suite that cannot fail proves nothing:
//
//  * the surface group goes red if either built-in identity literal drifts from the fixture, or the issue-code
//    words change, or `composeLiveRows(built, null)` stops being a total function on an empty input;
//  * a case's `rowCount`/`names` go red if the composer appends instead of merging, re-sorts the built-in
//    prefix, or mints a row for a channel with no playable address;
//  * `rowStreams` goes red if an anchored row is rebuilt instead of extended, if the association's member order
//    is ignored, or if the canonicalized address replaces the provider's text;
//  * `rowCountry`/`rowLanguages`/`rowGeoBlocked` go red if a minted row inherits a claim the catalog does not
//    state — `isGeoBlocked: true` for a catalog row, or `country: null` rendered as absent;
//  * `mintedNanoid` goes red if a new row is keyed on a member id or a random value instead of the logical
//    channel id, which is the key favourites and the player's `stringId` use;
//  * the secret scan goes red if a credential-bearing catalog address is copied into a row, and it runs on
//    every case rather than only the refusal case;
//  * the built-in id loop goes red if a "merge" replaces an existing row, because the survivor would arrive
//    under the catalog's logical id instead of `irib1`;
//  * `issueCounts` goes red if the fold-gap diagnostic is dropped, if it is emitted per member instead of per
//    row, if a refused credential stops being reported, or if any new code appears;
//  * the symmetric neutrality check goes red in both directions: a `neutral` case whose rows change, and a
//    non-`neutral` case whose rows do not — the second is what catches a fixture whose document quietly stopped
//    meaning anything;
//  * `unifiedMemberCount` goes red if the association or the logical-id map is renamed, since it reads the
//    decoded document through `buildUnifiedChannels` and not through the composer;
//  * the seam group goes red if a refused load ever hands a caller a state, if reading writes, or if a seeded
//    empty state stops composing to the same list.
const String _fixturePath = '../Tests/fixtures/live-composer/composer_cases.json';

/// One row as the six fields the host type carries, in a fixed key order.
Map<String, Object?> _shape(LiveTvChannel row) => <String, Object?>{
  'nanoid': row.nanoid,
  'name': row.name,
  'streams': <String>[...row.streams],
  'languages': <String>[...row.languages],
  'country': row.country,
  'isGeoBlocked': row.isGeoBlocked,
};

List<Map<String, Object?>> _shapes(List<LiveTvChannel> rows) =>
    <Map<String, Object?>>[for (final LiveTvChannel row in rows) _shape(row)];

List<String> _strings(Object? value) =>
    <String>[for (final Object? item in value! as List<Object?>) item! as String];

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

List<Object?> _list(Object? value) => value! as List<Object?>;

/// A `{name: [...]}` expectation object, or empty when the fixture omits the key.
Map<String, List<String>> _stringsByName(Object? value) {
  final Map<String, List<String>> out = <String, List<String>>{};
  if (value is Map<Object?, Object?>) {
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      out[entry.key! as String] = _strings(entry.value);
    }
  }
  return out;
}

Map<String, String> _stringByName(Object? value) {
  final Map<String, String> out = <String, String>{};
  if (value is Map<Object?, Object?>) {
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      out[entry.key! as String] = entry.value! as String;
    }
  }
  return out;
}

Map<String, bool> _flagsByName(Object? value) {
  final Map<String, bool> out = <String, bool>{};
  if (value is Map<Object?, Object?>) {
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      out[entry.key! as String] = entry.value! as bool;
    }
  }
  return out;
}

Map<String, int> _countsByName(Object? value) {
  final Map<String, int> out = <String, int>{};
  if (value is Map<Object?, Object?>) {
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      out[entry.key! as String] = entry.value! as int;
    }
  }
  return out;
}

Map<String, int> _codeCounts(List<CatalogIssue> issues) {
  final Map<String, int> out = <String, int>{};
  for (final CatalogIssue issue in issues) {
    out[issue.code] = (out[issue.code] ?? 0) + 1;
  }
  return out;
}

final Map<String, Object?> _fixture =
    jsonDecode(File(_fixturePath).readAsStringSync(encoding: utf8))
        as Map<String, Object?>;

/// Rows for a case, from the named groups in the fixture's `rows` object.
///
/// Built by hand rather than through `LiveTvChannel.fromJson`, because that factory reads the *network* shape
/// (`sources.streams`) while this fixture documents the runtime row shape. Reusing the factory would make a
/// wire-format change look like a composer change.
List<LiveTvChannel> _rows(List<Object?> groupNames) {
  final Map<String, Object?> groups = _object(_fixture['rows']);
  final List<LiveTvChannel> out = <LiveTvChannel>[];
  for (final Object? groupName in groupNames) {
    for (final Object? rowJson in _list(groups[groupName! as String])) {
      final Map<String, Object?> json = _object(rowJson);
      out.add(
        LiveTvChannel(
          nanoid: json['nanoid']! as String,
          name: json['name']! as String,
          streams: _strings(json['streams']),
          languages: _strings(json['languages']),
          country: json['country']! as String,
          isGeoBlocked: json['isGeoBlocked']! as bool,
        ),
      );
    }
  }
  return out;
}

/// The synthetic token the fixture plants in one catalog address. It appears in no legitimate row text, so
/// finding it anywhere in an output list is a leak rather than a formatting difference.
const String _secretMarker = 'SECRETVALUE';

bool _carriesSecret(List<LiveTvChannel> rows) => rows.any(
  (LiveTvChannel row) => row.streams.any((String url) => url.contains(_secretMarker)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared fixture surface', () {
    test('the contract file is present and readable', () {
      // Loud, not skipped: a missing fixture would otherwise let every case below vanish while the suite still
      // reported green.
      expect(File(_fixturePath).existsSync(), isTrue, reason: '$_fixturePath must exist for this suite to mean anything');
    });

    test('the fixture and this port name the built-in identity identically', () {
      expect(_fixture['builtInPlaylistId'], LiveSourceComposer.builtInPlaylistId);
      expect(
        _fixture['builtInProviderNamespace'],
        LiveSourceComposer.builtInProviderNamespace,
        reason: 'the adapter call site uses these two literals, so a drift here would silently un-anchor every row',
      );
    });

    test('the issue codes are the words the fixture counts', () {
      expect(LiveComposerIssueCode.secretRefusal, 'secretStorageUnavailable');
      expect(LiveComposerIssueCode.foldGap, 'builtinFoldGap');
    });

    test('the pinned entry point is total on an empty built-in list', () {
      expect(composeLiveRows(<LiveTvChannel>[], null), isEmpty);
      expect(composeLiveRows(<LiveTvChannel>[], const LiveCatalogState()), isEmpty);
    });
  });

  final List<Object?> cases = _list(_fixture['cases']);

  group('shared composer cases', () {
    test('the fixture carries exactly eight cases', () {
      expect(cases.length, 8, reason: 'this suite and the other two ports read one file, so its size is a contract');
    });

    for (final Object? rawCase in cases) {
      final Map<String, Object?> caseJson = _object(rawCase);
      final String id = caseJson['id']! as String;
      final Map<String, Object?> expectJson = _object(caseJson['expect']);
      final List<LiveTvChannel> built = _rows(_list(caseJson['rows']));
      final Map<String, Object?>? document = caseJson['document'] is Map<Object?, Object?>
          ? _object(caseJson['document'])
          : null;
      final String? rawDocument = caseJson['rawDocument'] is String ? caseJson['rawDocument']! as String : null;

      test(id, () {
        // Three ways to reach "no usable document": a real object, an explicit JSON null, or raw bytes the seam
        // refuses. Exactly one form must be present, or a fixture typo would quietly downgrade a merge case
        // into a no-op case while every expectation below still matched. `containsKey` matters: an absent
        // `document` key reads back as `null` in Dart, so testing only the value would count the raw-bytes case
        // as two forms and the assertion would be red for the wrong reason.
        final bool hasDocumentKey = caseJson.containsKey('document');
        final int forms = <bool>[
              hasDocumentKey && document != null,
              hasDocumentKey && document == null,
              rawDocument != null,
            ].where((bool value) => value)
            .length;
        expect(forms, 1, reason: '$id: states exactly one document form — an object, a null, or raw text');

        LiveCatalogState? state;
        if (document != null) {
          final String text = jsonEncode(document);
          state = LiveCatalogMigration.migrate(text);
          // Pinned against the codec's own output: a mistyped collection key would decode to an empty state and
          // every merge assertion below would pass for the wrong reason.
          expect(state.playlists.length, _list(document['playlists'] ?? <Object?>[]).length,
              reason: '$id: every fixture playlist survived the codec');
          expect(state.members.length, _list(document['members'] ?? <Object?>[]).length,
              reason: '$id: every fixture member survived the codec');
          expect(state.sources.length, _list(document['sources'] ?? <Object?>[]).length,
              reason: '$id: every fixture source survived the codec');
        } else if (rawDocument != null) {
          expect(() => LiveCatalogMigration.migrate(rawDocument), throwsFormatException,
              reason: '$id: the raw fixture document must be undecodable by this build');
          expect(expectJson['neutral'], isTrue, reason: '$id: refused bytes are pinned as a neutrality case');
        }

        final ComposedLiveRows composed = composeLiveRowsWithIssues(built, state);
        final List<String> expectedNames = _strings(expectJson['names']);

        expect(composed.rows.length, expectJson['rowCount'],
            reason: '$id: the composer returns exactly the expected number of rows');
        expect(composed.rows.map((LiveTvChannel row) => row.name).toList(), expectedNames,
            reason: '$id: the rows come back in the expected order');

        final Map<String, List<String>> expectedStreams = _stringsByName(expectJson['rowStreams']);
        final Map<String, String> expectedCountries = _stringByName(expectJson['rowCountry']);
        final Map<String, List<String>> expectedLanguages = _stringsByName(expectJson['rowLanguages']);
        final Map<String, bool> expectedGeo = _flagsByName(expectJson['rowGeoBlocked']);
        final Map<String, String> expectedMinted = _stringByName(expectJson['mintedNanoid']);
        for (final String name in expectedNames) {
          final LiveTvChannel row = composed.rows.firstWhere(
            (LiveTvChannel candidate) => candidate.name == name,
            orElse: () => throw StateError('$id: no composed row named $name'),
          );
          expect(row.streams, expectedStreams[name], reason: '$id: $name carries exactly its expected addresses');
          expect(row.country, expectedCountries[name], reason: '$id: $name carries the expected country');
          expect(row.languages, expectedLanguages[name], reason: '$id: $name carries the expected languages');
          expect(row.isGeoBlocked, expectedGeo[name], reason: '$id: $name carries the expected geo-block');
          if (expectedMinted.containsKey(name)) {
            expect(row.nanoid, expectedMinted[name],
                reason: '$id: $name is identified by the catalog logical channel id');
          }
        }

        // The one security property this file owns outright, on every case rather than only the refusal case.
        expect(_carriesSecret(composed.rows), isFalse,
            reason: '$id: no credential-bearing text reaches a composed row');

        // A built-in row keeps its own identity through the join, because `stringId` and the favourites document
        // key on it. This is what catches a composer that "merges" by replacing the row.
        for (final LiveTvChannel input in built) {
          expect(
            composed.rows.firstWhere((LiveTvChannel row) => row.name == input.name).nanoid,
            input.nanoid,
            reason: '$id: ${input.name} keeps its built-in row id',
          );
        }

        final Map<String, int> codes = _codeCounts(composed.issues);
        final Map<String, int> expectedIssues = _countsByName(expectJson['issueCounts']);
        int expectedTotal = 0;
        for (final MapEntry<String, int> entry in expectedIssues.entries) {
          expectedTotal += entry.value;
          expect(codes[entry.key], entry.value,
              reason: '$id: exactly ${entry.value} ${entry.key} issue(s) reported');
        }
        expect(composed.issues.length, expectedTotal,
            reason: '$id: the composer reports no issue codes the fixture did not name');

        // Neutrality pinned both ways: a flagged case must be unchanged, an unflagged case must have changed.
        final bool wantsNeutral = expectJson['neutral'] == true;
        final bool isNeutralOutput = _sameRows(composed.rows, built);
        if (wantsNeutral) {
          expect(isNeutralOutput, isTrue,
              reason: "$id: neutrality — the rows are the caller's own rows, element for element");
        } else {
          expect(isNeutralOutput, isFalse,
              reason: '$id: this case is not flagged neutral, so its rows must differ from its input');
        }

        expect(_shapes(built), _shapes(_rows(_list(caseJson['rows']))),
            reason: "$id: composing never mutates the caller's list");
        expect(_shapes(composeLiveRows(built, state)), _shapes(composed.rows),
            reason: '$id: the same inputs compose to the same rows, so a refresh cannot shuffle the list');

        if (caseJson.containsKey('unifiedMemberCount')) {
          expect(state, isNotNull, reason: '$id: a unified-member pin needs a document');
          final Map<String, Object?> pin = _object(caseJson['unifiedMemberCount']);
          final String member = pin['channelOfMember']! as String;
          final LogicalChannel channel = buildUnifiedChannels(state!).firstWhere(
            (LogicalChannel candidate) => candidate.memberIds.contains(member),
          );
          expect(channel.memberIds.length, pin['count'],
              reason: '$id: the unified layer holds ${pin['count']} members for that channel');
        }
      });
    }
  });

  group('the persistence seam cannot smuggle a document into the row list', () {
    /// Opens preferences over the ordinary in-memory store, mirroring
    /// `test/live_catalog_store_test.dart`'s helper rather than inventing a second one.
    Future<SharedPreferences> open([Map<String, Object> initial = const <String, Object>{}]) async {
      SharedPreferences.setMockInitialValues(initial);
      return SharedPreferences.getInstance();
    }

    test('unreadable bytes reach no state, leave the list identical, and are not rewritten', () async {
      // I16, through the real seam and the real codec rather than a hand-built verdict: the caller sees
      // `corrupt` with no state, composes with null, and gets today's list.
      const String raw = '{oops';
      final SharedPreferences prefs = await open(<String, Object>{LiveCatalogStore.storageKey: raw});
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.corrupt);
      expect(read.state, isNull, reason: 'a document this build cannot read may not arrive as an empty catalog');
      expect(read.isUsable, isFalse);

      final List<LiveTvChannel> built = _rows(<Object?>['builtIn']);
      final ComposedLiveRows composed = composeLiveRowsWithIssues(built, read.state);
      expect(_shapes(composed.rows), _shapes(built), reason: "a refused load composes to the caller's own rows");
      expect(composed.issues, isEmpty, reason: 'a refusal is not a fold gap and must not be counted as one');
      expect(prefs.getString(LiveCatalogStore.storageKey), raw,
          reason: 'I16: the unreadable bytes are exactly where they were');
      expect(prefs.getKeys(), <String>{LiveCatalogStore.storageKey},
          reason: 'I16: a load that writes would rewrite the user document before they act');
    });

    test('an absent device seeds an empty state, and the empty state is still neutral', () async {
      // The seam hands back a *seeded empty state* for `absent`, not null, so neutrality has to survive the
      // whole path — the empty-document case above only proves the pure function.
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.absent);
      expect(read.state, isNotNull, reason: 'setup: the seam resolves absent to a seeded state, not to null');

      final List<LiveTvChannel> built = _rows(<Object?>['builtIn']);
      final ComposedLiveRows composed = composeLiveRowsWithIssues(built, read.state);
      expect(_shapes(composed.rows), _shapes(built), reason: "a never-written device composes to today's list");
      expect(composed.issues, isEmpty);
      expect(prefs.getKeys(), isEmpty, reason: 'and reading that device created no key at all');
    });

    test('a stored empty document round-trips and stays neutral, then a real merge stops being neutral', () async {
      final SharedPreferences prefs = await open();
      final LiveCatalogStore store = LiveCatalogStore(prefs);
      expect((await store.save(const LiveCatalogState())).status, LiveCatalogStoreStatus.saved);
      final List<LiveTvChannel> built = _rows(<Object?>['builtIn']);

      final LiveCatalogStoreOutcome read = store.load();
      expect(read.status, LiveCatalogStoreStatus.ok);
      expect(_shapes(composeLiveRowsWithIssues(built, read.state).rows), _shapes(built),
          reason: 'an empty stored document changes nothing about the list a user sees');

      final Map<String, Object?> mergedCase = cases
          .map((Object? value) => _object(value))
          .firstWhere((Map<String, Object?> value) => value['id'] == 'duplicate-name-merged');
      final LiveCatalogState merged = LiveCatalogMigration.migrate(jsonEncode(_object(mergedCase['document'])));
      expect(_shapes(composeLiveRowsWithIssues(built, merged).rows), isNot(_shapes(built)),
          reason: 'the same seam over a document that does say something changes the list, so the check above '
              'cannot be passing because nothing ever changes');
    });
  });
}

/// Element-for-element equality of two row lists, as a plain boolean.
///
/// The neutrality rule has to be assertable in both directions — equal when the case is flagged, unequal when
/// it is not — and a boolean predicate keeps the two branches comparing the same thing. The comparison runs on
/// the shape trees, whose key order `_shape` fixes, so `jsonEncode` is a deterministic rendering rather than a
/// text-level coincidence; `_shape` exists precisely so nothing here compares objects that lack `==`.
bool _sameRows(List<LiveTvChannel> left, List<LiveTvChannel> right) =>
    jsonEncode(_shapes(left)) == jsonEncode(_shapes(right));
