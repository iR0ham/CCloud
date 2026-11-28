'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const ROOT = path.resolve(__dirname, '../..');
const JS_DIR = 'webos_app/app/js';
const MODULE_NAME = 'playlist_contracts.js';
const MIGRATION_DIR = path.join(ROOT, 'Tests/fixtures/migration');
const V1_FIXTURE_PATH = path.join(MIGRATION_DIR, 'catalog-v1.json');
const LEGACY_FIXTURE_PATH = path.join(MIGRATION_DIR, 'webos-legacy-storage.json');

// The exact surface the specification requires from this layer. Checking the names rather
// than only the behaviour matters because two implementations of one contract can each pass
// every behavioural test below while exposing differently-named entry points, at which point
// the next task has nothing to call.
const REQUIRED_API = [
  'migrate',
  'decodeState',
  'encodeState',
  'liveContext',
  'attemptContext',
  'issue',
  'snapshot',
  'emptyState',
  'standardSourcePolicy',
  'rendererSupportValues'
];

// Same contract, different loader than `Tests/webos/transport.test.js`: the module is
// evaluated in *this* realm with every browser and host I/O global sealed as a parameter,
// rather than inside `vm.runInNewContext`. The reason is measurable rather than stylistic.
// A value built inside a VM context carries that context's `Array.prototype` and
// `Object.prototype`, so `node:assert/strict` refuses it as "Values have same structure but
// are not reference-equal" even when every element matches. Ten of the checks below compare
// whole decoded documents, so a sandboxed realm would have the harness grade its own loader
// instead of the contract (that is exactly what the first hosted run of this suite showed).
// The inertness the sandbox was bought for is stated explicitly instead: `localStorage`,
// `fetch`, `XMLHttpRequest`, `document`, `require` and `process` are shadowed by parameters,
// so a module that reached for one throws here rather than passing on a development machine
// and failing on a TV.
//
// `moduleName` is a parameter, not the constant above, because task B3 runs this file against
// a second implementation of the same contract in the same directory. A harness that
// hardcoded one path would silently test that file twice and report agreement between two
// modules that were never both loaded; the parent session passes each name explicitly.
const SEALED_GLOBALS = [
  'window',
  'localStorage',
  'sessionStorage',
  'document',
  'navigator',
  'location',
  'fetch',
  'XMLHttpRequest',
  'WebSocket',
  'require',
  'process',
  'Buffer',
  'global',
  'globalThis'
];

function loadContracts(moduleName) {
  const name = moduleName || MODULE_NAME;
  const modulePath = path.join(ROOT, JS_DIR, name);
  const scope = {};
  const values = SEALED_GLOBALS.map(function (key) {
    return key === 'window' ? scope : undefined;
  });
  // The body is prefixed with the directive so a stray global write throws instead of
  // landing on the test process. `Function` compiles in this realm, which is the whole
  // point; `modulePath` stays in the thrown message because a same-realm load has no
  // filename channel of its own.
  const factory = new Function.apply(
    null,
    SEALED_GLOBALS.concat(['"use strict";\n' + fs.readFileSync(modulePath, 'utf8')])
  );
  try {
    factory.apply(null, values);
  } catch (error) {
    assert.fail(name + ' could not be evaluated inertly: ' + error.message);
  }
  const namespace = scope.CC;
  if (!namespace) {
    assert.fail(name + ' did not attach a CC namespace to window');
  }
  const keys = Object.keys(namespace);
  // Resolving the export as "whichever namespace the module attached", instead of a
  // hardcoded `CC.playlistContracts`, is what makes the parameter above useful. The
  // single-key rule is the honest part: a module that attached two namespaces would let a
  // test assert a method on one while the bundle reads the other, and no failing diff would
  // explain it.
  if (keys.length !== 1) {
    assert.fail(
      name + ' must attach exactly one CC namespace, found: ' + JSON.stringify(keys)
    );
  }
  const contracts = namespace[keys[0]];
  for (const required of REQUIRED_API) {
    if (contracts && contracts[required] !== undefined) {
      continue;
    }
    assert.fail(
      name + ' must expose `' + required + '` on CC.' + keys[0] +
        ', because the specification requires the module to migrate, encode, decode and ' +
        'build the runtime objects of the catalog contract'
    );
  }
  return contracts;
}

function moduleSource(moduleName) {
  return fs.readFileSync(path.join(ROOT, JS_DIR, moduleName || MODULE_NAME), 'utf8');
}

function readFixture(name) {
  return fs.readFileSync(path.join(MIGRATION_DIR, name), 'utf8');
}

// Every mutation below asserts the target text occurs before it is applied.
// `String.prototype.replace` with a string needle silently returns the input unchanged,
// so an unverified mutation would turn a rejection test into a tautology that passes
// because the document was never damaged — the failure mode task B1's review caught in
// the Swift harness, which is why `mutated()` exists there too.
function mutate(label, source, target, replacement) {
  if (source.indexOf(target) === -1) {
    assert.fail("mutation '" + label + "' found no occurrence of " + target);
  }
  return source.replace(target, replacement);
}

function throwsMessage(pattern, run, label) {
  let message = null;
  try {
    run();
  } catch (error) {
    message = error && error.message ? error.message : String(error);
  }
  if (message === null) assert.fail(label + ' did not throw');
  if (pattern instanceof RegExp) {
    assert.match(message, pattern, label + ' threw the wrong error: ' + message);
  } else {
    assert.ok(
      message.indexOf(pattern) !== -1,
      label + ' threw the wrong error: ' + message
    );
  }
  return message;
}

