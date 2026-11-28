/* Task B4-3 slice S1 acceptance: the behaviour-neutral live row composer (webOS).
 *
 * S1's deliverable is not the merge, it is the promise that nothing changes until a user's document says
 * something. That promise is only worth what a device can be expected to hit, so this suite reads the same
 * bytes as `flutter_app/test/live_source_composer_test.dart` and the Swift block in
 * `Tests/live-foundation/main.swift`: `Tests/fixtures/live-composer/composer_cases.json`. A case one port can
 * express and the others cannot is not a contract, and the brief's neutrality claim needs one source of truth
 * rather than three paraphrases of it.
 *
 * The suite boots the real modules into a sealed scope, exactly as `Tests/webos/live_catalog_store.test.js`
 * does, so nothing here is a stub of the composer: `CC.unifiedCatalog.registerBuiltIn`, `CC.unifiedCatalog.build`,
 * `CC.playlistParser` and `CC.playlistContracts.issue` are the shipping implementations, called through the same
 * `window.CC` namespace the TV uses. `api.js` is not loaded — it is the network layer, and a sealed scope has no
 * fetch — which is why the composer reads its language table late through `CC.liveLanguageName` and why the
 * last group below pins both the bound and the unbound label path.
 *
 * Everything here is Node-level execution against source text. No webOS device, emulator or TV browser is
 * involved, so this suite cannot show that a real TV renders the composed list or survives an app update; that
 * stays unverified and is recorded as such in `EXECUTION_LOG.md`.
 *
 * Falsifiability, per group: dropping the nil guard in `compose` reddens every `neutral` case; sorting the whole
 * result instead of inserting reddens `user-only-row` and `user-only-row-mid-list` in opposite directions;
 * omitting the `builtin:live` record injection reddens `empty-document` (its rows would vanish to the minted
 * half only if the record were missing — the check is on the count and the order); letting a credential-bearing
 * address through reddens `sensitive-merged-url`'s stream list, its issue count, and the leak scan; folding a
 * built-in name in the composer reddens `fold-gap-diagnostic`; rebuilding instead of copying an anchored row
 * reddens the sentinel `languageLabel` and `stringId` preservation checks; and the seam group reddens if the
 * store starts handing back a state for undecodable bytes or if composing touches storage.
 */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const ROOT = path.resolve(__dirname, '../..');
const JS_DIR = path.join(ROOT, 'webos_app', 'app', 'js');
const FIXTURE_PATH = path.join(ROOT, 'Tests', 'fixtures', 'live-composer', 'composer_cases.json');
const MODULE = 'live_source_composer.js';

// The composer needs every layer it calls, in the order `index.html` loads them. Kept identical to
// `Tests/webos/live_catalog_store.test.js` so a device that boots one boots the other.
const MODULES = [
  'util.js',
  'playlist_contracts.js',
  'playlist_parser.js',
  'channel_identity.js',
  'unified_catalog.js',
  'builtin_catalog_adapter.js',
  'live_catalog_store.js',
  MODULE
];

const SEALED_GLOBALS = [
  'window',
  'localStorage',
  'sessionStorage',
  'indexedDB',
  'document',
  'navigator',
  'location',
  'fetch',
  'XMLHttpRequest',
  'WebSocket',
  'TextEncoder',
  'URL',
  'URLSearchParams',
  'require',
  'process',
  'Buffer',
  'global',
  'globalThis'
];

// The fixture's synthetic credential probe. It appears in no built-in row, so this is a leak detector rather
// than a name filter: it catches the whole family of ways a refused address could come back — an unfiltered
// copy, a canonicalization that kept the query, or a row minted from the member that holds it.
const SECRET_MARKER = 'SECRETVALUE';

function fakeStorage() {
  const data = {};
  return {
    data: data,
    getItem: function (key) {
      return Object.prototype.hasOwnProperty.call(data, key) ? data[key] : null;
    },
    setItem: function (key, value) {
      data[key] = String(value);
    },
    removeItem: function (key) {
      delete data[key];
    }
  };
}

