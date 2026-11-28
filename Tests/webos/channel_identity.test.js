'use strict';

// Task B3-J: the webOS half of logical channel identity and the unified catalog view.
//
// This is the JavaScript repeat of `flutter_app/test/channel_identity_test.dart` and the
// `Multi-source channel identity` block of `Tests/live-foundation/main.swift`. The fixture IDs, names and
// expected verdicts below are deliberately the same literals the Swift block uses (`member:press-a`,
// «Namayesh», `builtin:ccloud`, the `[0, 1, 2]` ordinals) rather than a fresh set, because the whole value of
// a third port is that a *pair of rows*, not a test plan, produces the same score everywhere: a user who
// merges two rows on the Mac must see one channel on a phone and one channel on a TV.
//
// Two rules govern this file. First, nothing here invents a digest or a fold: `normalizedName` is produced by
// the real `nameKey` from the real parser, the identity recipes are compared against the real
// `stableKeyHash`, and the fold-seam pins (`press tv 720p`, `press tv`) are literals already green in
// `Tests/webos/playlist_parser.test.js:246-247`. Second, the checks are written to fail on a *semantic*
// change — a re-rolled validation order, a merge that rewrites a source ID, a view that filters disabled
// sources, an adapter that guesses a logo — and not on a rename.
//
// The modules are loaded into ONE sealed scope, unlike `Tests/webos/playlist_parser.test.js:76`, because
// `unified_catalog.js` resolves `CC.channelIdentity` and `CC.playlistContracts` at call time and
// `builtin_catalog_adapter.js` resolves `CC.playlistParser`: a per-file scope would test three modules that
// were never wired to each other, which is precisely how a namespace-name typo survives to a TV. The sealing
// rationale is unchanged — every browser and host I/O global is shadowed by a parameter, so a module that
// reached for storage, the network or the DOM throws here instead of passing on a laptop.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const ROOT = path.resolve(__dirname, '../..');
const JS_DIR = 'webos_app/app/js';
const FIXTURE_DIR = path.join(ROOT, 'Tests/fixtures/multi-source');

const CONTRACTS_MODULE = 'playlist_contracts.js';
const PARSER_MODULE = 'playlist_parser.js';
const IDENTITY_MODULE = 'channel_identity.js';
const CATALOG_MODULE = 'unified_catalog.js';
const ADAPTER_MODULE = 'builtin_catalog_adapter.js';

// Load order is the order task B4-J registers these files in `index.html`, so a module that silently depends
// on a sibling being evaluated first fails here rather than only on a device.
const MODULES = [
  CONTRACTS_MODULE,
  PARSER_MODULE,
  IDENTITY_MODULE,
  CATALOG_MODULE,
  ADAPTER_MODULE
];