const PINNED_EPOCH_MS = 1767225600000; // 2026-01-01T00:00:00Z
const ADDITIVE_V1 = `{
  "schemaVersion": 1,
  "playlists": [
    {
      "playlistId": "builtin:live",
      "name": "CCloud",
      "sourceType": "builtIn",
      "locationRef": "builtin:live",
      "enabled": true,
      "createdAt": "2026-01-01T00:00:00Z",
      "lastUpdatedAt": "2026-01-02T03:04:05.123Z",
      "lastSuccessfulRefresh": null,
      "refreshStatus": "ready",
      "lastErrorCode": null,
      "channelCount": 62,
      "parsingVersion": 1
    },
    {
      "playlistId": "pl-remote",
      "name": "Remote List",
      "sourceType": "remoteUrl",
      "locationRef": "https://example.test/list.m3u",
      "enabled": false,
      "createdAt": "2026-02-01T00:00:00.500Z",
      "lastUpdatedAt": null,
      "lastSuccessfulRefresh": "2026-02-02T00:00:00.000Z",
      "refreshStatus": "error",
      "lastErrorCode": "refresh_timeout",
      "channelCount": 0,
      "parsingVersion": 2
    }
  ],
  "members": [
    {
      "memberId": "m-1",
      "playlistId": "builtin:live",
      "providerNamespace": "famelack",
      "providerChannelId": "IRIB1",
      "displayName": "IRIB 1",
      "normalizedName": "irib 1",
      "logoUrl": "https://img.example/irib1.png",
      "group": "General",
      "countryCode": "IR",
      "languages": ["fa"],
      "tvgId": "irib1.example",
      "ordinal": 0
    },
    {
      "memberId": "m-2",
      "playlistId": "pl-remote",
      "providerNamespace": "iptv-org",
      "providerChannelId": "IRIB1.IR",
      "displayName": "IRIB 1 HD",
      "normalizedName": "irib 1 hd",
      "logoUrl": null,
      "group": null,
      "countryCode": null,
      "languages": [],
      "tvgId": null,
      "ordinal": 1
    }
  ],
  "sources": [
    {
      "sourceId": "s-1",
      "channelId": "ch-1",
      "memberId": "m-1",
      "playlistId": "builtin:live",
      "providerNamespace": "famelack",
      "label": "Famelack",
      "streamUrl": "https://stream.example/irib1.m3u8",
      "streamSecretRef": null,
      "protocolHint": "hls",
      "rendererCapability": "Supported",
      "origin": "playlist",
      "priority": 0,
      "enabled": true,
      "health": "available",
      "lastSuccessfulPlaybackAt": "2026-03-01T12:00:00.000Z",
      "lastFailedPlaybackAt": null,
      "lastErrorCode": null
    },
    {
      "sourceId": "s-2",
      "channelId": "ch-1",
      "memberId": "m-2",
      "playlistId": "pl-remote",
      "providerNamespace": "iptv-org",
      "label": "Backup (signed)",
      "streamSecretRef": "secret:ccloud-live-s-2",
      "protocolHint": "hls",
      "origin": "user",
      "priority": 1,
      "enabled": true,
      "health": "unverified"
    }
  ],
  "associations": [
    { "memberIds": ["m-1", "m-2"] }
  ],
  "preferences": [
    {
      "channelId": "ch-1",
      "favorite": true,
      "hidden": false,
      "category": null,
      "userOrder": 3,
      "automaticFailoverEnabled": true,
      "lastSuccessfulSourceId": "s-1"
    },
    {
      "channelId": "ch-2",
      "favorite": false,
      "hidden": true,
      "category": "News",
      "userOrder": null,
      "automaticFailoverEnabled": false,
      "sourcePolicy": {
        "maxAutomaticAttempts": 5,
        "sameSourceRetries": 1,
        "connectTimeoutMs": 9000,
        "backoffMs": [250, 750],
        "failedCooldownSeconds": 30,
        "bufferingThresholdMs": 1500
      },
      "lastSuccessfulSourceId": null
    }
  ],
  "logicalIdByMemberId": {
    "m-1": "ch-1",
    "m-2": "ch-1"
  }
}`;

// Byte-identical to `minimalV1JSON` in Tests/live-foundation/main.swift, the document that
// omits every field the contract defaults. Same text on both ports is what makes the two
// readers' tolerance a measured agreement instead of two separate opinions.
const MINIMAL_V1 = '{"schemaVersion":1,"playlists":[{"playlistId":"pl-1","name":"Minimal","sourceType":"remoteUrl","locationRef":"https://example.test/list.m3u","enabled":true,"createdAt":"2026-01-01T00:00:00Z"}],"members":[{"memberId":"m-1","playlistId":"pl-1","providerNamespace":"iptv-org","providerChannelId":"IR.IRIB1","displayName":"IRIB 1","normalizedName":"irib 1","ordinal":0}],"sources":[{"sourceId":"s-1","channelId":"ch-1","memberId":"m-1","playlistId":"pl-1","providerNamespace":"iptv-org","label":"Primary","streamUrl":"https://stream.example/irib1.m3u8","protocolHint":"hls","origin":"playlist","priority":0,"enabled":true,"health":"unverified"}],"associations":[],"preferences":[{"channelId":"ch-1","sourcePolicy":{"backoffMs":[100],"connectTimeoutMs":8000}}],"logicalIdByMemberId":{"m-1":"ch-1"}}';

const ADDRESSLESS_SOURCE =
  '{"schemaVersion":1,"playlists":[],"members":[],"sources":[{"sourceId":"s-broken","channelId":"ch-1","memberId":"m-1","playlistId":"pl-1","providerNamespace":"manual","label":"Nothing","protocolHint":"hls","origin":"user","priority":0,"enabled":true,"health":"unverified"}],"associations":[],"preferences":[],"recentWatches":[],"logicalIdByMemberId":{}}';