function loadInto(scope, storage, moduleName) {
  const file = path.join(JS_DIR, moduleName);
  assert.ok(fs.existsSync(file), moduleName + ' is missing; task B4-3 S1 owns this file');
  const source = fs.readFileSync(file, 'utf8');
  // See `live_catalog_store.test.js:94-100`: `util.js` assigns through a bare `CC`, which only works because a
  // browser's `window` is the global object, so the shim recreates that aliasing above each module's body.
  const body = '"use strict";\nvar CC = window.CC = window.CC || {};\n' + source;
  const factory = Function.apply(null, SEALED_GLOBALS.concat([body]));
  const values = SEALED_GLOBALS.map(function (key) {
    if (key === 'window') return scope;
    if (key === 'localStorage') return storage;
    return undefined;
  });
  try {
    factory.apply(null, values);
  } catch (error) {
    assert.fail(moduleName + ' could not be evaluated inertly: ' + error.message);
  }
  return scope;
}

// Each test boots its own device: a fresh sealed scope over a fresh storage double, so no test can see another
// one's persisted document or another one's language table.
function boot() {
  const storage = fakeStorage();
  const scope = {};
  for (const name of MODULES) loadInto(scope, storage, name);
  assert.ok(scope.CC, 'the modules attached no CC namespace to window');
  assert.ok(scope.CC.liveSourceComposer, 'the composer never attached itself');
  assert.equal(typeof scope.CC.liveSourceComposer.compose, 'function', 'the composer exports no compose()');
  return {
    CC: scope.CC,
    storage: storage,
    composer: scope.CC.liveSourceComposer,
    contracts: scope.CC.playlistContracts,
    catalog: scope.CC.unifiedCatalog,
    parser: scope.CC.playlistParser,
    store: scope.CC.liveCatalogStore,
    rawKey: 'ccloud.' + scope.CC.liveCatalogStore.key
  };
}

function fixture() {
  assert.ok(fs.existsSync(FIXTURE_PATH), 'the shared composer fixture is missing');
  const parsed = JSON.parse(fs.readFileSync(FIXTURE_PATH, 'utf8'));
  assert.ok(parsed && typeof parsed === 'object', 'the shared composer fixture is not a JSON object');
  return parsed;
}

const SHARED = fixture();
const ROW_GROUPS = SHARED.rows;

function hasOwn(map, key) {
  return Object.prototype.hasOwnProperty.call(map, key);
}

function strings(value) {
  return Array.isArray(value) ? value.filter(function (entry) { return typeof entry === 'string'; }) : [];
}

function objects(value) {
  return Array.isArray(value) ? value.filter(function (entry) { return entry && typeof entry === 'object'; }) : [];
}

function byName(value) {
  const out = {};
  for (const entry of objects(value)) {
    if (typeof entry.name === 'string') out[entry.name] = entry;
  }
  return out;
}

function stringByName(value) {
  const out = {};
  for (const key of Object.keys(value || {})) out[key] = String(value[key]);
  return out;
}

function countsByName(value) {
  const out = {};
  for (const key of Object.keys(value || {})) out[key] = Number(value[key]);
  return out;
}

/**
 * A built-in row, in the shape `api.js`'s `normChannel` returns (`api.js:326-344`).
 *
 * The fixture stores only the six fields every port's row type holds; the three derived fields are what the live
 * screen actually reads, so the test recreates them the way the shipping client does. `languageLabel` and
 * `stringId` also carry a sentinel role here: the composer must return an anchored row with those fields
 * untouched, which is only checkable if they are not something the composer could plausibly rebuild.
 */
