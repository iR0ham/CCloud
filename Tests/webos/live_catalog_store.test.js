/* Task B4-2 acceptance: the webOS catalog persistence seam.
 *
 * `Tests/webos/channel_identity.test.js` proves the identity layer seeds a logical-id map, and
 * `Tests/webos/live_contracts.test.js` proves the codec encodes and decodes a catalog document. Neither
 * proves the two can be joined without losing user data, which is what `live_catalog_store.js` is for. The
 * expectations below are therefore about the boundaries a device hits and a library test cannot see: what
 * happens when storage is empty, when the stored text is garbage, when the schema is newer than this build,
 * and when `localStorage` refuses the write.
 *
 * The suite loads the real modules into a sealed scope, exactly as the identity suite does, and gives them a
 * fake `localStorage` object rather than a stub `CC.store`. That distinction matters: `CC.store` is the only
 * code that touches storage (`util.js:42-63`), so testing through it pins the JSON round trip, the `ccloud.`
 * prefix, and the fact that a throwing `setItem` is swallowed by `CC.store` and has to be detected by the
 * store reading its own write back. This is also the first webOS suite to load `util.js` — the identity suite
 * stops at the library modules — so it is the first to need the browser's bare-`CC` alias, which `loadInto`
 * below recreates and explains.
 *
 * Everything here is static analysis and Node-level execution. No webOS device, emulator or TV browser is
 * involved, so the suite cannot show that a real TV grants storage or survives an app update; that stays
 * unverified and is recorded as such in `EXECUTION_LOG.md`.
 */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const ROOT = path.resolve(__dirname, '../..');
const JS_DIR = path.join(ROOT, 'webos_app', 'app', 'js');
const INDEX_HTML = path.join(ROOT, 'webos_app', 'app', 'index.html');

// The modules these slices need, in the order both the suites and `index.html` load them: the storage helper
// first, then the four library layers, then the seam that calls them, then the S1 composer that joins a loaded
// state onto the built-in rows. `live_source_composer.js` is in this list so the registration and ordering
// assertions below cover it; its own behaviour is pinned by `Tests/webos/live_source_composer.test.js`.
const MODULES = [
  'util.js',
  'playlist_contracts.js',
  'playlist_parser.js',
  'channel_identity.js',
  'unified_catalog.js',
  'builtin_catalog_adapter.js',
  'live_catalog_store.js',
  'live_source_composer.js'
];

// The files task B4-2 newly registers in the shipped page. `util.js` was always there.
const REGISTERED = MODULES.slice(1);

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

// A storage double with the same shape and the same failure modes the real one has: writes and removals can
// throw, and `CC.store` catches them, so a caller only learns the truth by reading back.
function fakeStorage(options) {
  const settings = options || {};
  const data = {};
  return {
    data: data,
    getItem: function (key) {
      return Object.prototype.hasOwnProperty.call(data, key) ? data[key] : null;
    },
    setItem: function (key, value) {
      if (settings.refuseWrites) throw new Error('QuotaExceededError');
      data[key] = String(value);
    },
    removeItem: function (key) {
      if (settings.refuseWrites || settings.refuseRemoval) throw new Error('QuotaExceededError');
      delete data[key];
    }
  };
}