// ---- 1. surface, empty state and the standard policy ------------------------------

test('module is inert and exposes the contract version', function () {
  const CC = loadContracts();
  assert.equal(CC.supportedSchemaVersion, 1);
  assert.deepEqual(
    CC.rendererSupportValues,
    ['Supported', 'Partially Supported', 'Unsupported', 'Not Yet Verified']
  );
  // A caller that edited the exported vocabulary must not be able to widen validation.
  CC.rendererSupportValues.push('Probably');
  assert.equal(CC.rendererSupportValues.length, 5);
  throwsMessage('RendererSupport', function () {
    CC.decodeState(mutate('unknown capability', ADDITIVE_V1, '"Supported"', '"Probably"'));
  }, 'a caller-pushed capability label');
  assert.deepEqual(loadContracts().rendererSupportValues, [
    'Supported',
    'Partially Supported',
    'Unsupported',
    'Not Yet Verified'
  ]);
});

test('absent stored data is the canonical empty v1 state', function () {
  const CC = loadContracts();
  const expected = {
    schemaVersion: 1,
    playlists: [],
    members: [],
    sources: [],
    associations: [],
    preferences: [],
    recentWatches: [],
    logicalIdByMemberId: {}
  };
  assert.deepEqual(CC.migrate(null), expected);
  assert.deepEqual(CC.migrate(undefined), expected);
  assert.deepEqual(CC.migrate(''), expected);
  assert.deepEqual(CC.emptyState(), expected);
  // Distinct objects, or two catalogs would share one array and one user's edit would
  // appear inside another state.
  const first = CC.emptyState();
  first.playlists.push({ playlistId: 'x' });
  assert.deepEqual(CC.emptyState().playlists, []);
});

test('standard policy values are the ones the specification settled on', function () {
  const CC = loadContracts();
  assert.deepEqual(CC.standardSourcePolicy(), {
    maxAutomaticAttempts: 3,
    sameSourceRetries: 2,
    connectTimeoutMs: 15000,
    backoffMs: [500, 1500, 4000],
    failedCooldownSeconds: 600,
    bufferingThresholdMs: 30000
  });
  assert.notEqual(CC.standardSourcePolicy(), CC.standardSourcePolicy());
  const policy = CC.standardSourcePolicy();
  policy.backoffMs.push(9999);
  assert.deepEqual(CC.standardSourcePolicy().backoffMs, [500, 1500, 4000]);
});

// ---- 2. the frozen fixtures -------------------------------------------------------

test('catalog-v1.json decodes with its real values and canonical times', function () {
  const CC = loadContracts();
  const text = readFixture('catalog-v1.json');
  const state = CC.decodeState(text);
  assert.equal(state.schemaVersion, 1);
  assert.equal(state.playlists.length, 1);
  const playlist = state.playlists[0];
  assert.equal(playlist.playlistId, 'builtin:live');
  assert.equal(playlist.name, 'CCloud');
  assert.equal(playlist.sourceType, 'builtIn');
  assert.equal(playlist.locationRef, 'builtin:live');
  assert.equal(playlist.enabled, true);
  assert.equal(playlist.refreshStatus, 'ready');
  assert.equal(playlist.channelCount, 0);
  assert.equal(playlist.parsingVersion, 1);
  assert.equal(playlist.lastErrorCode, null);
  // The seconds-precision text the fixture stores is normalized on read, so every later
  // comparison in the app works on one shape.
  assert.equal(playlist.createdAt, '2026-01-01T00:00:00.000Z');
  assert.equal(playlist.lastUpdatedAt, '2026-01-01T00:00:00.000Z');
  assert.equal(playlist.lastSuccessfulRefresh, '2026-01-01T00:00:00.000Z');
  assert.equal(Date.parse(playlist.createdAt), PINNED_EPOCH_MS);
  assert.deepEqual(state.members, []);
  assert.deepEqual(state.sources, []);
  assert.deepEqual(state.associations, []);
  assert.deepEqual(state.preferences, []);
  assert.deepEqual(state.recentWatches, []);
  assert.deepEqual(state.logicalIdByMemberId, {});
  assert.deepEqual(CC.migrate(text), state, 'decodeState and migrate must not diverge');
  const encoded = CC.encodeState(state);
  assert.deepEqual(JSON.parse(encoded), state, 'the frozen fixture round-trips');
  assert.ok(encoded.indexOf('"createdAt":"2026-01-01T00:00:00.000Z"') !== -1);
});