function hostRow(json) {
  const urls = strings(json.streams).map(function (entry) { return entry.trim(); })
    .filter(function (entry) { return entry.length > 0; });
  const languages = strings(json.languages);
  const name = typeof json.name === 'string' ? json.name : '';
  const nanoid = typeof json.nanoid === 'string' ? json.nanoid : '';
  const country = typeof json.country === 'string' ? json.country : '';
  let primary = '';
  for (const url of urls) {
    if (url.toLowerCase().indexOf('.m3u8') >= 0) { primary = url; break; }
  }
  if (!primary && urls.length) primary = urls[0];
  return {
    nanoid: nanoid,
    name: name,
    streams: urls,
    languages: languages,
    country: country,
    isGeoBlocked: json.isGeoBlocked === true,
    stringId: nanoid || (name + '-' + country),
    primaryStream: primary,
    languageLabel: 'label:' + name
  };
}

function rowsFor(groupNames) {
  const out = [];
  for (const groupName of strings(groupNames)) {
    const group = ROW_GROUPS[groupName];
    assert.ok(Array.isArray(group), 'the fixture names a row group that does not exist: ' + groupName);
    for (const json of group) out.push(hostRow(json));
  }
  return out;
}

function rowShape(row) {
  return JSON.stringify({
    nanoid: row.nanoid,
    name: row.name,
    streams: row.streams,
    languages: row.languages,
    country: row.country,
    isGeoBlocked: row.isGeoBlocked,
    stringId: row.stringId,
    primaryStream: row.primaryStream,
    languageLabel: row.languageLabel
  });
}

function shapes(rows) {
  return rows.map(rowShape);
}

function rowNames(rows) {
  return rows.map(function (row) { return row.name; });
}

function carriesSecret(rows, issues) {
  const haystack = shapes(rows).concat((issues || []).map(function (issue) { return String(issue.message); }));
  for (const text of haystack) {
    if (text.indexOf(SECRET_MARKER) !== -1) return text;
  }
  return null;
}

function countCodes(issues) {
  const out = {};
  for (const issue of issues) out[issue.code] = hasOwn(out, issue.code) ? out[issue.code] + 1 : 1;
  return out;
}

function namedRow(rows, name, label) {
  for (const row of rows) {
    if (row.name === name) return row;
  }
  assert.fail(label + ': no returned row named ' + name);
}

// ---- 1. the module's own surface ------------------------------------------------

test('the composer exports the built-in identity and the issue words the fixture counts', function () {
  const device = boot();
  assert.equal(SHARED.builtInPlaylistId, device.composer.builtInPlaylistId,
    'the fixture and the webOS composer name the built-in playlist identically');
  assert.equal(SHARED.builtInProviderNamespace, device.composer.builtInProviderNamespace,
    'and the built-in provider namespace identically');
  assert.equal(device.composer.issueSecretRefusal, 'secretStorageUnavailable',
    'the refusal word is the parse layer\'s own, so one condition has one name');
  assert.equal(device.composer.issueFoldGap, 'builtinFoldGap', 'and the fold gap is spelled as the fixture counts it');
});

test('composing an empty built-in list yields an empty list and no issues', function () {
  const device = boot();
  const empty = device.composer.compose({ channels: [], state: device.contracts.emptyState() });
  assert.deepEqual(empty.rows, [], 'no built-in rows and no members can compose to a row');
  assert.deepEqual(empty.issues, [], 'and there is no name to measure a fold gap on');
  const absent = device.composer.compose({ channels: [], state: null });
  assert.deepEqual(absent.rows, [], 'the nil-state path is empty too');
});

// ---- 2. the shared fixture cases ------------------------------------------------

const cases = objects(SHARED.cases);

test('the shared composer fixture carries exactly eight cases', function () {
  assert.equal(cases.length, 8, 'three suites are pinned by these bytes, so the count is part of the contract');
  const ids = cases.map(function (entry) { return entry.id; });
  assert.deepEqual(ids, [
    'absent-document',
    'empty-document',
    'corrupt-document',
    'duplicate-name-merged',
    'sensitive-merged-url',
    'user-only-row',
    'user-only-row-mid-list',
    'fold-gap-diagnostic'
  ], 'renaming a case would silently drop a port\'s coverage of it');
});