const IDENTITY_API = [
  'ambiguityFloor',
  'findCandidate',
  'logicalIdOf',
  'membersOfLogicalChannel',
  'associate',
  'separate',
  'seedSingletonChannels'
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

function loadInto(scope, moduleName) {
  const modulePath = path.join(ROOT, JS_DIR, moduleName);
  if (!fs.existsSync(modulePath)) {
    assert.fail(moduleName + ' is missing; task B3-J owns this file');
  }
  const values = SEALED_GLOBALS.map(function (key) {
    return key === 'window' ? scope : undefined;
  });
  const factory = Function.apply(
    null,
    SEALED_GLOBALS.concat(['"use strict";\n' + fs.readFileSync(modulePath, 'utf8')])
  );
  try {
    factory.apply(null, values);
  } catch (error) {
    assert.fail(moduleName + ' could not be evaluated inertly: ' + error.message);
  }
  return scope;
}

function loadGroup(names) {
  const scope = {};
  for (const name of names) {
    loadInto(scope, name);
  }
  if (!scope.CC) {
    assert.fail('the B3-J modules attached no CC namespace to window');
  }
  return scope.CC;
}

const NS = loadGroup(MODULES);
const K = NS.playlistContracts;
const P = NS.playlistParser;
const ID = NS.channelIdentity;
const UC = NS.unifiedCatalog;

function fixture(name) {
  const file = path.join(FIXTURE_DIR, name);
  if (!fs.existsSync(file)) {
    assert.fail('fixture ' + name + ' is missing; the three suites share these exact files');
  }
  return fs.readFileSync(file, 'utf8');
}

// ---- fixtures mirroring the Swift helpers ---------------------------------------------------------

const BUILTIN_PLAYLIST = 'builtin:ccloud';
// The canonical spelling the codec itself produces: `requireTimestamp` validates the pattern and then
// returns `new Date(text).toISOString()` (`playlist_contracts.js:191-231`), so every timestamp comes back
// with three fractional digits whatever the document held. Section 10 round-trips whole state graphs
// through `encodeState`/`decodeState`, and an anchor written in the shorter second-precision form would
// come back unequal to itself — that is the codec normalizing, not a bug, so the fixture uses the form the
// codec emits and a dedicated assertion below pins the normalization instead of hiding it.
const NOW = '2026-11-25T00:00:00.000Z';
const LEGACY_NOW = '2026-11-25T00:00:00Z';

// `identityPlaylist` in Swift: every field the contract requires, so the same state can be handed to
// `encodeState` without a second set of fixtures.
function playlistRow(id, enabled) {
  return {
    playlistId: id,
    name: id,
    sourceType: 'remoteUrl',
    locationRef: 'https://cdn.example/' + id + '.m3u',
    enabled: enabled === undefined ? true : enabled,
    createdAt: NOW,
    lastUpdatedAt: null,
    lastSuccessfulRefresh: null,
    refreshStatus: 'ready',
    lastErrorCode: null,
    channelCount: 0,
    parsingVersion: 1
  };
}

// `identityMember` in Swift: `normalizedName` comes from the production fold, so these checks exercise the
// scoring rules rather than a hand-written guess at what the fold produces. The short override names
// (`namespace`, `providerId`, `country`, `logo`) are the Swift parameter names, resolved to the persisted
// field names here — an override that silently added a `namespace` key instead of setting
// `providerNamespace` would make a cross-namespace case pass for the wrong reason.
const MEMBER_OVERRIDE_FIELDS = {
  namespace: 'providerNamespace',
  providerId: 'providerChannelId',
  country: 'countryCode',
  logo: 'logoUrl'
};

function memberRow(id, name, fields) {
  const row = {
    memberId: id,
    playlistId: 'playlist:a',
    providerNamespace: 'famelack',
    providerChannelId: '',
    displayName: name,
    normalizedName: P.nameKey(name),
    ordinal: 0,
    logoUrl: null,
    group: null,
    countryCode: null,
    languages: ['fas'],
    tvgId: null
  };
  const overrides = fields || {};
  const keys = Object.keys(overrides);
  for (let i = 0; i < keys.length; i += 1) {
    const target = MEMBER_OVERRIDE_FIELDS[keys[i]] === undefined ? keys[i] : MEMBER_OVERRIDE_FIELDS[keys[i]];
    assert.ok(
      Object.prototype.hasOwnProperty.call(row, target),
      'unknown member field in a fixture: ' + keys[i]
    );
    row[target] = overrides[keys[i]];
  }
  return row;
}

// `identitySource` in Swift: 17 fields, same names and same order the ports persist.
function sourceRow(id, fields) {
  const settings = fields || {};
  const priority = settings.priority === undefined ? 0 : settings.priority;
  const row = {
    sourceId: id,
    channelId: settings.channelId,
    memberId: settings.memberId,
    playlistId: settings.playlistId === undefined ? 'playlist:a' : settings.playlistId,
    providerNamespace: settings.namespace === undefined ? 'famelack' : settings.namespace,
    label: 'منبع ' + P.persianDigits(priority + 1),
    streamUrl: settings.url === undefined ? 'https://cdn.example/' + id + '.m3u8' : settings.url,
    streamSecretRef: null,
    protocolHint: 'm3u8',
    rendererCapability: 'Not Yet Verified',
    origin: 'playlist',
    priority: priority,
    enabled: settings.enabled === undefined ? true : settings.enabled,
    health: 'unverified',
    lastSuccessfulPlaybackAt: null,
    lastFailedPlaybackAt: null,
    lastErrorCode: null
  };
  return row;
}

function preferenceRow(channelId, fields) {
  const settings = fields || {};
  return {
    channelId: channelId,
    favorite: settings.favorite === undefined ? false : settings.favorite,
    hidden: settings.hidden === undefined ? false : settings.hidden,
    category: settings.category === undefined ? null : settings.category,
    userOrder: settings.userOrder === undefined ? null : settings.userOrder,
    automaticFailoverEnabled:
      settings.automaticFailoverEnabled === undefined ? true : settings.automaticFailoverEnabled,
    sourcePolicy: settings.sourcePolicy === undefined ? K.standardSourcePolicy() : settings.sourcePolicy,
    lastSuccessfulSourceId:
      settings.lastSuccessfulSourceId === undefined ? null : settings.lastSuccessfulSourceId
  };
}

// `identityMapping` in Swift: every member is its own logical channel until a case says otherwise, which is
// exactly the Phase B rule that nothing associates itself.
function identityMapping(members) {
  const mapping = {};
  for (let i = 0; i < members.length; i += 1) {
    mapping[members[i].memberId] = members[i].memberId;
  }
  return mapping;
}

function stateOf(fields) {
  const settings = fields || {};
  const members = settings.members === undefined ? [] : settings.members;
  const state = K.emptyState();
  state.playlists = settings.playlists === undefined ? allPlaylists() : settings.playlists;
  state.members = members;
  state.sources = settings.sources === undefined ? [] : settings.sources;
  state.associations = settings.associations === undefined ? [] : settings.associations;
  state.preferences = settings.preferences === undefined ? [] : settings.preferences;
  state.logicalIdByMemberId =
    settings.mapping === undefined ? identityMapping(members) : settings.mapping;
  return state;
}

function allPlaylists() {
  return [playlistRow('playlist:a'), playlistRow('playlist:b'), playlistRow('playlist:c')];
}

function snapshot(value) {
  return JSON.stringify(value);
}

function channelIds(channels) {
  return channels.map(function (channel) {
    return channel.channelId;
  });
}

function sourceIds(rows) {
  return rows.map(function (row) {
    return row.sourceId;
  });
}

// Returns the refusal message, asserting that the call did throw. Every refusal is graded on its
// `ChannelIdentityError.<code>` text, because that string is the wire-visible contract across the ports.
function refusalMessage(thunk, label) {
  let thrown = null;
  try {
    thunk();
  } catch (error) {
    thrown = error;
  }
  assert.notEqual(thrown, null, label + ' must be refused');
  assert.equal(
    thrown.message.indexOf('ChannelIdentityError.'),
    0,
    label + ' must throw the shared code string, found: ' + thrown.message
  );
  return thrown.message;
}

function expectRefusal(code, thunk, label) {
  assert.equal(refusalMessage(thunk, label), 'ChannelIdentityError.' + code, label);
}

// ---- 1. namespace assembly and surface --------------------------------------------------------------

test('the five B3-J modules share one CC namespace and expose the surface task B4-J calls', function () {
  assert.deepEqual(
    Object.keys(NS).sort(),
    ['channelIdentity', 'playlistContracts', 'playlistParser', 'unifiedCatalog'],
    'the new modules must attach to the existing CC namespace rather than mint a second global'
  );
  assert.deepEqual(
    Object.keys(ID).sort(),
    IDENTITY_API.slice().sort(),
    'channel identity exposes exactly the functions the other two ports publish, so a screen cannot bind to a port-specific name'
  );
  assert.deepEqual(
    Object.keys(UC).sort(),
    ['build', 'registerBuiltIn'],
    'the built-in bridge lands on the catalog namespace it serves instead of becoming a second entry point'
  );
  // `ambiguityFloor` is a contract *value*, not a callable — Dart publishes
  // `channelCandidateAmbiguityFloor` and Swift `ChannelCandidate.ambiguityFloor` the same way — so the
  // surface check splits here instead of pretending every exported key is a function.
  for (const name of IDENTITY_API.filter(function (key) {
    return key !== 'ambiguityFloor';
  })) {
    assert.equal(typeof ID[name], 'function', '`' + name + '` must be callable');
  }
  assert.equal(typeof ID.ambiguityFloor, 'number', '`ambiguityFloor` must be comparable by a screen');
  assert.equal(typeof UC.build, 'function');
  assert.equal(typeof UC.registerBuiltIn, 'function');
});

test('the ambiguity floor is a contract value, not a screen-side guess', function () {
  assert.equal(ID.ambiguityFloor, 85, 'the same floor the Swift and Dart ports publish');
  const atFloor = ID.findCandidate(
    memberRow('member:fl-a', 'Chahar', { countryCode: 'IR', logo: 'https://img.example/4.png' }),
    memberRow('member:fl-b', 'Chahar', { playlistId: 'playlist:b', countryCode: 'IR', logo: 'https://img.example/4.png' })
  );
  const belowFloor = ID.findCandidate(
    memberRow('member:fl-c', 'Panj', { countryCode: 'IR' }),
    memberRow('member:fl-d', 'Panj', { playlistId: 'playlist:b', countryCode: 'IR' })
  );
  assert.equal(atFloor.score, ID.ambiguityFloor);
  assert.equal(atFloor.ambiguous, false, 'a pair exactly at the floor may be offered plainly');
  assert.equal(belowFloor.score, ID.ambiguityFloor - 10, 'the next tier down is 75, so one point decides the verdict');
  assert.equal(belowFloor.ambiguous, true, 'and a screen reading the exported floor warns on the same pair');
});

// ---- 2. the candidate ladder, tier by tier ----------------------------------------------------------

test('equal namespaced provider IDs plus a matching name and country score 95', function () {
  const top = ID.findCandidate(
    memberRow('member:press-a', 'Press TV', {
      providerChannelId: 'PressTV',
      countryCode: 'IR',
      logoUrl: 'https://img.example/press.png'
    }),
    memberRow('member:press-b', 'Press TV', {
      playlistId: 'playlist:b',
      providerChannelId: 'PressTV',
      countryCode: 'IR',
      logoUrl: 'https://img.example/press.png'
    })
  );
  assert.equal(top.score, 95);
  assert.equal(top.evidence, 'exactProviderId');
  assert.equal(top.ambiguous, false, 'the strongest tier clears the floor, so the screen may offer it plainly');
  assert.equal(top.leftMemberId, 'member:press-a');
  assert.equal(top.rightMemberId, 'member:press-b', 'the candidate names its pair in argument order');
});

test('a provider match with no country on either side is still the top tier', function () {
  const gold = ID.findCandidate(
    memberRow('member:gold-a', 'Golden', { namespace: 'iptv-org', providerChannelId: 'GOLD' }),
    memberRow('member:gold-b', 'Golden', {
      playlistId: 'playlist:b',
      namespace: 'iptv-org',
      providerChannelId: 'GOLD'
    })
  );
  assert.equal(gold.score, 90, 'nothing contradicts the pair, so it stays in the provider tier');
  assert.equal(gold.evidence, 'exactProviderId');
  assert.equal(gold.ambiguous, false);
});

test('name, country and logo reach the floor exactly, and padded or lowercase values still compare', function () {
  const soft = ID.findCandidate(
    memberRow('member:soft-a', 'Namayesh', { countryCode: 'ir', logoUrl: ' https://img.example/n.png ' }),
    memberRow('member:soft-b', 'Namayesh', {
      playlistId: 'playlist:b',
      countryCode: 'IR',
      logoUrl: 'https://img.example/n.png'
    })
  );
  assert.equal(soft.score, 85);
  assert.equal(soft.evidence, 'exactNameCountryLogo');
  assert.equal(soft.ambiguous, false, 'trailing whitespace and a lowercase ISO code are storage noise');
});

test('without a logo the same pair drops under the floor', function () {
  const pair = ID.findCandidate(
    memberRow('member:c75-a', 'Share', { countryCode: 'IR' }),
    memberRow('member:c75-b', 'Share', { playlistId: 'playlist:b', countryCode: 'IR' })
  );
  assert.equal(pair.score, 75);
  assert.equal(pair.evidence, 'exactNameCountry');
  assert.equal(pair.ambiguous, true, 'a suggestion the user must confirm');
});

test('a shared logo never substitutes for a missing country', function () {
  const pair = ID.findCandidate(
    memberRow('member:l70-a', 'Barsa', { logoUrl: 'https://img.example/b.png' }),
    memberRow('member:l70-b', 'Barsa', { playlistId: 'playlist:b', logoUrl: 'https://img.example/b.png' })
  );
  assert.equal(pair.score, 70);
  assert.equal(pair.evidence, 'exactNameLogo');
  assert.equal(pair.ambiguous, true);
});

test('an identical name alone is the weakest evidence the ladder will still report', function () {
  const pair = ID.findCandidate(
    memberRow('member:n50-a', 'Generic'),
    memberRow('member:n50-b', 'Generic', { playlistId: 'playlist:b' })
  );
  assert.equal(pair.score, 50);
  assert.equal(pair.evidence, 'exactNameOnly');
  assert.equal(pair.ambiguous, true);
});

test('a member is never a candidate for itself', function () {
  assert.equal(ID.findCandidate(memberRow('member:same', 'Self'), memberRow('member:same', 'Self')), null);
});

test('different names produce no candidate at all rather than a low score', function () {
  assert.equal(ID.findCandidate(memberRow('member:x1', 'Alpha'), memberRow('member:x2', 'Beta')), null);
});

test('a name that folds to nothing is not evidence, however many rows share it', function () {
  // The fold is the parser's, so this first asserts what the shared fold actually produces before it asserts
  // the verdict the three ports agree on.
  assert.equal(P.nameKey('—'), '', 'the em dash leaves no key behind');
  assert.equal(
    ID.findCandidate(
      memberRow('member:x3', '—'),
      memberRow('member:x4', '—', { playlistId: 'playlist:b' })
    ),
    null
  );
});

// ---- 3. normalization and contradiction -------------------------------------------------------------

test('equal raw provider IDs under different namespaces are two unrelated strings', function () {
  const cross = ID.findCandidate(
    memberRow('member:xn-a', 'Press TV', {
      namespace: 'famelack',
      providerChannelId: 'PressTV',
      countryCode: 'IR',
      logoUrl: 'https://img.example/p.png'
    }),
    memberRow('member:xn-b', 'Press TV', {
      playlistId: 'playlist:b',
      namespace: 'iptv-org',
      providerChannelId: 'PressTV',
      countryCode: 'IR',
      logoUrl: 'https://img.example/p.png'
    })
  );
  assert.equal(cross.score, 85, 'the pair falls through to the name tiers instead of scoring 90+');
  assert.equal(cross.evidence, 'exactNameCountryLogo');
  assert.equal(cross.ambiguous, false, 'a different namespace says nothing either way, so it is not a conflict');
});

test('two different provider IDs in one namespace are a conflict no matching text can clear', function () {
  const conflict = ID.findCandidate(
    memberRow('member:ic-a', 'Press TV', {
      namespace: 'iptv-org',
      providerChannelId: 'PRESS-A',
      countryCode: 'IR',
      logoUrl: 'https://img.example/p.png'
    }),
    memberRow('member:ic-b', 'Press TV', {
      playlistId: 'playlist:b',
      namespace: 'iptv-org',
      providerChannelId: 'PRESS-B',
      countryCode: 'IR',
      logoUrl: 'https://img.example/p.png'
    })
  );
  assert.equal(conflict.score, 85, 'the score is still what the evidence supports');
  assert.equal(conflict.ambiguous, true, 'but the contradiction makes even the floor tier a confirmation');
});

test('a contradiction on country demotes even the 90 tier', function () {
  const pair = ID.findCandidate(
    memberRow('member:cc-a', 'Press TV', {
      namespace: 'iptv-org',
      providerChannelId: 'PressTV',
      countryCode: 'IR'
    }),
    memberRow('member:cc-b', 'Press TV', {
      playlistId: 'playlist:b',
      namespace: 'iptv-org',
      providerChannelId: 'PressTV',
      countryCode: 'GB'
    })
  );
  assert.equal(pair.score, 90);
  assert.equal(pair.evidence, 'exactProviderId');
  assert.equal(pair.ambiguous, true, 'one provider ID cannot be two countries');
});

test('a blank country is unknown, not a country named the empty string', function () {
  const pair = ID.findCandidate(
    memberRow('member:bl-a', 'Kalemeh', { countryCode: '   ', logoUrl: 'https://img.example/k.png' }),
    memberRow('member:bl-b', 'Kalemeh', { playlistId: 'playlist:b', countryCode: 'IR', logoUrl: 'https://img.example/k.png' })
  );
  assert.equal(pair.score, 70, 'an unknown value cannot match, so the pair drops to the logo tier');
  assert.equal(pair.evidence, 'exactNameLogo');
  assert.equal(pair.ambiguous, true, 'and it cannot conflict either — the flag comes from the score alone');
});

test('logos are compared as given and never canonicalized', function () {
  const pair = ID.findCandidate(
    memberRow('member:lg-a', 'Xahar', { countryCode: 'IR', logoUrl: 'irib1.png' }),
    memberRow('member:lg-b', 'Xahar', { playlistId: 'playlist:b', countryCode: 'IR', logoUrl: '/logos/irib1.png' })
  );
  assert.equal(pair.score, 75, '`irib1.png` and `/logos/irib1.png` are two statements about provenance');
  assert.equal(pair.evidence, 'exactNameCountry');
});

test('padded provider IDs contradict rather than match, because the ID is stored text', function () {
  const pair = ID.findCandidate(
    memberRow('member:pd-a', 'Haft', { providerChannelId: ' SEVEN ', countryCode: 'IR', logoUrl: 'https://img.example/7.png' }),
    memberRow('member:pd-b', 'Haft', { playlistId: 'playlist:b', providerChannelId: 'SEVEN', countryCode: 'IR', logoUrl: 'https://img.example/7.png' })
  );
  assert.equal(pair.score, 85, 'the tier is the name evidence, not a provider match');
  assert.equal(pair.evidence, 'exactNameCountryLogo');
  assert.equal(pair.ambiguous, true, 'two IDs that disagree within one namespace is a contradiction');
});

// ---- 4. the fold seam, driven through the real parser and the real adapter --------------------------

test('the identity layer invents no folding the parser did not perform', function () {
  assert.equal(P.nameKey('Press TV (720p)'), 'press tv 720p', 'already pinned in the B2-J suite');
  assert.equal(P.nameKey(P.displayName('Press TV (720p)')), 'press tv', 'noise stripping is a parse-time job');
  assert.equal(
    ID.findCandidate(
      memberRow('member:raw-a', 'Press TV (720p)'),
      memberRow('member:raw-b', 'Press TV', { playlistId: 'playlist:b' })
    ),
    null,
    'a raw quality token breaks the match, so this layer adds no folding of its own'
  );
});

test('through the parser the two rows are one station at the weakest tier', function () {
  const parsed = P.parsePlaylist('playlist:valid', fixture('valid.m3u'), null);
  const registered = P.registerParsedPlaylist(parsed, 'playlist:valid', 'famelack');
  const parsedPress = registered.members.filter(function (row) {
    return row.displayName === 'Press TV';
  })[0];
  assert.notEqual(parsedPress, undefined, 'the production parser strips the quality token from the fixture row');
  assert.equal(parsedPress.normalizedName, 'press tv');
  const pair = ID.findCandidate(
    memberRow('member:raw-b', 'Press TV', { playlistId: 'playlist:b' }),
    parsedPress
  );
  assert.equal(pair.score, 50);
  assert.equal(pair.evidence, 'exactNameOnly');
});

test('the shared script fold makes two spellings of one station comparable', function () {
  assert.equal(P.nameKey('كورد TV'), P.nameKey('کورد TV'), 'Arabic kaf and Persian keheh fold together');
  assert.equal(
    ID.findCandidate(
      memberRow('member:fold-a', 'كورد TV'),
      memberRow('member:fold-b', 'کورد TV', { playlistId: 'playlist:b' })
    ).score,
    50
  );
});

// ---- 5. mapping and group membership ----------------------------------------------------------------

test('an unmapped member is already a channel of its own', function () {
  const members = [memberRow('member:m1', 'One'), memberRow('member:m2', 'Two', { playlistId: 'playlist:b' })];
  const fresh = K.emptyState();
  fresh.members = members;
  fresh.playlists = allPlaylists();
  assert.equal(ID.logicalIdOf(fresh, 'member:m1'), 'member:m1', 'spec rule 4, so the first merge can succeed');
  assert.deepEqual(ID.membersOfLogicalChannel(fresh, 'member:m2'), ['member:m2']);
});

test('members of a channel come back in the order the user associated them', function () {
  const members = [memberRow('member:a1', 'One'), memberRow('member:a2', 'Two', { playlistId: 'playlist:b' })];
  const state = stateOf({
    members: members,
    associations: [{ memberIds: ['member:a2', 'member:a1'] }],
    mapping: { 'member:a1': 'member:a1', 'member:a2': 'member:a1' }
  });
  assert.deepEqual(
    ID.membersOfLogicalChannel(state, 'member:a1'),
    ['member:a2', 'member:a1'],
    'the recorded order wins over catalog order, because it is the user’s statement'
  );
  assert.deepEqual(
    ID.membersOfLogicalChannel(state, 'member:nothing'),
    [],
    'a channel no member names has no members rather than a crash'
  );
});

test('a member of a disabled playlist still belongs to its channel', function () {
  const members = [memberRow('member:d1', 'One'), memberRow('member:d2', 'Two', { playlistId: 'playlist:b' })];
  const state = stateOf({
    playlists: [playlistRow('playlist:a', true), playlistRow('playlist:b', false)],
    members: members,
    associations: [{ memberIds: ['member:d1', 'member:d2'] }],
    mapping: { 'member:d1': 'member:d1', 'member:d2': 'member:d1' }
  });
  assert.deepEqual(
    ID.membersOfLogicalChannel(state, 'member:d1'),
    ['member:d1', 'member:d2'],
    'an association is user data and must survive a disable/enable round trip'
  );
});

// ---- 6. associate ----------------------------------------------------------------------------------

const assocMembers = [
  memberRow('member:k1', 'One'),
  memberRow('member:k2', 'Two', { playlistId: 'playlist:b' }),
  memberRow('member:k3', 'Three', { playlistId: 'playlist:c' })
];
const assocState = stateOf({
  members: assocMembers,
  sources: [
    sourceRow('s1', { channelId: 'member:k1', memberId: 'member:k1', priority: 0 }),
    sourceRow('s2', { channelId: 'member:k1', memberId: 'member:k1', priority: 1 }),
    sourceRow('s3', { channelId: 'member:k2', memberId: 'member:k2', playlistId: 'playlist:b' }),
    sourceRow('s4', { channelId: 'member:k3', memberId: 'member:k3', playlistId: 'playlist:c' })
  ]
});

test('an association moves ownership and nothing else', function () {
  const before = snapshot(assocState);
  const merged = ID.associate(assocState, ['member:k2', 'member:k3'], 'member:k1');
  assert.notEqual(merged, assocState, 'a new value is returned rather than an in-place edit');
  assert.deepEqual(sourceIds(merged.sources), ['s1', 's2', 's3', 's4']);
  assert.deepEqual(
    merged.sources.map(function (row) {
      return row.priority;
    }),
    [0, 1, 0, 0],
    'source IDs, priorities and their stored order survive verbatim'
  );
  assert.deepEqual(
    merged.sources.map(function (row) {
      return row.channelId;
    }),
    ['member:k1', 'member:k1', 'member:k1', 'member:k1'],
    'every source of every joined member now names the preferred channel'
  );
  assert.deepEqual(
    merged.associations.map(function (row) {
      return row.memberIds;
    }),
    [['member:k1', 'member:k2', 'member:k3']],
    'the preferred channel’s own member comes first, then the newcomers in the order the user gave'
  );
  assert.deepEqual(merged.logicalIdByMemberId, {
    'member:k1': 'member:k1',
    'member:k2': 'member:k1',
    'member:k3': 'member:k1'
  }, 'the mapping is the only place the merge is recorded');
  assert.equal(merged.members.length, 3);
  assert.equal(snapshot(assocState), before, 'the state the caller handed in is untouched');
});

test('the merge preserves identity, ordering and history fields it has no business touching', function () {
  const merged = ID.associate(assocState, ['member:k2', 'member:k3'], 'member:k1');
  const moved = merged.sources[2];
  assert.equal(Object.keys(moved).length, 17, 'no field is dropped when a source is re-parented');
  assert.deepEqual(
    moved,
    Object.assign({}, assocState.sources[2], { channelId: 'member:k1' }),
    'only channelId changes on a re-parented row'
  );
  assert.notEqual(moved, assocState.sources[2], 'the moved row is a fresh value, not a shared mutable one');
  assert.equal(merged.sources[0], assocState.sources[0], 'an untouched row is carried by reference, as Dart’s unmodifiable views do');
  for (let i = 0; i < merged.members.length; i += 1) {
    assert.equal(merged.members[i], assocState.members[i], 'member rows are never edited in place');
  }
  assert.equal(merged.schemaVersion, assocState.schemaVersion);
  assert.deepEqual(merged.playlists.map(function (row) {
    return row.playlistId;
  }), ['playlist:a', 'playlist:b', 'playlist:c']);
});

test('a merge never rewrites the user’s own preference rows', function () {
  const preference = preferenceRow('member:k2', {
    favorite: true,
    category: 'Special',
    userOrder: 7,
    automaticFailoverEnabled: false,
    lastSuccessfulSourceId: 's3'
  });
  const withPreference = stateOf({ members: assocMembers, preferences: [preference] });
  const merged = ID.associate(withPreference, ['member:k2', 'member:k3'], 'member:k1');
  assert.equal(merged.preferences.length, 1);
  assert.equal(merged.preferences[0], preference, 'the preference keeps being keyed on the member’s own ID');
  assert.equal(merged.preferences[0].favorite, true);
  assert.equal(merged.preferences[0].userOrder, 7);
});

test('a second merge grows the existing channel instead of stacking associations', function () {
  const once = ID.associate(assocState, ['member:k1', 'member:k2'], 'member:k1');
  assert.equal(once.associations.length, 1);
  const twice = ID.associate(once, ['member:k3', 'member:k2'], 'member:k1');
  assert.equal(twice.associations.length, 1, 'the absorbed association is replaced, not appended to');
  assert.deepEqual(twice.associations[0].memberIds, ['member:k1', 'member:k2', 'member:k3']);
  assert.equal(twice.logicalIdByMemberId['member:k3'], 'member:k1');
});

test('similarity never decides anything: scanning every pair cannot change stored state', function () {
  const before = snapshot(assocState);
  for (const left of assocState.members) {
    for (const right of assocState.members) {
      ID.findCandidate(left, right);
    }
  }
  assert.equal(snapshot(assocState), before);
  assert.deepEqual(assocState.associations, [], 'the parser and the scorer leave every channel separate');
  assert.equal(assocState.logicalIdByMemberId['member:k2'], 'member:k2');
});

// ---- 7. refusals and their order -------------------------------------------------------------------

const invalidState = stateOf({
  members: [
    memberRow('member:v1', 'One'),
    memberRow('member:v2', 'Two', { playlistId: 'playlist:b' }),
    memberRow('member:v3', 'Three', { playlistId: 'playlist:c' })
  ],
  associations: [{ memberIds: ['member:v2', 'member:v3'] }],
  mapping: { 'member:v1': 'member:v1', 'member:v2': 'member:v2', 'member:v3': 'member:v2' }
});

test('every refusal carries the shared code string and leaves the state untouched', function () {
  const before = snapshot(invalidState);
  expectRefusal(
    'fewerThanTwoMembers',
    function () {
      ID.associate(invalidState, ['member:v1'], 'member:v1');
    },
    'one member is not an association'
  );
  expectRefusal(
    'fewerThanTwoMembers',
    function () {
      ID.associate(invalidState, [], 'member:v1');
    },
    'an empty selection is not an association'
  );
  expectRefusal(
    'fewerThanTwoMembers',
    function () {
      ID.associate(invalidState, null, 'member:v1');
    },
    'a missing list is not an association either'
  );
  expectRefusal(
    'duplicateMember',
    function () {
      ID.associate(invalidState, ['member:v1', 'member:v1'], 'member:v1');
    },
    'a repeated member is the caller’s bug and is not hidden by deduplication'
  );
  expectRefusal(
    'unknownMember',
    function () {
      ID.associate(invalidState, ['member:v1', 'member:ghost'], 'member:v1');
    },
    'an unknown member cannot be associated'
  );
  expectRefusal(
    'unknownPreferredLogicalChannel',
    function () {
      ID.associate(invalidState, ['member:v1', 'member:v2'], 'member:nowhere');
    },
    'a preferred channel that does not exist cannot own anything'
  );
  expectRefusal(
    'memberAssociatedElsewhere',
    function () {
      ID.associate(invalidState, ['member:v1', 'member:v3'], 'member:v1');
    },
    'a member already inside another channel is not free to join'
  );
  expectRefusal(
    'unknownPreferredLogicalChannel',
    function () {
      ID.associate(invalidState, ['member:v1', 'member:v3'], 'member:nowhere');
    },
    'the whole-map check runs before the per-member loop'
  );
  expectRefusal(
    'unknownMember',
    function () {
      ID.separate(invalidState, 'member:ghost');
    },
    'separating an unknown member is refused'
  );
  expectRefusal(
    'fewerThanTwoMembers',
    function () {
      ID.separate(invalidState, 'member:v1');
    },
    'separating the last member of a channel is refused'
  );
  assert.equal(snapshot(invalidState), before, 'validation finishes before anything is built');
  assert.deepEqual(invalidState.associations, [{ memberIds: ['member:v2', 'member:v3'] }]);
  assert.deepEqual(invalidState.logicalIdByMemberId, {
    'member:v1': 'member:v1',
    'member:v2': 'member:v2',
    'member:v3': 'member:v2'
  });
  assert.deepEqual(
    refusalMessage(function () {
      ID.associate(invalidState, ['member:v1', 'member:v3'], 'member:v1');
    }, 'code text'),
    'ChannelIdentityError.memberAssociatedElsewhere',
    'the refusal carries the wire-visible code string the other two ports carry'
  );
});

test('a member mapped to itself is unassociated and free to join', function () {
  const state = stateOf({ members: assocMembers });
  const merged = ID.associate(state, ['member:k1', 'member:k2'], 'member:k1');
  assert.deepEqual(merged.associations[0].memberIds, ['member:k1', 'member:k2']);
});

// ---- 8. separate -----------------------------------------------------------------------------------

test('separating one member of a two-member channel leaves nothing recorded', function () {
  const pairMembers = [memberRow('member:p1', 'One'), memberRow('member:p2', 'Two', { playlistId: 'playlist:b' })];
  const pairState = stateOf({
    playlists: [playlistRow('playlist:a'), playlistRow('playlist:b')],
    members: pairMembers,
    sources: [
      sourceRow('p1s', { channelId: 'member:p1', memberId: 'member:p1' }),
      sourceRow('p2s', { channelId: 'member:p1', memberId: 'member:p2', playlistId: 'playlist:b' })
    ],
    associations: [{ memberIds: ['member:p1', 'member:p2'] }],
    mapping: { 'member:p1': 'member:p1', 'member:p2': 'member:p1' }
  });
  const before = snapshot(pairState);
  const split = ID.separate(pairState, 'member:p2');
  assert.deepEqual(split.associations, [], 'two members merged only with each other leave no association behind');
  assert.equal(split.logicalIdByMemberId['member:p2'], 'member:p2', 'the leaving branch takes the canonical ID');
  assert.deepEqual(sourceIds(split.sources), ['p1s', 'p2s'], 'separation mints no new source ID');
  assert.deepEqual(
    split.sources.map(function (row) {
      return row.channelId;
    }),
    ['member:p1', 'member:p2'],
    'only the leaving member’s rows are re-parented'
  );
  assert.equal(split.sources[0], pairState.sources[0], 'the staying row is carried untouched');
  assert.equal(snapshot(pairState), before, 'the original state is still what it was');
});

test('a merge followed by a split restores what the user had without rebuilding anything', function () {
  const preference = preferenceRow('member:k2', {
    favorite: true,
    category: 'Special',
    userOrder: 7,
    lastSuccessfulSourceId: 's3'
  });
  const state = stateOf({
    members: assocMembers,
    sources: [
      sourceRow('s1', { channelId: 'member:k1', memberId: 'member:k1' }),
      sourceRow('s3', { channelId: 'member:k2', memberId: 'member:k2', playlistId: 'playlist:b' }),
      sourceRow('s4', { channelId: 'member:k3', memberId: 'member:k3', playlistId: 'playlist:c' })
    ],
    preferences: [preference]
  });
  const merged = ID.associate(state, ['member:k2', 'member:k3'], 'member:k1');
  const split = ID.separate(merged, 'member:k2');
  const restored = UC.build(split).filter(function (channel) {
    return channel.channelId === 'member:k2';
  })[0];
  assert.notEqual(restored, undefined, 'the leaving member is a channel again');
  assert.equal(restored.favorite, true);
  assert.equal(restored.userOrder, 7);
  assert.equal(restored.category, 'Special');
  assert.equal(restored.lastSuccessfulSourceId, 's3');
  assert.deepEqual(
    split.associations[split.associations.length - 1].memberIds,
    ['member:k1', 'member:k3'],
    'undoing one join is one action rather than a rebuild'
  );
});

test('separating from a three-way channel keeps the remaining pair a channel', function () {
  const merged = ID.associate(assocState, ['member:k2', 'member:k3'], 'member:k1');
  const split = ID.separate(merged, 'member:k3');
  assert.deepEqual(split.associations, [{ memberIds: ['member:k1', 'member:k2'] }]);
  assert.equal(split.logicalIdByMemberId['member:k3'], 'member:k3');
  assert.equal(split.sources[3].channelId, 'member:k3');
  assert.equal(split.sources[0].channelId, 'member:k1');
});

// ---- 9. the unified view ---------------------------------------------------------------------------

const viewMembers = [
  memberRow('member:u1', 'Alpha', { providerChannelId: 'A1', countryCode: 'IR', logoUrl: 'https://img.example/a.png', group: 'General' }),
  memberRow('member:u2', 'Beta', { playlistId: 'playlist:b', providerChannelId: 'B1', group: 'Kids' }),
  memberRow('member:u3', 'Gamma', { playlistId: 'playlist:c', providerChannelId: 'C1' }),
  memberRow('member:u4', 'Delta', { playlistId: 'playlist:c' })
];
const viewSources = [
  sourceRow('u2-zeta', { channelId: 'member:u2', memberId: 'member:u2', playlistId: 'playlist:b' }),
  sourceRow('u2-alpha', { channelId: 'member:u2', memberId: 'member:u2', playlistId: 'playlist:b' }),
  sourceRow('u2-first', { channelId: 'member:u2', memberId: 'member:u2', playlistId: 'playlist:b', priority: 1 }),
  sourceRow('u1-second', { channelId: 'member:u1', memberId: 'member:u1', priority: 1 }),
  sourceRow('u1-first', { channelId: 'member:u1', memberId: 'member:u1' }),
  sourceRow('u3-off', { channelId: 'member:u3', memberId: 'member:u3', playlistId: 'playlist:c', enabled: false }),
  sourceRow('u3-stale', { channelId: 'member:u3', memberId: 'member:u3', playlistId: 'playlist:c', priority: 1 }),
  sourceRow('ghost-row', { channelId: 'member:u1', memberId: 'member:gone' })
];
const viewPreference = preferenceRow('member:u1', {
  favorite: true,
  hidden: true,
  category: 'News',
  userOrder: 2,
  automaticFailoverEnabled: false,
  lastSuccessfulSourceId: 'u1-second'
});
const viewState = stateOf({
  members: viewMembers,
  sources: viewSources,
  preferences: [viewPreference]
});

test('the placed channel sorts first and the rest keep catalog appearance order', function () {
  const channels = UC.build(viewState);
  assert.deepEqual(
    channelIds(channels),
    ['member:u1', 'member:u2', 'member:u3', 'member:u4'],
    'editing one channel’s position cannot reorder another'
  );
  assert.equal(channels.length, 4);
  assert.equal(
    channels.every(function (channel) {
      return channel.memberIds.length > 0;
    }),
    true,
    'every reported channel has at least one member'
  );
});

test('the view applies the user’s own settings to the logical channel', function () {
  const placed = UC.build(viewState)[0];
  assert.equal(placed.favorite, true);
  assert.equal(placed.hidden, true, 'the flag the list filters on');
  assert.equal(placed.category, 'News');
  assert.equal(placed.userOrder, 2);
  assert.equal(placed.automaticFailoverEnabled, false);
  assert.equal(placed.lastSuccessfulSourceId, 'u1-second');
  assert.equal(placed.channelId, 'member:u1');
});

test('metadata comes from the channel’s first member', function () {
  const placed = UC.build(viewState)[0];
  assert.equal(placed.displayName, 'Alpha');
  assert.equal(placed.normalizedName, P.nameKey('Alpha'));
  assert.equal(placed.logoUrl, 'https://img.example/a.png');
  assert.equal(placed.countryCode, 'IR');
  assert.deepEqual(placed.languages, ['fas']);
});

test('sources follow priority order, and equal priorities break on the source ID', function () {
  const channels = UC.build(viewState);
  const byId = {};
  for (const channel of channels) byId[channel.channelId] = channel;
  assert.deepEqual(sourceIds(byId['member:u1'].sources), ['u1-first', 'u1-second']);
  assert.deepEqual(
    sourceIds(byId['member:u2'].sources),
    ['u2-alpha', 'u2-zeta', 'u2-first'],
    'the order is total and stable across refreshes, so the two other ports show the same list order'
  );
});

test('a user category wins over the provider group, and the group is the fallback', function () {
  const byId = {};
  for (const channel of UC.build(viewState)) byId[channel.channelId] = channel;
  assert.equal(byId['member:u1'].category, 'News');
  assert.equal(byId['member:u2'].category, 'Kids', 'where the user set no category, the provider’s own group is what the channel carries');
});

test('a member with no source rows is still a channel, and a source whose member is gone is dropped', function () {
  const channels = UC.build(viewState);
  const empty = channels.filter(function (channel) {
    return channel.channelId === 'member:u4';
  })[0];
  assert.deepEqual(empty.sources, [], 'this is what an empty list must render as');
  assert.equal(
    channels.some(function (channel) {
      return channel.sources.some(function (row) {
        return row.memberId === 'member:gone';
      });
    }),
    false,
    'the orphaned row is dropped rather than attached to a plausible channel'
  );
});

test('unset channels carry the standard recovery defaults, not port-specific literals', function () {
  const channels = UC.build(viewState);
  const plain = channels.filter(function (channel) {
    return channel.channelId === 'member:u2';
  })[0];
  assert.equal(plain.favorite, false);
  assert.equal(plain.hidden, false);
  assert.equal(plain.userOrder, null);
  assert.equal(plain.automaticFailoverEnabled, true, 'failover is on unless the user said otherwise');
  assert.equal(plain.lastSuccessfulSourceId, null);
  assert.deepEqual(plain.sourcePolicy, K.standardSourcePolicy());
  assert.notEqual(plain.sourcePolicy, K.standardSourcePolicy(), 'a fresh policy object per channel, so one edit cannot leak');
});

test('a disabled playlist disappears from the view while every row stays in the state', function () {
  const disabled = stateOf({
    playlists: [playlistRow('playlist:a'), playlistRow('playlist:b', false), playlistRow('playlist:c')],
    members: viewMembers,
    sources: viewSources,
    preferences: [viewPreference]
  });
  const before = snapshot(disabled);
  const channels = UC.build(disabled);
  assert.deepEqual(channelIds(channels), ['member:u1', 'member:u3', 'member:u4']);
  assert.equal(disabled.members.length, 4);
  assert.equal(disabled.sources.length, viewSources.length);
  assert.equal(snapshot(disabled), before, 'building the view mutates nothing');
  const gamma = channels.filter(function (channel) {
    return channel.channelId === 'member:u3';
  })[0];
  assert.deepEqual(
    sourceIds(gamma.sources),
    ['u3-off', 'u3-stale'],
    'a disabled source stays in its channel because the user manages it; eligibility belongs to Phase C'
  );
  assert.equal(
    gamma.sources.filter(function (row) {
      return !row.enabled;
    }).length,
    1
  );
  assert.equal(
    UC.build(
      stateOf({ members: viewMembers, sources: viewSources, preferences: [viewPreference] })
    ).length,
    4,
    're-enabling the playlist restores exactly the same four identities rather than new ones'
  );
});

test('sources follow their member’s logical channel, not their stored channel ID', function () {
  const stale = stateOf({
    members: [memberRow('member:w1', 'First'), memberRow('member:w2', 'Second', { playlistId: 'playlist:b' })],
    sources: [sourceRow('w2-row', { channelId: 'member:w2', memberId: 'member:w2', playlistId: 'playlist:b' })],
    associations: [{ memberIds: ['member:w1', 'member:w2'] }],
    mapping: { 'member:w1': 'member:w1', 'member:w2': 'member:w1' }
  });
  const joined = UC.build(stale);
  assert.equal(joined.length, 1);
  assert.deepEqual(sourceIds(joined[0].sources), ['w2-row']);
  assert.deepEqual(joined[0].memberIds, ['member:w1', 'member:w2']);
});

test('the association records the user’s own member order and the first member owns the metadata', function () {
  const ordered = stateOf({
    playlists: [playlistRow('playlist:a'), playlistRow('playlist:b')],
    members: [memberRow('member:o1', 'One'), memberRow('member:o2', 'Two', { playlistId: 'playlist:b' })],
    sources: [
      sourceRow('o2s', { channelId: 'member:o1', memberId: 'member:o2', playlistId: 'playlist:b' }),
      sourceRow('o1s', { channelId: 'member:o1', memberId: 'member:o1' })
    ],
    associations: [{ memberIds: ['member:o2', 'member:o1'] }],
    mapping: { 'member:o1': 'member:o1', 'member:o2': 'member:o1' }
  });
  const channels = UC.build(ordered);
  assert.equal(channels.length, 1);
  assert.deepEqual(channels[0].memberIds, ['member:o2', 'member:o1']);
  assert.equal(channels[0].displayName, 'Two');
});

test('a 95 candidate is still only a suggestion, so the view keeps two channels', function () {
  const twins = stateOf({
    playlists: [playlistRow('playlist:a'), playlistRow('playlist:b')],
    members: [
      memberRow('member:t1', 'Twin', { namespace: 'iptv-org', providerChannelId: 'TWIN', countryCode: 'IR' }),
      memberRow('member:t2', 'Twin', {
        playlistId: 'playlist:b',
        namespace: 'iptv-org',
        providerChannelId: 'TWIN',
        countryCode: 'IR'
      })
    ],
    sources: [
      sourceRow('t1s', { channelId: 'member:t1', memberId: 'member:t1' }),
      sourceRow('t2s', { channelId: 'member:t2', memberId: 'member:t2', playlistId: 'playlist:b' })
    ]
  });
  assert.equal(ID.findCandidate(twins.members[0], twins.members[1]).score, 95);
  assert.deepEqual(channelIds(UC.build(twins)), ['member:t1', 'member:t2']);
  assert.equal(
    UC.build(twins).every(function (channel) {
      return channel.memberIds.length === 1;
    }),
    true,
    'nothing merges itself without the user'
  );
});

test('building the view twice is idempotent, so a screen may rebuild after every edit', function () {
  const first = UC.build(viewState);
  const second = UC.build(viewState);
  assert.deepEqual(first, second);
  assert.notEqual(first, second, 'a fresh list each call');
  assert.notEqual(first[0].sources, second[0].sources);
  assert.equal(first[0].sources[0], second[0].sources[0], 'rows stay shared, only the containers are new');
});

// ---- 10. the built-in adapter ----------------------------------------------------------------------

const builtInRows = [
  {
    nanoid: 'fam1',
    name: 'IRIB 1',
    streams: ['https://irib.example/1.m3u8', 'https://backup.example/1.m3u8'],
    languages: ['fas'],
    country: 'IR',
    isGeoBlocked: false
  },
  {
    nanoid: 'fam2',
    name: 'Press TV',
    streams: ['https://press.example/a.m3u8', 'https://press.example/a.m3u8'],
    languages: ['fas'],
    country: 'IR',
    isGeoBlocked: false
  },
  {
    nanoid: '  ',
    name: 'بی بی سی فارسی',
    streams: [],
    languages: ['fas'],
    country: ' gb ',
    isGeoBlocked: true
  }
];

function adapterOptions() {
  return { playlistId: BUILTIN_PLAYLIST, providerNamespace: 'famelack' };
}

test('the adapter registers exactly the rows it was given, in provider order', function () {
  const registered = UC.registerBuiltIn(builtInRows, adapterOptions());
  assert.equal(registered.members.length, 3);
  assert.deepEqual(
    registered.members.map(function (row) {
      return row.ordinal;
    }),
    [0, 1, 2],
    'the ordinal is the catalog position, so a merged duplicate leaves no hole'
  );
  assert.equal(registered.channels, builtInRows, 'the runtime row list comes back as the caller passed it');
  assert.equal(
    registered.members.every(function (row) {
      return row.logoUrl === null && row.group === null;
    }),
    true,
    'the built-in dataset carries no logo or group, so none is invented'
  );
});

test('the member recipe is the parse path’s recipe', function () {
  const registered = UC.registerBuiltIn(builtInRows, adapterOptions());
  assert.equal(
    registered.members[0].memberId,
    'member:' + P.stableKeyHash(BUILTIN_PLAYLIST + '\nprovider\nfamelack\nfam1'),
    'a station that later appears in a playlist can be recognised because one recipe mints one identity'
  );
  assert.notEqual(
    registered.members[0].memberId,
    'member:' + P.stableKeyHash('fam1\nprovider\n' + BUILTIN_PLAYLIST + '\n' + BUILTIN_PLAYLIST),
    'the recipe is order-sensitive, which is what makes the assertion above falsifiable'
  );
  const third = registered.members[2];
  assert.equal(third.providerChannelId, 'name:' + P.nameKey('بی بی سی فارسی'));
  assert.equal(third.tvgId, null);
  assert.equal(third.countryCode, 'GB', 'a padded country is normalised on the way in');
  assert.equal(third.normalizedName, P.nameKey('بی بی سی فارسی'));
});

test('the source recipe, the gapless priority sequence and the labels all come from the parse path', function () {
  const registered = UC.registerBuiltIn(builtInRows, adapterOptions());
  const firstMember = registered.members[0].memberId;
  assert.equal(registered.sources.length, 3, 'a duplicate URL registers one source');
  assert.equal(
    registered.sources[0].sourceId,
    'source:' + P.stableKeyHash(firstMember + '\nurl\nhttps://irib.example/1.m3u8')
  );
  assert.equal(registered.sources[1].streamUrl, 'https://backup.example/1.m3u8');
  assert.deepEqual(
    registered.sources.slice(0, 2).map(function (row) {
      return row.priority;
    }),
    [0, 1]
  );
  assert.equal(
    registered.sources[2].priority,
    0,
    'priorities are per member, so a second station does not inherit the first one’s sequence'
  );
  assert.equal(registered.sources[0].label, 'منبع اصلی');
  assert.equal(registered.sources[1].label, 'منبع ۲', 'the shared Persian strings, including the Persian-Indic digit');
  assert.equal(
    registered.members[1].providerChannelId,
    'fam2',
    'the second station keeps its own provider ID rather than the name fold'
  );
});

test('nothing is claimed, proved, secret-backed or pre-associated by a built-in row', function () {
  const registered = UC.registerBuiltIn(builtInRows, adapterOptions());
  assert.equal(
    registered.sources.every(function (row) {
      return (
        row.rendererCapability === 'Not Yet Verified' &&
        row.health === 'unverified' &&
        row.enabled === true &&
        row.origin === 'playlist' &&
        row.channelId === row.memberId &&
        row.streamSecretRef === null &&
        row.lastSuccessfulPlaybackAt === null &&
        row.lastFailedPlaybackAt === null &&
        row.lastErrorCode === null
      );
    }),
    true,
    'rule 4 again: a built-in row is its own channel until the user associates it'
  );
  assert.equal(
    registered.sources.every(function (row) {
      return Object.keys(row).length === 17;
    }),
    true,
    'the rows carry the contract’s full field set, so the state encoder accepts them'
  );
  assert.deepEqual(
    K.decodeState(K.encodeState(
      stateOf({
        playlists: [playlistRow(BUILTIN_PLAYLIST)],
        members: registered.members,
        sources: registered.sources
      })
    )),
    stateOf({
      playlists: [playlistRow(BUILTIN_PLAYLIST)],
      members: registered.members,
      sources: registered.sources
    }),
    'the adapter’s output is already a valid catalog document, not a screen-side shape'
  );

  // Pinned rather than worked around: a document saved in the shorter second-precision spelling still
  // decodes, but the codec rewrites the stamp into the canonical three-fractional-digit form, because
  // `requireTimestamp` ends with `return date.toISOString()` (`playlist_contracts.js:191-232`). So
  // `encodeState(decodeState(legacy)) !== legacy` for an older document while
  // `encodeState(decodeState(x)) === x` for a canonical one — which is exactly why `NOW` above is written
  // in the spelling the codec emits. A later slice that stores a legacy profile has to normalize it on
  // read, not expect the stored text back.
  const legacyPlaylist = playlistRow(BUILTIN_PLAYLIST);
  legacyPlaylist.createdAt = LEGACY_NOW;
  assert.equal(
    K.decodeState(K.encodeState(stateOf({ playlists: [legacyPlaylist] }))).playlists[0].createdAt,
    NOW,
    'the second-precision wire form is accepted but canonicalized on read'
  );
});

test('identity stays unique across the whole dataset', function () {
  const registered = UC.registerBuiltIn(builtInRows, adapterOptions());
  const members = {};
  for (const row of registered.members) members[row.memberId] = true;
  const sources = {};
  for (const row of registered.sources) sources[row.sourceId] = true;
  assert.equal(Object.keys(members).length, registered.members.length);
  assert.equal(Object.keys(sources).length, registered.sources.length);
});

test('two provider rows for one station merge into one member', function () {
  const duplicated = UC.registerBuiltIn(
    [
      { nanoid: 'fam3', name: 'Gem TV', streams: ['https://gem.example/a.m3u8'], languages: ['fas'], country: 'IR' },
      { nanoid: 'fam3', name: 'Gem TV', streams: ['https://gem.example/b.m3u8'], languages: ['fas'], country: 'IR' }
    ],
    adapterOptions()
  );
  assert.equal(duplicated.members.length, 1);
  assert.deepEqual(
    duplicated.sources.map(function (row) {
      return row.priority;
    }),
    [0, 1],
    'gapless priorities rather than doubling the list'
  );
  assert.equal(
    duplicated.sources.every(function (row) {
      return row.memberId === duplicated.members[0].memberId;
    }),
    true
  );
});

test('a credential-bearing address is refused silently while the clean sibling survives', function () {
  const credential = UC.registerBuiltIn(
    [
      {
        nanoid: 'fam4',
        name: 'Secret TV',
        streams: ['https://cdn.example/live.m3u8?token=supersecretvalue'],
        languages: ['fas'],
        country: 'IR'
      },
      { nanoid: 'fam5', name: 'Plain TV', streams: ['https://cdn.example/plain.m3u8'], languages: ['fas'], country: 'IR' }
    ],
    adapterOptions()
  );
  assert.equal(credential.members.length, 2);
  assert.equal(credential.sources.length, 1);
  assert.equal(credential.sources[0].streamUrl, 'https://cdn.example/plain.m3u8');
  assert.equal(credential.sources[0].streamSecretRef, null, 'refusing a credential does not invent a stand-in reference');
  const state = stateOf({
    playlists: [playlistRow(BUILTIN_PLAYLIST)],
    members: credential.members.concat([UC.registerBuiltIn(builtInRows, adapterOptions()).members[0]]),
    sources: credential.sources.concat(UC.registerBuiltIn(builtInRows, adapterOptions()).sources.slice(0, 1))
  });
  assert.equal(
    snapshot(state).indexOf('supersecretvalue'),
    -1,
    'the refused address never reaches the persisted document, which is the property the adapter exists to guarantee'
  );
});

test('a built-in row and a parsed twin meet at the name-and-country tier when there is no logo', function () {
  const score = ID.findCandidate(
    memberRow('member:b1', 'IRIB 1', { providerChannelId: 'fam1', countryCode: 'IR' }),
    memberRow('member:b2', 'IRIB 1', {
      playlistId: 'playlist:b',
      namespace: 'iptv-org',
      providerChannelId: 'IRIB1.ir',
      countryCode: 'IR'
    })
  ).score;
  assert.equal(score, 75, 'so the pair is a confirmation, not a silent merge');
});

test('a real playlist row and a real built-in row of the same station are comparable across sources', function () {
  const parsed = P.parsePlaylist(
    'playlist:external',
    '#EXTM3U\n#EXTINF:-1 tvg-id="IRIB1.ir",IRIB 1\nhttps://other.example/1.m3u8\n',
    null
  );
  const registered = P.registerParsedPlaylist(parsed, 'playlist:external', 'iptv-org');
  const external = registered.members[0];
  assert.equal(external.providerChannelId, 'IRIB1', 'the last dotted suffix is the country, not part of the ID');
  const builtIn = UC.registerBuiltIn(
    [{ nanoid: 'fam1', name: 'IRIB 1', streams: ['https://irib.example/1.m3u8'], languages: ['fas'], country: 'IR' }],
    adapterOptions()
  ).members[0];
  const pair = ID.findCandidate(builtIn, external);
  assert.equal(pair.score, 75, 'same station, two providers, one namespace each: the name tiers decide');
  assert.equal(pair.evidence, 'exactNameCountry');
  assert.equal(pair.ambiguous, true);
});

test('the built-in rows project into independent channels with the standard defaults', function () {
  const registered = UC.registerBuiltIn(builtInRows, adapterOptions());
  const channels = UC.build(
    stateOf({
      playlists: [playlistRow(BUILTIN_PLAYLIST)],
      members: registered.members,
      sources: registered.sources
    })
  );
  assert.deepEqual(
    channelIds(channels),
    [registered.members[0].memberId, registered.members[1].memberId, registered.members[2].memberId]
  );
  assert.equal(
    channels.every(function (channel) {
      return channel.automaticFailoverEnabled === true && channel.memberIds.length === 1;
    }),
    true
  );
  assert.deepEqual(channels[0].sourcePolicy, K.standardSourcePolicy());
  assert.equal(channels[2].sources.length, 0, 'a station with no addresses is still a row the user can see');
});

test('a built-in row whose own name carries a noise token finds no candidate: the known B4 gap', function () {
  const parsed = P.parsePlaylist(
    'playlist:valid',
    '#EXTM3U\n#EXTINF:-1 tvg-id="PressTV.ir",Press TV (720p)\nhttps://press.example/tv.m3u8\n',
    null
  );
  const parsedMember = P.registerParsedPlaylist(parsed, 'playlist:valid', 'famelack').members[0];
  assert.equal(parsedMember.normalizedName, 'press tv', 'the parse path strips the token');
  const builtIn = UC.registerBuiltIn(
    [{ nanoid: '', name: 'Press TV (720p)', streams: ['https://press.example/tv.m3u8'], languages: ['fas'], country: 'IR' }],
    adapterOptions()
  ).members[0];
  assert.equal(builtIn.normalizedName, 'press tv 720p', 'the adapter does not apply displayName: the gap is shared, not hidden');
  assert.equal(ID.findCandidate(builtIn, parsedMember), null, 'so the pair under-suggests rather than mis-merges');
});

test('a built-in adapter call with nothing usable returns empty lists instead of throwing', function () {
  const empty = UC.registerBuiltIn(null, {});
  assert.deepEqual(empty.members, []);
  assert.deepEqual(empty.sources, []);
  assert.deepEqual(empty.channels, []);
  const junk = UC.registerBuiltIn([{}, { name: 'No Streams', country: 'IR' }], adapterOptions());
  assert.equal(junk.members.length, 2, 'a row with no name still gets an identity rather than vanishing');
  assert.deepEqual(junk.sources, [], 'and no source is invented for a row that states no address');
  assert.equal(junk.members[0].displayName, '');
  assert.equal(junk.members[0].countryCode, null);
});

// ---- 11. the language ceiling and realm purity ------------------------------------------------------

// A crude slice, same as `Tests/webos/playlist_parser.test.js:815`: each module is one IIFE of ES5-shaped
// code, so the only comment markers are the ones removed and every string literal is quoted on one line.
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

function stringsBlanked(code) {
  return code.replace(/"[^"]*"/g, '""').replace(/'[^']*'/g, "''");
}

// ---- 11. seeding the logical-id map: the precondition task B4 needs ---------------------------------

// Every fixture above builds its map with `identityMapping`, the same rule the Swift and Dart suites
// hand-build. Task B4 cannot: a real catalog comes from `registerParsedPlaylist`, which emits members and
// sources and no mapping at all, so the first merge a user attempts has no anchor and is refused on all three
// ports. `seedSingletonChannels` is that hand-built rule promoted into library code, and the checks below are
// the conditions under which it is allowed to exist: it must reproduce the fixture rule exactly, must never
// rewrite a recorded decision, and must not change what a screen displays.

const seedMembers = [
  memberRow('member:sd1', 'One'),
  memberRow('member:sd2', 'Two', { playlistId: 'playlist:b' }),
  memberRow('member:sd3', 'Three', { playlistId: 'playlist:c' })
];
const unseededState = stateOf({ members: seedMembers, mapping: {} });

test('an unseeded catalog refuses its first merge: the gap is real, not a fixture accident', function () {
  expectRefusal(
    'unknownPreferredLogicalChannel',
    function () {
      ID.associate(unseededState, ['member:sd1', 'member:sd2'], 'member:sd1');
    },
    'the map is keyed on member ids, so a freshly registered catalog has no key to name a preferred channel'
  );
  assert.deepEqual(unseededState.logicalIdByMemberId, {}, 'the refusal comes from an empty map, not from the members');
  assert.deepEqual(
    ID.logicalIdOf(unseededState, 'member:sd1'),
    'member:sd1',
    'an unseeded member is already its own channel for reading, which is what makes seeding a formality rather than a policy change'
  );
});

test('seeding gives each member its own channel and reproduces the fixture rule exactly', function () {
  const seeded = ID.seedSingletonChannels(unseededState);
  assert.deepEqual(
    seeded.logicalIdByMemberId,
    identityMapping(seedMembers),
    'the library now produces what every suite previously wrote by hand, so no port can drift on the recipe'
  );
  assert.deepEqual(
    Object.keys(seeded.logicalIdByMemberId).sort(),
    ['member:sd1', 'member:sd2', 'member:sd3']
  );
  assert.equal(seeded.schemaVersion, unseededState.schemaVersion);
  assert.deepEqual(seeded.playlists, unseededState.playlists);
  assert.deepEqual(seeded.sources, unseededState.sources);
  assert.deepEqual(seeded.associations, unseededState.associations);
  assert.deepEqual(seeded.preferences, unseededState.preferences);
  assert.notEqual(seeded.members, unseededState.members, 'the returned state shares no mutable list with its input');
  assert.notEqual(unseededState.logicalIdByMemberId, seeded.logicalIdByMemberId);
  assert.deepEqual(unseededState.logicalIdByMemberId, {}, 'seeding never edits the state it was given');
  assert.deepEqual(
    ID.membersOfLogicalChannel(seeded, 'member:sd1'),
    ['member:sd1'],
    'a seeded singleton is one member, so the memberAssociatedElsewhere rule still lets it join a merge'
  );
});

test('seeding is idempotent and never rewrites a recorded merge', function () {
  const once = ID.seedSingletonChannels(unseededState);
  const twice = ID.seedSingletonChannels(once);
  assert.equal(twice, once, 'a second load adds nothing, so calling this on every start costs no new state');

  const merged = ID.associate(once, ['member:sd2', 'member:sd3'], 'member:sd2');
  assert.equal(merged.logicalIdByMemberId['member:sd3'], 'member:sd2');
  const reseeded = ID.seedSingletonChannels(merged);
  assert.equal(reseeded, merged, 'every member already has a key, so there is nothing to seed');
  assert.equal(
    reseeded.logicalIdByMemberId['member:sd3'],
    'member:sd2',
    'a user decision is data, and a load-time helper must not get to revisit it'
  );
});

test('a seeded merge lands on exactly the state the hand-mapped fixture merge produces', function () {
  const handMapped = stateOf({ members: seedMembers });
  assert.deepEqual(
    ID.associate(ID.seedSingletonChannels(unseededState), ['member:sd2', 'member:sd3'], 'member:sd2'),
    ID.associate(handMapped, ['member:sd2', 'member:sd3'], 'member:sd2'),
    'seeding is the same starting point the suites already assumed, so B4 adds no second merge semantics'
  );
});

test('seeding changes what may be merged, not what a screen shows', function () {
  assert.deepEqual(
    UC.build(ID.seedSingletonChannels(unseededState)),
    UC.build(unseededState),
    'three unassociated rows stay three rows: seeding creates no phantom channel and reorders nothing'
  );
});

test('a seeded state is a document the codec round-trips', function () {
  const seeded = ID.seedSingletonChannels(unseededState);
  assert.deepEqual(
    K.decodeState(K.encodeState(seeded)),
    seeded,
    'the seeded map is encodable, so task B4 can persist it rather than rebuild it on every launch'
  );
});

test('the three new modules stay inside the language ceiling the webOS build is checked against', function () {
  const runtimeCeiling = [
    ['optional chaining', /\?\./],
    ['nullish coalescing', /\?\?/],
    ['Array.prototype.flat', /\.flat\(/],
    ['Array.prototype.flatMap', /\.flatMap\(/],
    ['Array.prototype.includes', /\.includes\(/],
    ['Object.fromEntries', /Object\.fromEntries/],
    ['Object.entries', /Object\.entries/],
    ['Object.assign', /Object\.assign/],
    ['globalThis', /\bglobalThis\b/],
    ['BigInt', /\bBigInt\b/],
    ['logical assignment', /(\|\||&&|\?\?)=/],
    ['Number.isInteger', /Number\.isInteger/],
    ['String.prototype.padStart', /\.padStart\(/],
    ['String.prototype.trimStart', /\.trimStart\(/]
  ];
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
  const hostApis = [
    'localStorage',
    'sessionStorage',
    'indexedDB',
    'fetch(',
    'XMLHttpRequest',
    'require(',
    'document.',
    'WebSocket',
    'new URL(',
    'URLSearchParams',
    'TextEncoder',
    'Date.now('
  ];
  for (const moduleName of [IDENTITY_MODULE, CATALOG_MODULE, ADAPTER_MODULE]) {
    const code = codeOnly(fs.readFileSync(path.join(ROOT, JS_DIR, moduleName), 'utf8'));
    for (const entry of runtimeCeiling) {
      assert.equal(entry[1].test(code), false, moduleName + ' must not use ' + entry[0] + ' (Chromium 68 ceiling)');
    }
    for (const entry of repoStyle) {
      assert.equal(
        entry[1].test(code),
        false,
        moduleName + ' should stay in the ES5-shaped idiom of webos_app/app/js: ' + entry[0]
      );
    }
    for (const forbidden of hostApis) {
      assert.ok(code.indexOf(forbidden) === -1, moduleName + ' must not touch ' + forbidden);
    }
    assert.equal(/#[A-Za-z]/.test(stringsBlanked(code)), false, moduleName + ' must not use a private class field');
    assert.ok(/\bfor\s*\(/.test(code), moduleName + ' walks its lists with explicit index loops');
    assert.ok(
      /^window\.CC = window\.CC \|\| \{\};$/m.test(code),
      moduleName + ' attaches to the existing CC namespace instead of replacing it'
    );
  }
});

test('the catalog never re-derives an identity or a policy that another module owns', function () {
  const catalogCode = codeOnly(fs.readFileSync(path.join(ROOT, JS_DIR, CATALOG_MODULE), 'utf8'));
  for (const notAllowed of ['stableKeyHash', 'charCodeAt', 'member:', 'maxAutomaticAttempts', 'backoffMs']) {
    assert.ok(
      catalogCode.indexOf(notAllowed) === -1,
      'unified_catalog.js must read ' + notAllowed + ' from its owner rather than restate it'
    );
  }
  assert.ok(
    catalogCode.indexOf('CC.channelIdentity') !== -1,
    'the mapping rule has one owner, which is what keeps a merge on the Mac a merge on the TV'
  );
  assert.ok(catalogCode.indexOf('CC.playlistContracts.standardSourcePolicy()') !== -1);

  const adapterCode = codeOnly(fs.readFileSync(path.join(ROOT, JS_DIR, ADAPTER_MODULE), 'utf8'));
  for (const shared of ['CC.playlistParser.stableKeyHash', 'nameKey', 'canonicalStreamUrl', 'isSensitiveUrl', 'persianDigits']) {
    assert.ok(
      adapterCode.indexOf(shared) !== -1 || adapterCode.indexOf('parser.' + shared.split('.').pop()) !== -1,
      'the adapter must reuse the parser’s ' + shared + ' rather than carry a second implementation'
    );
  }
  assert.ok(adapterCode.indexOf('charCodeAt') === -1, 'the adapter mints no digest of its own');
  // `displayName: name` is a field assignment the adapter must keep; the probe is for the noise *strip call*,
  // which belongs to the parse path and would make a built-in row and a playlist row fold differently.
  assert.ok(adapterCode.indexOf('displayName(') === -1, 'the adapter does not apply the parse-time noise strip');
});

test('nothing in the new modules reads the realm it was loaded in', function () {
  for (const moduleName of [IDENTITY_MODULE, CATALOG_MODULE, ADAPTER_MODULE]) {
    const before = Object.keys(global);
    loadInto({}, moduleName);
    assert.deepEqual(before, Object.keys(global), moduleName + ' must not add anything to the host global object');
  }
});

test('a second, isolated load of the whole group behaves identically', function () {
  // The screens may reload the app without a page refresh, and a module that kept state between loads would
  // merge channels that the user never asked for.
  const fresh = loadGroup(MODULES);
  const state = fresh.channelIdentity.associate(
    stateOf({ members: assocMembers }),
    ['member:k2', 'member:k3'],
    'member:k1'
  );
  assert.deepEqual(state.associations[0].memberIds, ['member:k1', 'member:k2', 'member:k3']);
  assert.equal(fresh.unifiedCatalog.build(state).length, 1);
  assert.equal(fresh.channelIdentity.ambiguityFloor, 85);
});