test('the additive document decodes, and only the additive keys are filled', function () {
  const CC = loadContracts();
  const state = CC.decodeState(ADDITIVE_V1);
  assert.deepEqual(state.recentWatches, [], 'an absent recentWatches decodes as empty');
  assert.equal(state.playlists.length, 2);
  assert.equal(state.members.length, 2);
  assert.equal(state.sources.length, 2);
  assert.equal(state.associations.length, 1);
  assert.equal(state.preferences.length, 2);
  assert.deepEqual(state.logicalIdByMemberId, { 'm-1': 'ch-1', 'm-2': 'ch-1' });
  assert.equal(state.members[1].ordinal, 1);
  assert.deepEqual(state.members[0].languages, ['fa']);
  assert.equal(state.members[1].logoUrl, null);
  assert.deepEqual(state.associations[0].memberIds, ['m-1', 'm-2']);
  assert.equal(state.playlists[1].enabled, false);
  assert.equal(state.playlists[1].refreshStatus, 'error');
  assert.equal(state.playlists[1].lastErrorCode, 'refresh_timeout');
  assert.equal(state.playlists[0].createdAt, '2026-01-01T00:00:00.000Z');
  assert.equal(state.playlists[0].lastUpdatedAt, '2026-01-02T03:04:05.123Z');
  assert.equal(state.playlists[1].createdAt, '2026-02-01T00:00:00.500Z');
  assert.equal(state.playlists[1].lastSuccessfulRefresh, '2026-02-02T00:00:00.000Z');

  const first = state.preferences[0];
  assert.deepEqual(first.sourcePolicy, CC.standardSourcePolicy());
  assert.equal(first.favorite, true);
  assert.equal(first.hidden, false);
  assert.equal(first.userOrder, 3);
  assert.equal(first.automaticFailoverEnabled, true);
  assert.equal(first.category, null);
  assert.equal(first.lastSuccessfulSourceId, 's-1');
  assert.deepEqual(state.preferences[1].sourcePolicy, {
    maxAutomaticAttempts: 5,
    sameSourceRetries: 1,
    connectTimeoutMs: 9000,
    backoffMs: [250, 750],
    failedCooldownSeconds: 30,
    bufferingThresholdMs: 1500
  });

  const plain = state.sources[0];
  assert.equal(plain.rendererCapability, 'Supported');
  assert.equal(plain.streamUrl, 'https://stream.example/irib1.m3u8');
  assert.equal(plain.streamSecretRef, null);
  assert.equal(plain.origin, 'playlist');
  assert.equal(plain.health, 'available');
  assert.equal(plain.lastSuccessfulPlaybackAt, '2026-03-01T12:00:00.000Z');
  assert.equal(Date.parse(plain.lastSuccessfulPlaybackAt), 1772366400000);
  assert.equal(plain.lastFailedPlaybackAt, null);
  assert.equal(plain.lastErrorCode, null);
  const secret = state.sources[1];
  assert.equal(secret.rendererCapability, 'Not Yet Verified');
  assert.equal(secret.streamUrl, '', 'a secret-backed source holds no address in memory');
  assert.equal(secret.streamSecretRef, 'secret:ccloud-live-s-2');
  assert.equal(secret.origin, 'user');
  assert.equal(secret.priority, 1);
});

test('a minimal document takes every default the contract allows', function () {
  const CC = loadContracts();
  const state = CC.decodeState(MINIMAL_V1);
  const playlist = state.playlists[0];
  assert.equal(playlist.refreshStatus, 'idle');
  assert.equal(playlist.channelCount, 0);
  assert.equal(playlist.parsingVersion, 1);
  assert.equal(playlist.lastUpdatedAt, null);
  assert.deepEqual(state.members[0].languages, []);
  assert.equal(state.members[0].ordinal, 0);
  assert.equal(state.sources[0].rendererCapability, 'Not Yet Verified');
  assert.equal(state.sources[0].lastSuccessfulPlaybackAt, null);
  const preference = state.preferences[0];
  assert.equal(preference.favorite, false);
  assert.equal(preference.hidden, false);
  assert.equal(preference.automaticFailoverEnabled, true);
  assert.equal(preference.category, null);
  assert.equal(preference.userOrder, null);
  assert.equal(preference.lastSuccessfulSourceId, null);
  assert.deepEqual(preference.sourcePolicy, {
    maxAutomaticAttempts: 3,
    sameSourceRetries: 2,
    connectTimeoutMs: 8000,
    backoffMs: [100],
    failedCooldownSeconds: 600,
    bufferingThresholdMs: 30000
  });
  // Defaults are a read tolerance, not a rewrite: what the document did say survives.
  const encoded = CC.encodeState(state);
  assert.ok(encoded.indexOf('"refreshStatus":"idle"') !== -1);
  assert.ok(encoded.indexOf('"languages":[]') !== -1);
  assert.ok(encoded.indexOf('"recentWatches":[]') !== -1);
  assert.deepEqual(JSON.parse(encoded), state, 'the upgrade is loss-free');
});

// ---- 3. canonical text on write ---------------------------------------------------

test('a written document always includes the three additive keys', function () {
  const CC = loadContracts();
  const encoded = CC.encodeState(CC.decodeState(ADDITIVE_V1));
  assert.ok(encoded.indexOf('"recentWatches":[]') !== -1);
  assert.ok(encoded.indexOf('"sourcePolicy"') !== -1);
  assert.ok(encoded.indexOf('"rendererCapability":"Not Yet Verified"') !== -1);
  assert.ok(encoded.indexOf('"watchedAt"') === -1, 'no watch record is invented');
  // The strict half of the date contract: no timestamp leaves as a bare number. A float
  // value would appear as `:1767225600.0` — the pattern is anchored on the value
  // boundary so it cannot fire inside `T00:00:00.000Z`.
  const DATE_FIELDS = [
    'createdAt',
    'lastUpdatedAt',
    'lastSuccessfulRefresh',
    'lastSuccessfulPlaybackAt',
    'lastFailedPlaybackAt'
  ];
  for (const field of DATE_FIELDS) {
    const numeric = new RegExp('"' + field + '":[-0-9]');
    assert.equal(
      encoded.search(numeric),
      -1,
      'the ' + field + ' field must never be written as a bare epoch number'
    );
  }
  for (const field of ['createdAt', 'lastUpdatedAt', 'lastSuccessfulRefresh', 'lastSuccessfulPlaybackAt']) {
    const quoted = new RegExp('"' + field + '":"');
    assert.ok(quoted.test(encoded), 'the ' + field + ' field is written as canonical text');
  }
  assert.ok(!/:[0-9]+\.[0-9]+[,}\]]/.test(encoded), 'no numeric field carries a fraction');
  assert.ok(encoded.startsWith('{"schemaVersion":1'), 'the version is the first key written');
});