for (const caseJson of cases) {
  test(caseJson.id + ': composes to the shared expectation', function () {
    const device = boot();
    const expect = caseJson.expect;
    assert.ok(expect && typeof expect === 'object', caseJson.id + ': expect block is missing');
    const built = rowsFor(caseJson.rows);
    const builtSnapshot = shapes(built);
    const builtInstances = built.slice();

    // Three documented ways to reach "no usable document": a real object, an explicit JSON null, or raw text the
    // seam refuses. Exactly one form must be present, or a fixture typo would silently downgrade a merge case
    // into a no-op case while every expectation below still matched.
    let state = null;
    const forms = [
      caseJson.document !== null && caseJson.document !== undefined && typeof caseJson.document === 'object',
      hasOwn(caseJson, 'document') && caseJson.document === null,
      typeof caseJson.rawDocument === 'string'
    ];
    let formCount = 0;
    for (const taken of forms) if (taken) formCount += 1;
    assert.equal(formCount, 1, caseJson.id + ': states exactly one document form — an object, a null, or raw text');

    if (forms[0]) {
      const text = JSON.stringify(caseJson.document);
      const decoded = device.contracts.migrate(text);
      // Pinned against the codec's own output so a mistyped collection key cannot turn this case into a
      // different case: an ignored key would decode to an empty state and every merge assertion would pass for
      // the wrong reason.
      assert.equal(decoded.playlists.length, objects(caseJson.document.playlists).length,
        caseJson.id + ': every fixture playlist survived the codec');
      assert.equal(decoded.members.length, objects(caseJson.document.members).length,
        caseJson.id + ': every fixture member survived the codec');
      assert.equal(decoded.sources.length, objects(caseJson.document.sources).length,
        caseJson.id + ': every fixture source survived the codec');
      state = decoded;
    } else if (forms[2]) {
      assert.throws(
        function () { device.contracts.decodeState(caseJson.rawDocument); },
        function () { return true; },
        caseJson.id + ': the raw fixture document is undecodable by this build'
      );
      assert.equal(expect.neutral, true, caseJson.id + ': refused bytes are pinned as a neutrality case');
    }

    const composed = device.composer.compose({ channels: built, state: state });
    const expectedNames = strings(expect.names);

    assert.equal(composed.rows.length, expect.rowCount,
      caseJson.id + ': the composer returns exactly the expected number of rows');
    assert.deepEqual(rowNames(composed.rows), expectedNames, caseJson.id + ': the rows come back in the expected order');

    const expectedStreams = byNameFromLists(expect.rowStreams);
    const expectedCountries = stringByName(expect.rowCountry);
    const expectedLanguages = byNameFromLists(expect.rowLanguages);
    const expectedGeo = boolByName(expect.rowGeoBlocked);
    const expectedMinted = stringByName(expect.mintedNanoid);
    for (const name of expectedNames) {
      const row = namedRow(composed.rows, name, caseJson.id);
      assert.ok(hasOwn(expectedStreams, name), caseJson.id + ': rowStreams has no pin for ' + name);
      assert.deepEqual(row.streams, expectedStreams[name], caseJson.id + ': ' + name + ' carries exactly its expected addresses');
      assert.ok(hasOwn(expectedCountries, name), caseJson.id + ': rowCountry has no pin for ' + name);
      assert.equal(row.country, expectedCountries[name], caseJson.id + ': ' + name + ' carries the expected country');
      assert.ok(hasOwn(expectedLanguages, name), caseJson.id + ': rowLanguages has no pin for ' + name);
      assert.deepEqual(row.languages, expectedLanguages[name], caseJson.id + ': ' + name + ' carries the expected languages');
      assert.ok(hasOwn(expectedGeo, name), caseJson.id + ': rowGeoBlocked has no pin for ' + name);
      assert.equal(row.isGeoBlocked, expectedGeo[name], caseJson.id + ': ' + name + ' carries the expected geo-block');
      if (hasOwn(expectedMinted, name)) {
        assert.equal(row.nanoid, expectedMinted[name],
          caseJson.id + ': ' + name + ' is identified by the catalog\'s logical channel id');
      }
    }

    // The one security property this file owns outright, checked on every case rather than only where the
    // fixture names it.
    assert.equal(carriesSecret(composed.rows, composed.issues), null,
      caseJson.id + ': no credential-bearing text reaches a composed row or an issue message');

    // A built-in row keeps its own identity through the join, because the player's `stringId` and the favorites
    // document key on it. This is the check that catches a composer which "merges" by replacing the row.
    for (const input of builtSnapshot) {
      const parsed = JSON.parse(input);
      assert.equal(namedRow(composed.rows, parsed.name, caseJson.id + ': preserved').nanoid, parsed.nanoid,
        caseJson.id + ': ' + parsed.name + ' keeps its built-in row id');
    }

    // Issues carry the contract's three fields and no invented ones.
    const codes = countCodes(composed.issues);
    const expectedIssues = countsByName(expect.issueCounts);
    let expectedTotal = 0;
    for (const code of Object.keys(expectedIssues)) {
      expectedTotal += expectedIssues[code];
      assert.equal(codes[code] || 0, expectedIssues[code],
        caseJson.id + ': exactly ' + expectedIssues[code] + ' ' + code + ' issue(s) reported');
    }
    assert.equal(composed.issues.length, expectedTotal,
      caseJson.id + ': the composer reports no issue codes the fixture did not name');
    for (const issue of composed.issues) {
      assert.equal(typeof issue.code, 'string', caseJson.id + ': an issue has no code');
      assert.ok(issue.code.length > 0, caseJson.id + ': an issue has an empty code');
      assert.equal(typeof issue.message, 'string', caseJson.id + ': an issue has no message');
      assert.equal(issue.line, null, caseJson.id + ': a composed row has no source line to blame');
    }

    // Neutrality is pinned both ways. A case flagged `neutral` must return the caller's own rows, element for
    // element and instance for instance; a case not flagged must *change* something, so a fixture whose document
    // quietly stopped meaning anything (a renamed key, a dropped association) fails here instead of passing its
    // own merge assertions while doing nothing in the app.
    const wantsNeutral = expect.neutral === true;
    const sameInstances = composed.rows.length === builtInstances.length &&
      composed.rows.every(function (row, index) { return row === builtInstances[index]; });
    if (wantsNeutral) {
      assert.ok(sameInstances, caseJson.id + ': neutrality — the rows are the caller\'s own rows, instance for instance');
      assert.deepEqual(shapes(composed.rows), builtSnapshot, caseJson.id + ': and they still describe the same channels');
    } else {
      assert.ok(!sameInstances,
        caseJson.id + ': this case is not flagged neutral, so its rows must differ from its input');
    }
    if (state === null) {
      // The strongest form available, and the one S2's caller depends on: no usable document returns the very
      // array it was handed, so a screen that keeps its list keeps the same object.
      assert.equal(composed.rows, built, caseJson.id + ': with no state the caller\'s own array comes back');
    }

    // Composing never touches the caller's data, and never shuffles on a refresh.
    assert.deepEqual(shapes(built), builtSnapshot, caseJson.id + ': composing never mutates the caller\'s rows');
    const again = device.composer.compose({ channels: built, state: state });
    assert.deepEqual(shapes(again.rows), shapes(composed.rows),
      caseJson.id + ': the same inputs compose to the same rows, so a refresh cannot shuffle the list');
    assert.deepEqual(countCodes(again.issues), codes, caseJson.id + ': and reports the same issues');

    if (caseJson.unifiedMemberCount !== undefined && caseJson.unifiedMemberCount !== null) {
      const pin = caseJson.unifiedMemberCount;
      assert.ok(state, caseJson.id + ': a unified-member pin needs a document');
      const channels = device.catalog.build(state);
      let found = null;
      for (const channel of channels) {
        if (strings(channel.memberIds).indexOf(pin.channelOfMember) !== -1) found = channel;
      }
      assert.ok(found, caseJson.id + ': no unified channel holds the pinned member');
      assert.equal(found.memberIds.length, pin.count,
        caseJson.id + ': the unified layer holds ' + pin.count + ' members for that channel');
    }
  });
}