function loadInto(scope, storage, moduleName) {
  const file = path.join(JS_DIR, moduleName);
  assert.ok(fs.existsSync(file), moduleName + ' is missing; task B4-2 owns this file');
  const source = fs.readFileSync(file, 'utf8');
  // `util.js` assigns through a bare `CC` right after `window.CC = window.CC || {}` (`util.js:2-7`), which works
  // in a browser only because `window` *is* the global object there. Sealing `window` into a parameter breaks
  // that aliasing, so the shim re-creates it: `var CC` is hoisted above the file's own statements, so every
  // module sees one shared namespace object, exactly as a TV does. The library modules do this for themselves
  // (`playlist_contracts.js:55`), so nothing here gives a module a capability the shipped page withholds; a
  // module that failed to attach its namespace still fails the export assertions in `boot` below.
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

// Each test boots its own device: a fresh sealed scope over a fresh storage double, so no test can see
// another one's persisted document.
function boot(options) {
  const settings = options || {};
  const storage = fakeStorage(settings);
  const scope = {};
  for (const name of MODULES) loadInto(scope, storage, name);
  assert.ok(scope.CC, 'the modules attached no CC namespace to window');
  assert.ok(scope.CC.liveCatalogStore, 'the persistence seam never attached itself');
  return {
    CC: scope.CC,
    storage: storage,
    store: scope.CC.liveCatalogStore,
    contracts: scope.CC.playlistContracts,
    identity: scope.CC.channelIdentity,
    parser: scope.CC.playlistParser,
    rawKey: 'ccloud.' + scope.CC.liveCatalogStore.key
  };
}

const NOW = '2026-11-25T00:00:00.000Z';

function playlistRow(id) {
  return {
    playlistId: id,
    name: id,
    sourceType: 'remoteUrl',
    locationRef: 'https://cdn.example/' + id + '.m3u',
    enabled: true,
    createdAt: NOW,
    lastUpdatedAt: null,
    lastSuccessfulRefresh: null,
    refreshStatus: 'ready',
    lastErrorCode: null,
    channelCount: 0,
    parsingVersion: 1
  };
}

function memberRow(device, id, name, playlistId) {
  return {
    memberId: id,
    playlistId: playlistId === undefined ? 'playlist:a' : playlistId,
    providerNamespace: 'famelack',
    providerChannelId: '',
    displayName: name,
    normalizedName: device.parser.nameKey(name),
    ordinal: 0,
    logoUrl: null,
    group: null,
    countryCode: null,
    languages: ['fas'],
    tvgId: null
  };
}

function sourceRow(device, id, memberId, channelId) {
  return {
    sourceId: id,
    channelId: channelId === undefined ? memberId : channelId,
    memberId: memberId,
    playlistId: 'playlist:a',
    providerNamespace: 'famelack',
    label: 'منبع ۱',
    streamUrl: 'https://cdn.example/' + id + '.m3u8',
    streamSecretRef: null,
    protocolHint: 'm3u8',
    rendererCapability: 'Not Yet Verified',
    origin: 'playlist',
    priority: 0,
    enabled: true,
    health: 'unverified',
    lastSuccessfulPlaybackAt: null,
    lastFailedPlaybackAt: null,
    lastErrorCode: null
  };
}

// A registered-but-unassociated catalog: playlists, members and sources exist, `logicalIdByMemberId` does
// not. This is the exact shape `registerParsedPlaylist` produces, and the shape that made the first merge
// fail before task B4-1.
function catalog(device) {
  const members = [
    memberRow(device, 'member:c1', 'IRIB 1'),
    memberRow(device, 'member:c2', 'IRIB 2', 'playlist:b'),
    memberRow(device, 'member:c3', 'Press TV', 'playlist:b')
  ];
  const sources = [
    sourceRow(device, 'source:c1', 'member:c1'),
    sourceRow(device, 'source:c2', 'member:c2'),
    sourceRow(device, 'source:c3', 'member:c3')
  ];
  const state = device.contracts.emptyState();
  state.playlists = [playlistRow('playlist:a'), playlistRow('playlist:b')];
  state.members = members;
  state.sources = sources;
  return state;
}

function putRaw(device, value) {
  device.storage.setItem(device.rawKey, JSON.stringify(value));
}

// ---- 1. surface -----------------------------------------------------------------

test('the persistence seam exposes one key, four verdicts, and no storage handle of its own', function () {
  const device = boot();
  const store = device.store;
  assert.deepEqual(
    Object.keys(store).sort(),
    [
      'clear',
      'hasStored',
      'key',
      'load',
      'save',
      'statusAbsent',
      'statusCorrupt',
      'statusOk',
      'statusRefused',
      'statusSaved'
    ].sort(),
    'the surface is exactly the four verdicts and the three actions task B4-3 needs, no second storage API'
  );
  assert.equal(store.key, 'liveCatalog', 'the document lives beside settings, favorites and history');
  const statuses = [store.statusOk, store.statusAbsent, store.statusCorrupt, store.statusSaved, store.statusRefused];
  assert.equal(new Set(statuses).size, 5, 'a caller branches on the status, so two verdicts may not share a word');
  for (const name of ['load', 'save', 'clear', 'hasStored']) {
    assert.equal(typeof store[name], 'function', '`' + name + '` must be callable');
  }
});

// ---- 2. an empty device ---------------------------------------------------------

test('an empty device reads as absent, and a load never writes', function () {
  const device = boot();
  assert.equal(device.store.hasStored(), false, 'nothing is stored before the first save');
  const read = device.store.load();
  assert.equal(read.status, device.store.statusAbsent);
  assert.equal(read.message, null, 'an absent document is not a failure and must not look like one');
  assert.deepEqual(
    Object.keys(read.state).sort(),
    ['associations', 'logicalIdByMemberId', 'members', 'playlists', 'preferences', 'recentWatches', 'schemaVersion', 'sources'],
    'the empty state is a full catalog document, not a partial object a caller has to defend against'
  );
  assert.equal(read.state.schemaVersion, 1);
  assert.deepEqual(read.state.members, []);
  assert.deepEqual(read.state.logicalIdByMemberId, {});
  assert.equal(
    device.storage.getItem(device.rawKey),
    null,
    'reading on every start must not create a document, or a broken build would write one before the user acts'
  );
});

// ---- 3. a real round trip ------------------------------------------------------

test('a saved catalog reads back as the same document through the codec', function () {
  const device = boot();
  const state = catalog(device);
  const written = device.store.save(state);
  assert.equal(written.status, device.store.statusSaved);
  assert.equal(device.store.hasStored(), true);
  assert.equal(
    typeof JSON.parse(device.storage.getItem(device.rawKey)),
    'string',
    'storage holds codec text, so `encodeState` validated the document rather than JSON.stringify guessing at it'
  );
  const read = device.store.load();
  assert.equal(read.status, device.store.statusOk);
  assert.deepEqual(read.state.playlists, state.playlists);
  assert.deepEqual(read.state.members, state.members);
  assert.deepEqual(read.state.sources, state.sources);
  assert.equal(read.state.members.length, 3, 'a reload loses no row');
});

test('loading seeds a stored catalog, so the first merge a user attempts works', function () {
  const device = boot();
  const state = catalog(device);
  assert.deepEqual(state.logicalIdByMemberId, {}, 'the fixture is what registration actually produces');
  device.store.save(state);
  const stored = JSON.parse(JSON.parse(device.storage.getItem(device.rawKey)));
  assert.deepEqual(
    stored.logicalIdByMemberId,
    {},
    'the save persisted the state it was given: seeding happens on read, never as a side effect of writing'
  );
  const read = device.store.load();
  assert.deepEqual(
    read.state.logicalIdByMemberId,
    device.identity.seedSingletonChannels(state).logicalIdByMemberId,
    'a loaded document is mergeable through the same rule task B4-1 published, not a store-side copy of it'
  );
  const merged = device.identity.associate(read.state, ['member:c1', 'member:c2'], 'member:c1');
  assert.equal(merged.logicalIdByMemberId['member:c2'], 'member:c1', 'the user decision the seam exists to enable');
  assert.throws(
    function () {
      device.identity.associate(state, ['member:c1', 'member:c2'], 'member:c1');
    },
    /unknownPreferredLogicalChannel/,
    'without the load step the same document is still unmergeable, which is the gap this slice closes'
  );
});

// ---- 4. corrupt documents ------------------------------------------------------

test('a malformed document is reported and left exactly where it is', function () {
  const device = boot();
  putRaw(device, '{oops');
  const before = device.storage.getItem(device.rawKey);
  const read = device.store.load();
  assert.equal(read.status, device.store.statusCorrupt);
  assert.equal(read.state, null, 'a document this build cannot read must never arrive as an empty catalog');
  assert.ok(read.message.length > 0, 'the caller needs a message to log, not a bare status');
  assert.equal(device.storage.getItem(device.rawKey), before, 'reading destroyed nothing');
});

test('a stored object instead of codec text is corrupt, not empty', function () {
  const device = boot();
  putRaw(device, { schemaVersion: 1, members: [] });
  const read = device.store.load();
  assert.equal(read.status, device.store.statusCorrupt);
  assert.equal(read.message, 'live catalog document is not JSON text');
  assert.equal(read.state, null);
});

test('storage text that is not JSON at all is still corrupt, not an empty device', function () {
  // The case `CC.store.get` cannot see: it turns a parse failure into its fallback (`util.js:43-49`), so a
  // seam that trusted only `get` would call this device empty and let the next save overwrite a document that
  // a later build might still read. The seam asks `CC.store.has` for this one distinction.
  const device = boot();
  device.storage.setItem(device.rawKey, '{"schemaVersion":1,"members":');
  const before = device.storage.getItem(device.rawKey);
  assert.equal(device.CC.store.get(device.store.key, null), null, 'CC.store really does report this as missing');
  const read = device.store.load();
  assert.equal(read.status, device.store.statusCorrupt, 'and the seam does not repeat that answer');
  assert.equal(read.state, null);
  assert.equal(read.message, 'live catalog document is not readable as text');
  assert.equal(device.store.hasStored(), true, 'the bytes are known to be there without being decoded');
  assert.equal(device.storage.getItem(device.rawKey), before, 'the truncated write is left for a newer build');
  assert.equal(device.store.clear(), true, 'an explicit clear still removes it');
  assert.equal(device.store.load().status, device.store.statusAbsent, 'and only then is the device empty');
});

test('CC.store.has answers the raw-presence question without decoding anything', function () {
  // `live_catalog_store.js` is not allowed a `localStorage` handle of its own (see the host-API policy check
  // below), so the absent-versus-unreadable distinction has to be something the storage layer answers. This
  // pins that answer against the real slot, for bytes no parser accepts, and for a storage that throws.
  const device = boot();
  assert.equal(device.CC.store.has(device.store.key), false, 'nothing stored yet');
  device.storage.setItem(device.rawKey, '{"schemaVersion":1,"members":');
  assert.equal(device.CC.store.has(device.store.key), true, 'unparseable bytes still occupy the slot');
  assert.equal(device.CC.store.get(device.store.key, null), null, 'which is exactly what get cannot report');
  device.storage.removeItem(device.rawKey);
  assert.equal(device.CC.store.has(device.store.key), false, 'and removing them is visible again');

  const refused = boot();
  refused.storage.getItem = function () { throw new Error('SecurityError'); };
  assert.equal(refused.CC.store.has(refused.store.key), false, 'a storage that refuses reads counts as empty');
  assert.equal(refused.store.load().status, refused.store.statusAbsent, 'so the seam reports a device, not a crash');
});

test('the seam and CC.store agree on one storage key, so a document cannot be written where it cannot be read', function () {
  // The seam asks `CC.store` for both reads and presence while `util.js` owns the `ccloud.` prefix. That is only
  // safe while both views name the same slot, which is what this pins from both directions.
  const device = boot();
  const text = device.contracts.encodeState(catalog(device));
  device.CC.store.set(device.store.key, text);
  assert.equal(device.store.load().status, device.store.statusOk, 'a document written through CC.store is found');
  assert.equal(device.storage.getItem(device.rawKey), JSON.stringify(text), 'at the prefixed slot CC.store uses');

  const other = boot();
  other.store.save(catalog(other));
  assert.equal(other.CC.store.get(other.store.key, null), other.contracts.encodeState(catalog(other)),
    'and a document written through the seam is readable through CC.store');
});

test('a newer schema version refuses instead of clearing the user catalog', function () {
  const device = boot();
  const text = device.contracts.encodeState(catalog(device));
  const future = JSON.parse(text);
  future.schemaVersion = 2;
  putRaw(device, JSON.stringify(future));
  const read = device.store.load();
  assert.equal(read.status, device.store.statusCorrupt);
  assert.equal(
    read.message,
    'Unsupported live catalog schema',
    'the refusal text is the cross-port codec message, so a diagnostic means the same thing on every platform'
  );
  assert.equal(read.state, null);
  assert.equal(JSON.parse(device.storage.getItem(device.rawKey)), JSON.stringify(future), 'the v2 document survives a v1 build reading it');
});

test('a corrupt document does not stop an explicit save from replacing it', function () {
  const device = boot();
  putRaw(device, '{oops');
  assert.equal(device.store.load().status, device.store.statusCorrupt);
  const written = device.store.save(catalog(device));
  assert.equal(
    written.status,
    device.store.statusSaved,
    'fail-closed protects a read, not a decision: when the user acts, the new document is the answer'
  );
  assert.equal(device.store.load().status, device.store.statusOk);
});

// ---- 5. write failures --------------------------------------------------------

test('a refused write is reported, and nothing pretends the document exists', function () {
  // A device whose storage rejects writes (quota, private mode, a full /media partition): the app must learn
  // that its save did not land, because a silently dropped association is a lost user decision.
  const stuck = boot({ refuseWrites: true });
  const written = stuck.store.save(catalog(stuck));
  assert.equal(written.status, stuck.store.statusRefused);
  assert.equal(written.message, 'live catalog write did not reach storage');
  assert.equal(written.state, null, 'a refused save hands back nothing to believe in');
  assert.equal(stuck.store.hasStored(), false);
  assert.equal(stuck.store.load().status, stuck.store.statusAbsent);
});

test('a state the codec rejects is refused before anything is written', function () {
  const device = boot();
  const broken = catalog(device);
  broken.schemaVersion = 2;
  const written = device.store.save(broken);
  assert.equal(written.status, device.store.statusRefused);
  assert.equal(
    device.storage.getItem(device.rawKey),
    null,
    'an unencodable state must not leave a half-written document behind'
  );
});

// ---- 6. clearing --------------------------------------------------------------

test('clear reports whether storage really holds nothing', function () {
  const device = boot();
  device.store.save(catalog(device));
  assert.equal(device.store.hasStored(), true);
  assert.equal(device.store.clear(), true);
  assert.equal(device.store.hasStored(), false);
  assert.equal(device.store.load().status, device.store.statusAbsent);

  const stuck = boot({ refuseRemoval: true });
  stuck.store.save(catalog(stuck));
  assert.equal(
    stuck.store.clear(),
    false,
    'a removal that storage rejected is not success, even though the call itself did not throw'
  );
  assert.equal(
    stuck.store.hasStored(),
    true,
    'the document the user asked to forget is still there, which is the whole reason clear reports'
  );
});

// ---- 7. language ceiling and host APIs ---------------------------------------

function codeOnly(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
}

test('live_catalog_store.js stays inside the webOS language ceiling and binds no host API directly', function () {
  const code = codeOnly(fs.readFileSync(path.join(JS_DIR, 'live_catalog_store.js'), 'utf8'));
  const ceiling = [
    ['optional chaining', /\?\./],
    ['nullish coalescing', /\?\?/],
    ['Array.prototype.flat', /\.flat\(/],
    ['Array.prototype.flatMap', /\.flatMap\(/],
    ['Array.prototype.includes', /\.includes\(/],
    ['Object.fromEntries', /Object\.fromEntries/],
    ['Object.entries', /Object\.entries/],
    ['globalThis', /\bglobalThis\b/],
    ['logical assignment', /(\|\||&&|\?\?)=/],
    ['String.prototype.padStart', /\.padStart\(/],
    ['arrow function', /=>/],
    ['template literal', /`/],
    ['const declaration', /(^|[^\w$.])const\s/],
    ['let declaration', /(^|[^\w$.])let\s/],
    ['class declaration', /(^|[^\w$.])class\s/],
    ['spread or rest operator', /\.\.\./]
  ];
  for (const entry of ceiling) {
    assert.equal(entry[1].test(code), false, 'live_catalog_store.js must not use ' + entry[0] + ' (Chromium 68 ceiling)');
  }
  // `util.js` owns the only storage handle in the app; a second one here would put the `ccloud.` prefix and
  // the JSON rule in two places that can drift, and would make this suite unable to prove the chain.
  for (const forbidden of ['localStorage', 'sessionStorage', 'indexedDB', 'fetch(', 'XMLHttpRequest', 'require(', 'document.', 'WebSocket', 'Date.now(']) {
    assert.ok(code.indexOf(forbidden) === -1, 'live_catalog_store.js must not touch ' + forbidden);
  }
  assert.ok(
    /^window\.CC = window\.CC \|\| \{\};$/m.test(code),
    'the seam attaches to the existing CC namespace instead of replacing it'
  );
});

// ---- 8. registration in the shipped page -------------------------------------

function scriptTags(html) {
  const names = [];
  const pattern = /<script[^>]*src="([^"]*)"/g;
  let match = pattern.exec(html);
  while (match !== null) {
    names.push(match[1]);
    match = pattern.exec(html);
  }
  return names;
}

test('index.html registers the multi-source modules in the order the suites load them', function () {
  assert.ok(fs.existsSync(INDEX_HTML), 'the shipped page must exist for a registration check to mean anything');
  const tags = scriptTags(fs.readFileSync(INDEX_HTML, 'utf8'));
  const expected = REGISTERED.map(function (name) {
    return 'js/' + name;
  });
  for (const src of expected) {
    assert.ok(tags.indexOf(src) !== -1, src + ' is never loaded by index.html, so the device cannot use it');
    assert.equal(tags.lastIndexOf(src), tags.indexOf(src), src + ' must be registered once');
  }
  const positions = expected.map(function (src) {
    return tags.indexOf(src);
  });
  for (let i = 1; i < positions.length; i += 1) {
    assert.ok(
      positions[i] > positions[i - 1],
      REGISTERED[i] + ' loads before ' + REGISTERED[i - 1] + ', which is not the order these modules were verified in'
    );
  }
  assert.ok(tags.indexOf('js/app.js') > positions[positions.length - 1], 'screens run after every module exists');
});

test('every app script on disk is registered, so a new module cannot be silently unshipped', function () {
  const tags = new Set(scriptTags(fs.readFileSync(INDEX_HTML, 'utf8')));
  const missing = [];
  for (const dirEntry of fs.readdirSync(JS_DIR, { withFileTypes: true })) {
    if (!dirEntry.isFile() || path.extname(dirEntry.name) !== '.js') continue;
    if (!tags.has('js/' + dirEntry.name)) missing.push(dirEntry.name);
  }
  assert.deepEqual(missing, [], 'these files exist in the package but no page loads them');
});