// ---- 4. the secret-omission rule --------------------------------------------------

test('encoding omits streamUrl for a secret-backed source and keeps the reference', function () {
  const CC = loadContracts();
  const state = CC.decodeState(ADDITIVE_V1);
  const encoded = CC.encodeState(state);
  const json = JSON.parse(encoded);
  assert.equal(Object.prototype.hasOwnProperty.call(json.sources[1], 'streamUrl'), false);
  assert.equal(json.sources[1].streamSecretRef, 'secret:ccloud-live-s-2');
  assert.equal(json.sources[0].streamUrl, 'https://stream.example/irib1.m3u8');
  assert.ok(
    encoded.indexOf('secret:ccloud-live-s-2') !== -1,
    'the secret reference itself is written, so omitting the address cannot also drop the reference'
  );
  assert.deepEqual(CC.migrate(encoded), state, 'a secret-backed source round-trips');
});

test('a source with neither an address nor a secret reference is rejected', function () {
  const CC = loadContracts();
  throwsMessage(
    'streamUrl is required unless the address is held in a streamSecretRef',
    function () {
      CC.decodeState(ADDRESSLESS_SOURCE);
    },
    'an addressless source'
  );
  throwsMessage(
    'streamUrl is required unless the address is held in a streamSecretRef',
    function () {
      CC.decodeState(mutate('null streamUrl', ADDRESSLESS_SOURCE, '"protocolHint":"hls",', '"streamUrl":null,"protocolHint":"hls",'));
    },
    'a null streamUrl without a secret reference'
  );
});

// ---- 5. fail-closed on malformed input --------------------------------------------

test('an unsupported schema version is refused on read and on write', function () {
  const CC = loadContracts();
  const future = mutate('schemaVersion 2', ADDITIVE_V1, '"schemaVersion": 1,', '"schemaVersion": 2,');
  throwsMessage('Unsupported live catalog schema', function () {
    CC.decodeState(future);
  }, 'a future schema version on read');
  throwsMessage('Unsupported live catalog schema', function () {
    CC.migrate(future);
  }, 'a future schema version on migrate');
  const state = CC.decodeState(ADDITIVE_V1);
  state.schemaVersion = 2;
  throwsMessage('Unsupported live catalog schema', function () {
    CC.encodeState(state);
  }, 'a future schema version on write');
  state.schemaVersion = 0;
  throwsMessage('Unsupported live catalog schema', function () {
    CC.encodeState(state);
  }, 'a zero schema version on write');
});

test('a malformed schema version is malformed data, not a version problem', function () {
  const CC = loadContracts();
  const cases = [
    ['string schemaVersion', '"schemaVersion": "1",'],
    ['boolean schemaVersion', '"schemaVersion": true,'],
    ['fractional schemaVersion', '"schemaVersion": 1.5,'],
    ['absent schemaVersion', '']
  ];
  for (const entry of cases) {
    throwsMessage(
      /schemaVersion must be an integer|Unsupported live catalog schema/,
      (function (replacement) {
        return function () {
          CC.decodeState(mutate('schemaVersion shape', ADDITIVE_V1, '"schemaVersion": 1,', replacement));
        };
      })(entry[1]),
      entry[0]
    );
  }
});

test('malformed documents fail closed instead of clearing the catalog', function () {
  const CC = loadContracts();
  // Malformed text throws rather than returning an empty state: a caught parse error
  // would be indistinguishable from "the user has no playlists", and the next save would
  // then persist an empty catalog over the real one.
  assert.throws(function () {
    CC.decodeState('{ not json');
  }, 'malformed JSON text must throw');
  assert.throws(function () {
    CC.decodeState('');
  }, 'an empty document straight to decodeState must throw');
  throwsMessage('must be', function () {
    CC.decodeState('[1,2,3]');
  }, 'a top-level array');
  throwsMessage('must be', function () {
    CC.decodeState('"2026-01-01"');
  }, 'a top-level string');
  throwsMessage('must be', function () {
    CC.decodeState(null);
  }, 'a null document straight to decodeState');
  throwsMessage('must be', function () {
    CC.decodeState(7);
  }, 'a numeric document');
  throwsMessage('must be', function () {
    CC.encodeState(null);
  }, 'encoding a null state');
  throwsMessage('must be', function () {
    CC.encodeState('{"schemaVersion":1}');
  }, 'encoding a JSON string instead of a state');
});

test('a present-but-invalid field is never replaced by a default', function () {
  const CC = loadContracts();
  const cases = [
    ['unknown rendererCapability', '"rendererCapability": "Supported",', '"rendererCapability": "Probably",'],
    ['non-string rendererCapability', '"rendererCapability": "Supported",', '"rendererCapability": 3,'],
    ['unknown sourceType', '"sourceType": "builtIn"', '"sourceType": "torrent"'],
    ['unknown health', '"health": "available"', '"health": "weird"'],
    ['unknown origin', '"origin": "playlist"', '"origin": "magic"'],
    ['non-list playlists', '"playlists": [', '"playlists": 7, "ignored": ['],
    ['non-list recentWatches', '"logicalIdByMemberId": {', '"recentWatches": 7,\n  "logicalIdByMemberId": {'],
    ['non-timestamp createdAt', '"createdAt": "2026-01-01T00:00:00Z",', '"createdAt": "yesterday",'],
    ['non-string playlist name', '"name": "CCloud",', '"name": 7,'],
    ['non-object sourcePolicy', '"sourcePolicy": {', '"sourcePolicy": 5, "policyBody": {'],
    ['non-string preference flag', '"favorite": true,', '"favorite": "yes",'],
    ['non-integer member ordinal', '"ordinal": 0', '"ordinal": "first"'],
    ['fractional priority', '"priority": 0,', '"priority": 0.5,']
  ];
  for (const entry of cases) {
    throwsMessage('live catalog', (function (target, replacement) {
      return function () {
        CC.decodeState(mutate(entry[0], ADDITIVE_V1, target, replacement));
      };
    })(entry[1], entry[2]), entry[0]);
  }
  // `true` is not a number in JS, so an unknown enum label cannot sneak in as 1 either.
  throwsMessage('live catalog', function () {
    CC.decodeState(mutate('boolean channelCount', ADDITIVE_V1, '"channelCount": 62,', '"channelCount": true,'));
  }, 'a boolean channelCount');
});