function byNameFromLists(value) {
  const out = {};
  for (const key of Object.keys(value || {})) out[key] = strings(value[key]);
  return out;
}

function boolByName(value) {
  const out = {};
  for (const key of Object.keys(value || {})) out[key] = value[key] === true;
  return out;
}

// ---- 3. the persistence seam cannot smuggle a document into the row list ---------

test('a corrupt stored document leaves today\'s list identical and the bytes where they are', function () {
  const device = boot();
  const corruptCase = cases.filter(function (entry) { return entry.id === 'corrupt-document'; })[0];
  assert.ok(corruptCase && typeof corruptCase.rawDocument === 'string',
    'the shared fixture must carry a corrupt-document case with rawDocument');
  const built = rowsFor(corruptCase.rows);
  device.storage.setItem(device.rawKey, corruptCase.rawDocument);

  const loaded = device.store.load();
  assert.equal(loaded.status, device.store.statusCorrupt, 'the seam reports the fixture\'s undecodable bytes as corrupt');
  assert.equal(loaded.state, null, 'and hands back no state, which is what makes the composer\'s nil path the real path');

  const composed = device.composer.compose({ channels: built, state: loaded.state });
  assert.ok(composed.rows.every(function (row, index) { return row === built[index]; }),
    'I16: a refused document leaves today\'s row list identical');
  assert.deepEqual(composed.issues, [], 'and a refused document is not a composer failure');
  assert.equal(device.storage.getItem(device.rawKey), corruptCase.rawDocument,
    'I16: reading and composing write nothing — the document survives byte for byte');
  assert.deepEqual(Object.keys(device.storage.data), [device.rawKey], 'and composing stores nothing alongside it');
});

test('a device that never stored a catalog composes to today\'s list', function () {
  const device = boot();
  const built = rowsFor(['builtIn']);
  const loaded = device.store.load();
  assert.equal(loaded.status, device.store.statusAbsent, 'a device with no live catalog reads as absent');
  assert.ok(loaded.state, 'and the seam hands back the seeded empty state, not nil');
  const composed = device.composer.compose({ channels: built, state: loaded.state });
  assert.ok(composed.rows.every(function (row, index) { return row === built[index]; }),
    'I16: an absent catalog composes to today\'s list through the real seam');
  assert.deepEqual(composed.issues, [], 'and the three clean names report no fold gap');
  assert.deepEqual(Object.keys(device.storage.data), [], 'and asking for the catalog created no document');
});

test('an empty stored catalog composes to today\'s list, and the same slot can carry a merge', function () {
  const device = boot();
  const built = rowsFor(['builtIn']);
  const saved = device.store.save(device.contracts.emptyState());
  assert.equal(saved.status, device.store.statusSaved, 'the empty document is writable');
  const loaded = device.store.load();
  assert.equal(loaded.status, device.store.statusOk, 'and reads back as ok');
  const composed = device.composer.compose({ channels: built, state: loaded.state });
  assert.ok(composed.rows.every(function (row, index) { return row === built[index]; }),
    'I16: an empty stored catalog composes to today\'s list through the real seam');

  // The other half of the same statement: the seam is not what makes the list static. Reading the fixture's
  // merge document through it must change the row list, or the neutrality checks above would also pass with a
  // composer that ignores its state argument entirely.
  const mergeCase = cases.filter(function (entry) { return entry.id === 'duplicate-name-merged'; })[0];
  device.storage.setItem(device.rawKey, JSON.stringify(mergeCase.document));
  const merged = device.store.load();
  assert.equal(merged.status, device.store.statusOk, 'the merge document decodes through the seam');
  const mergedRows = device.composer.compose({ channels: built, state: merged.state }).rows;
  assert.ok(!mergedRows.every(function (row, index) { return row === built[index]; }),
    'a document that re-lists a built-in station is not neutral');
  assert.equal(mergedRows[0].streams.length, 2, 'it contributes exactly one address to the anchored row');
});