test('a non-RFC3339 timestamp is refused rather than parsed loosely', function () {
  const CC = loadContracts();
  // `new Date(text)` would happily accept "2026-01-01", "2026/01/01" and vendor
  // spellings that the Dart and Swift readers reject, so the shape is checked first.
  // The rejected spellings are the ones `new Date` accepts, plus two the shape rule
  // catches on its own: a one-digit component and hour 24, both of which the Dart and
  // Swift readers refuse.
  const rejected = [
    '2026-01-01',
    '2026-01-01T00:00:00',
    'not a timestamp',
    '2026-01-01T00:00:00+0500',
    '2026-1-01T00:00:00Z',
    '2026-01-01T00:00:00.1Z',
    '2026-01-01T24:00:00Z'
  ];
  for (const value of rejected) {
    throwsMessage(
      'is not an RFC 3339 timestamp',
      (function (text) {
        return function () {
          CC.decodeState(mutate('createdAt shape', ADDITIVE_V1, '"createdAt": "2026-01-01T00:00:00Z",', '"createdAt": "' + text + '",'));
        };
      })(value),
      'a ' + value + ' timestamp'
    );
  }
  // Calendar validity is a separate rule from the shape and carries its own message, and it
  // is the part a delegated parser cannot be trusted with: `new Date` answers each value
  // below with a real day further into the year instead of refusing it, which would store a
  // different date than the user wrote.
  const calendarRejected = [
    '2026-02-31T00:00:00Z',
    '2026-02-29T00:00:00Z',
    '2026-04-31T00:00:00Z',
    '2026-13-01T00:00:00Z',
    '2026-00-10T00:00:00Z',
    '2026-01-00T00:00:00Z'
  ];
  for (const value of calendarRejected) {
    throwsMessage(
      'is not a real calendar instant',
      (function (text) {
        return function () {
          CC.decodeState(mutate('calendar ' + text, ADDITIVE_V1, '"createdAt": "2026-01-01T00:00:00Z",', '"createdAt": "' + text + '",'));
        };
      })(value),
      'a ' + value + ' calendar day'
    );
  }
  // The accepted spellings are exactly the two the format clause allows, plus an offset,
  // and each normalizes to canonical UTC text. `2026-01-01T00:00:00Z` with no fraction is
  // the form the frozen `catalog-v1.json` fixture carries, so refusing it would make this
  // port unable to read the document all three ports agree on.
  const accepted = [
    ['2026-01-01T00:00:00Z', '2026-01-01T00:00:00.000Z'],
    ['2026-01-01T00:00:00.123Z', '2026-01-01T00:00:00.123Z'],
    ['2026-01-01T05:30:00.000+05:30', '2026-01-01T00:00:00.000Z'],
    ['2026-01-01T21:00:00.000-03:00', '2026-01-02T00:00:00.000Z'],
    // The leap rule has to be a rule and not a blanket "February stops at 28", so the pair
    // sits in the same table as the refusals above.
    ['2028-02-29T00:00:00Z', '2028-02-29T00:00:00.000Z']
  ];
  for (const entry of accepted) {
    const normalized = CC.decodeState(
      mutate('accepted ' + entry[0], ADDITIVE_V1, '"createdAt": "2026-01-01T00:00:00Z",', '"createdAt": ' + '"' + entry[0] + '",')
    );
    assert.equal(
      normalized.playlists[0].createdAt,
      entry[1],
      'a ' + entry[0] + ' timestamp must normalize to ' + entry[1]
    );
  }
  const offset = CC.decodeState(
    mutate('offset instant', ADDITIVE_V1, '"createdAt": "2026-01-01T00:00:00Z",', '"createdAt": "2026-01-01T05:00:00+05:00",')
  );
  assert.equal(offset.playlists[0].createdAt, '2026-01-01T00:00:00.000Z');
  assert.equal(Date.parse(offset.playlists[0].createdAt), PINNED_EPOCH_MS);
});

// ---- 6. runtime-only shapes -------------------------------------------------------

test('attempt context is identity only, validated and never persisted', function () {
  const CC = loadContracts();
  const attempt = CC.attemptContext('gen-1', 'builtin:live', 'ch-1', 's-1', 1, 'identity-1');
  assert.deepEqual(attempt, {
    requestGeneration: 'gen-1',
    playlistId: 'builtin:live',
    logicalChannelId: 'ch-1',
    sourceId: 's-1',
    attemptNumber: 1,
    stableMediaIdentity: 'identity-1'
  });
  assert.deepEqual(Object.keys(attempt), [
    'requestGeneration',
    'playlistId',
    'logicalChannelId',
    'sourceId',
    'attemptNumber',
    'stableMediaIdentity'
  ]);
  throwsMessage('live catalog', function () {
    CC.attemptContext('gen-1', 'pl', 'ch', 's', 'first', 'id');
  }, 'a non-integer attempt number');
  throwsMessage('live catalog', function () {
    CC.attemptContext('gen-1', 'pl', 'ch', 's', 1, undefined);
  }, 'a missing media identity');
  // A stale generation must be distinguishable, or a callback from a superseded player
  // session could commit state for a channel the user already left.
  const stale = CC.attemptContext('gen-0', 'builtin:live', 'ch-1', 's-1', 1, 'identity-1');
  assert.notEqual(JSON.stringify(stale), JSON.stringify(attempt));
  const encoded = CC.encodeState(CC.emptyState());
  assert.ok(encoded.indexOf('requestGeneration') === -1, 'an attempt is not part of stored state');
});