// ---- 4. minted rows are renderable host rows ------------------------------------

test('a minted row carries the derived fields the live screen reads, and degrades honestly without the label table', function () {
  const device = boot();
  const built = rowsFor(['builtIn']);
  const mergeCase = cases.filter(function (entry) { return entry.id === 'user-only-row'; })[0];
  const composed = device.composer.compose({
    channels: built,
    state: device.contracts.migrate(JSON.stringify(mergeCase.document))
  });
  const minted = namedRow(composed.rows, 'BBC Persian', 'user-only-row');

  // Without `api.js` in scope there is no table, and the honest answer is the same "unknown" label the host
  // itself uses rather than a Persian name this module invented.
  assert.equal(minted.languageLabel, 'نامشخص', 'an unbound label table yields the unknown label');
  assert.equal(minted.primaryStream, 'https://stream.example/bbc-persian.m3u8',
    'a minted row is playable by the screen\'s own handoff, which reads primaryStream');
  assert.equal(minted.stringId, minted.nanoid, 'and its key is the row identity the fetch would have used');
  assert.equal(minted.isGeoBlocked, false, 'nothing here has proven a geo-block');
  assert.equal(minted.country, 'GB', 'the member\'s own country survives as host text');

  // Bound, the label is the table's, so a row the fetch never produced still matches what a language search
  // over `languageLabel` (screens/live.js:49) would find.
  device.CC.liveLanguageName = function (code) { return code === 'fas' ? 'فارسی' : code; };
  const bound = namedRow(device.composer.compose({
    channels: rowsFor(['builtIn']),
    state: device.contracts.migrate(JSON.stringify(mergeCase.document))
  }).rows, 'BBC Persian', 'user-only-row');
  assert.equal(bound.languageLabel, 'فارسی', 'the table is read late, so the composer follows whatever api.js exports');

  // An anchored row's own derived fields survive untouched, including a primary the provider chose.
  const anchor = namedRow(composed.rows, 'IRIB 1', 'absent');
  assert.equal(anchor.languageLabel, 'label:IRIB 1', 'a built-in row keeps the label the fetch gave it');
  assert.equal(anchor.stringId, 'irib1', 'and its nanoid-based key');
});

test('an anchored row with no usable address gains one instead of staying a dead cell', function () {
  const device = boot();
  const dead = hostRow({
    nanoid: 'irib1',
    name: 'IRIB 1',
    streams: [''],
    languages: ['fas'],
    country: 'IR',
    isGeoBlocked: false
  });
  assert.equal(dead.primaryStream, '', 'the fixture row above is the shape normChannel would have filtered out');
  const mergeCase = cases.filter(function (entry) { return entry.id === 'duplicate-name-merged'; })[0];
  const composed = device.composer.compose({
    channels: [dead],
    state: device.contracts.migrate(JSON.stringify(mergeCase.document))
  });
  const row = composed.rows[0];
  assert.equal(row.streams.length, 2, 'both catalog addresses reach the row');
  assert.equal(row.primaryStream, 'https://cdn.example/irib1.m3u8',
    'and the derived primary follows, so the screen does not toast "no stream" over a playable row');
  assert.equal(row.languageLabel, 'label:IRIB 1', 'while every other field stays the anchor\'s own');
});

// ---- 5. language ceiling and realm purity --------------------------------------

function codeOnly(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
}

test('live_source_composer.js stays inside the webOS language ceiling and binds no host API', function () {
  const code = codeOnly(fs.readFileSync(path.join(JS_DIR, MODULE), 'utf8'));
  const ceiling = [
    ['optional chaining', /\?\./],
    ['nullish coalescing', /\?\?/],
    ['Array.prototype.flat', /\.flat\(/],
    ['Array.prototype.flatMap', /\.flatMap\(/],
    ['Array.prototype.includes', /\.includes\(/],
    ['Object.fromEntries', /Object\.fromEntries/],
    ['Object.entries', /Object\.entries/],
    ['globalThis', /\bglobalThis\b/],
    ['BigInt', /\bBigInt\b/],
    ['logical assignment', /(\|\||&&|\?\?)=/],
    ['private class field', /#[A-Za-z]/],
    ['String.prototype.padStart', /\.padStart\(/],
    ['arrow function', /=>/],
    ['template literal', /`/],
    ['const declaration', /(^|[^\w$.])const\s/],
    ['let declaration', /(^|[^\w$.])let\s/],
    ['class declaration', /(^|[^\w$.])class\s/],
    ['async function', /(^|[^\w$.])async\s+function/],
    ['await expression', /(^|[^\w$.])await\s/],
    ['spread or rest operator', /\.\.\./]
  ];
  for (const entry of ceiling) {
    assert.equal(entry[1].test(code), false, MODULE + ' must not use ' + entry[0] + ' (Chromium 68 ceiling)');
  }
  assert.ok(/\bfor\s*\(/.test(code), 'the module walks its lists with explicit index loops');
  assert.ok(
    /^window\.CC = window\.CC \|\| \{\};$/m.test(code),
    'the module attaches to the existing CC namespace instead of replacing it'
  );
  // Storage, network and DOM all belong to other files. S1 needs none of them: the caller hands the composer
  // the state the seam already loaded, and a module that could read storage could also write a catalog from a
  // display pass, which is the rule task B4-2 exists to enforce.
  for (const forbidden of [
    'localStorage',
    'sessionStorage',
    'indexedDB',
    'CC.store',
    'fetch(',
    'XMLHttpRequest',
    'require(',
    'document.',
    'WebSocket',
    'Date.now('
  ]) {
    assert.ok(code.indexOf(forbidden) === -1, MODULE + ' must not touch ' + forbidden);
  }
  // Sibling modules are called, never replaced: a display layer that reassigned `CC.playlistParser` would
  // rewrite the parse rules for every screen behind it.
  assert.equal(
    /CC\.(playlistParser|playlistContracts|channelIdentity|unifiedCatalog|liveCatalogStore|liveLanguageName)\s*=/.test(code),
    false,
    MODULE + ' reads its siblings and never rebinds them'
  );
});

test('index.html loads the composer after every module it calls and before the screens', function () {
  const html = fs.readFileSync(path.join(ROOT, 'webos_app', 'app', 'index.html'), 'utf8');
  const tags = [];
  const pattern = /<script[^>]*src="([^"]*)"/g;
  let match = pattern.exec(html);
  while (match !== null) {
    tags.push(match[1]);
    match = pattern.exec(html);
  }
  const position = tags.indexOf('js/' + MODULE);
  assert.notEqual(position, -1, MODULE + ' is never loaded by index.html, so the device cannot use it');
  assert.equal(tags.lastIndexOf('js/' + MODULE), position, MODULE + ' must be registered once');
  for (const dependency of ['playlist_contracts.js', 'playlist_parser.js', 'unified_catalog.js', 'builtin_catalog_adapter.js']) {
    assert.ok(
      tags.indexOf('js/' + dependency) < position,
      dependency + ' must load before ' + MODULE + ', which calls into it'
    );
  }
  assert.ok(tags.indexOf('js/app.js') > position, 'screens run after the composer exists');
  assert.ok(tags.indexOf('js/api.js') < position, 'api.js exports the language table the composer reads late');
});