test('playback context copies the candidate order it is given', function () {
  const CC = loadContracts();
  const sourceIds = ['s-1', 's-2'];
  const policy = CC.standardSourcePolicy();
  const context = CC.liveContext('builtin:live', 'ch-1', sourceIds, true, policy);
  assert.deepEqual(context.sourceIds, ['s-1', 's-2']);
  sourceIds.push('s-3');
  policy.maxAutomaticAttempts = 99;
  policy.backoffMs = [];
  // Candidate order is the failover specification, and a policy edited after the attempt
  // started must not change a running attempt.
  assert.deepEqual(context.sourceIds, ['s-1', 's-2']);
  assert.equal(context.sourcePolicy.maxAutomaticAttempts, 3);
  assert.deepEqual(context.sourcePolicy.backoffMs, [500, 1500, 4000]);
  throwsMessage('live catalog', function () {
    CC.liveContext('pl', 'ch', 's-1', true, CC.standardSourcePolicy());
  }, 'a non-array candidate list');
  throwsMessage('live catalog', function () {
    CC.liveContext('pl', 'ch', ['s-1'], 'yes', CC.standardSourcePolicy());
  }, 'a non-boolean failover flag');
});

test('catalog issues normalize an absent line to null', function () {
  const CC = loadContracts();
  assert.deepEqual(CC.issue('playlist_unreachable', 'Playlist unreachable', 12), {
    code: 'playlist_unreachable',
    message: 'Playlist unreachable',
    line: 12
  });
  assert.deepEqual(CC.issue('no_tvg', 'No TVG id'), {
    code: 'no_tvg',
    message: 'No TVG id',
    line: null
  });
  throwsMessage('live catalog', function () {
    CC.issue('a', 'b', '12');
  }, 'a non-integer line');
  throwsMessage('live catalog', function () {
    CC.issue(null, 'b');
  }, 'a missing issue code');
});

test('a unified snapshot is timestamped canonically and leaks no secret address', function () {
  const CC = loadContracts();
  const state = CC.decodeState(ADDITIVE_V1);
  const channel = {
    channelId: 'ch-1',
    displayName: 'IRIB 1',
    normalizedName: 'irib 1',
    logoUrl: null,
    category: 'General',
    countryCode: 'IR',
    languages: ['fa'],
    memberIds: ['m-1', 'm-2'],
    sources: [state.sources[1], state.sources[0]],
    favorite: true,
    hidden: false,
    userOrder: null,
    automaticFailoverEnabled: true,
    sourcePolicy: CC.standardSourcePolicy(),
    lastSuccessfulSourceId: 's-2'
  };
  const snapshot = CC.snapshot(
    4,
    '2026-01-01T00:00:00Z',
    state.playlists,
    [channel],
    [CC.issue('playlist_unreachable', 'Playlist unreachable', 12)]
  );
  assert.equal(snapshot.revision, 4);
  assert.equal(snapshot.generatedAt, '2026-01-01T00:00:00.000Z');
  assert.equal(snapshot.playlists.length, 2);
  assert.equal(snapshot.channels.length, 1);
  assert.equal(snapshot.channels[0].sources.length, 2);
  assert.deepEqual(snapshot.channels[0].memberIds, ['m-1', 'm-2']);
  assert.deepEqual(snapshot.issues[0], {
    code: 'playlist_unreachable',
    message: 'Playlist unreachable',
    line: 12
  });
  // Two sources, one addressed and one secret-backed: the omission rule has to hold for
  // the second while the first keeps its address, which a blanket "no streamUrl text"
  // assertion could not tell apart.
  assert.equal(snapshot.channels[0].sources[1].streamUrl, 'https://stream.example/irib1.m3u8');
  assert.equal(
    Object.prototype.hasOwnProperty.call(snapshot.channels[0].sources[0], 'streamUrl'),
    false
  );
  const text = JSON.stringify(snapshot);
  assert.ok(text.indexOf('"streamUrl":"https://stream.example/irib1.m3u8"') !== -1);
  assert.equal(text.split('"streamUrl"').length - 1, 1, 'one address key for two sources');
  assert.ok(text.indexOf('"generatedAt":"2026-01-01T00:00:00.000Z"') !== -1);
  throwsMessage('live catalog', function () {
    CC.snapshot(1, 'yesterday', [], [], []);
  }, 'a snapshot with an unparseable generation time');
  throwsMessage('live catalog', function () {
    CC.snapshot(1, '2026-01-01T00:00:00Z', [], [{}], []);
  }, 'a snapshot with an empty channel');
});

// ---- 7. the legacy stores and the language ceiling --------------------------------

test('the legacy webOS document is still the shape B4 must migrate from', function () {
  const bytes = fs.readFileSync(LEGACY_FIXTURE_PATH);
  const text = bytes.toString('utf8');
  // Pinned byte for byte: B4-J's migration reads this shape, and a fixture quietly
  // edited to look like the new contract would make that test prove nothing.
  assert.equal(
    text,
    '{"ccloud.favorites":[{"item":{"id":7,"title":"Legacy Movie"},"addedAt":"2026-01-02T03:04:05Z"}],' +
      '"ccloud.history":[{"item":{"id":7,"title":"Legacy Movie"},"lastWatchedAt":"2026-01-03T03:04:05Z","progress":0.5,"episodes":[]}],' +
      '"ccloud.settings":{"appearance":"dark","preferredQuality":"auto"}}'
  );
  assert.equal(Buffer.compare(Buffer.from(text, 'utf8'), bytes), 0);
  const parsed = JSON.parse(text);
  assert.deepEqual(Object.keys(parsed), [
    'ccloud.favorites',
    'ccloud.history',
    'ccloud.settings'
  ]);
  assert.equal(parsed['ccloud.favorites'][0].item.title, 'Legacy Movie');
  assert.equal(parsed['ccloud.history'][0].progress, 0.5);

  // The contract layer does not read those keys, and refuses to treat the legacy document
  // as a catalog: silently returning an empty state here would let B4's first save erase
  // the user's favorites.
  const CC = loadContracts();
  throwsMessage('live catalog', function () {
    CC.decodeState(text);
  }, 'the legacy storage document');
  throwsMessage('live catalog', function () {
    CC.migrate(text);
  }, 'the legacy storage document through migrate');
});

// A crude slice is enough here and is deliberately not a JavaScript tokenizer: the module
// this scans is one IIFE of plain ES5-style code, so the only comment markers in the file
// are the ones this removes, and every string literal in it is quoted on one line.
function codeOnly(source) {
  var out = '';
  var i = 0;
  while (i < source.length) {
    if (source[i] === '/' && source[i + 1] === '/') {
      while (i < source.length && source[i] !== '\n') {
        i += 1;
      }
      continue;
    }
    if (source[i] === '/' && source[i + 1] === '*') {
      i += 2;
      while (i < source.length && !(source[i] === '*' && source[i + 1] === '/')) {
        if (source[i] === '\n') {
          out += '\n';
        }
        i += 1;
      }
      i += 2;
      continue;
    }
    if (source[i] === '"' || source[i] === "'") {
      var quote = source[i];
      out += quote;
      i += 1;
      while (i < source.length && source[i] !== quote) {
        if (source[i] === '\\') {
          out += source[i];
          i += 1;
        }
        out += source[i];
        i += 1;
      }
      out += quote;
      i += 1;
      continue;
    }
    out += source[i];
    i += 1;
  }
  return out;
}

test('the module stays inside the language ceiling the webOS build is checked against', function () {
  const code = codeOnly(moduleSource());
  // Split into two lists, because the two reasons are different and a single list would
  // misreport both. The first group is the runtime ceiling: `webos_app` ships to webOS 4,
  // whose Chromium 68 has no optional chaining, nullish coalescing, `flat`, `flatMap`,
  // `globalThis` or `Object.fromEntries`, so one of those is a TypeError on the TV that no
  // laptop run reproduces. `node --check`, which is what CI actually executes, accepts all
  // of them, so the ceiling has to be enforced by text.
  const runtimeCeiling = [
    ['optional chaining', /\?\./],
    ['nullish coalescing', /\?\?/],
    ['Array.prototype.flat', /\.flat\(/],
    ['Array.prototype.flatMap', /\.flatMap\(/],
    ['Object.fromEntries', /Object\.fromEntries/],
    ['Object.entries', /Object\.entries/],
    ['globalThis', /\bglobalThis\b/],
    ['BigInt', /\bBigInt\b/],
    ['logical assignment', /(\|\||&&|\?\?)=/],
    ['private class field', /#[A-Za-z]/]
  ];
  for (const entry of runtimeCeiling) {
    assert.equal(
      entry[1].test(code),
      false,
      MODULE_NAME + ' must not use ' + entry[0] + ' (Chromium 68 ceiling)'
    );
  }
  // The second group is the repository's style ceiling, not a runtime requirement: every
  // other file in `webos_app/app/js` is ES5-shaped (`var`, function expressions, string
  // concatenation), and `store.js:70` is the timestamp idiom this codec pins. Keeping one
  // idiom across the bundle is what lets a reader audit the whole file without wondering
  // which constructs the oldest device in the field supports.
  const repoStyle = [
    ['arrow function', /=>/],
    ['template literal', /`/],
    ['const declaration', /(^|[^\w$.])const\s/],
    ['let declaration', /(^|[^\w$.])let\s/],
    ['class declaration', /(^|[^\w$.])class\s/],
    ['async function', /(^|[^\w$.])async\s+function/],
    ['await expression', /(^|[^\w$.])await\s/],
    ['spread or rest operator', /\.\.\./]
  ];
  for (const entry of repoStyle) {
    assert.equal(
      entry[1].test(code),
      false,
      MODULE_NAME + ' should stay in the ES5-shaped idiom of webos_app/app/js: ' + entry[0]
    );
  }
  assert.ok(/\bfor\s*\(/.test(code), 'the module walks its lists with explicit index loops');
  assert.ok(
    /^window\.CC = window\.CC \|\| \{\};$/m.test(code),
    'the module attaches to the existing CC namespace instead of replacing it'
  );
  // A contract layer that reached for storage or the network could not be tested without a
  // device, and device runs are not available here.
  for (const forbidden of [
    'localStorage',
    'sessionStorage',
    'indexedDB',
    'fetch(',
    'XMLHttpRequest',
    'require(',
    'document.',
    'WebSocket'
  ]) {
    assert.ok(code.indexOf(forbidden) === -1, MODULE_NAME + ' must not touch ' + forbidden);
  }
});
