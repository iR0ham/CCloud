'use strict';

// Task B2-J: the webOS half of the M3U parser and source registry contract.
//
// Same seven fixtures, same verdicts, same identity recipes as
// `flutter_app/test/playlist_parser_test.dart` and the `Multi-source playlist parser` block of
// `Tests/live-foundation/main.swift`. A port that passes its own suite but disagrees with the other
// two is worse than a port with no suite, so the checks below are written to fail on a *semantic*
// change (a folded URL, a re-ordered identity, a dropped dedupe) rather than on a rename.
//
// The three golden digests pinned in section 2 are not computed here. They are the literal text a
// `macos-15` runner printed for the Swift implementation at `e2400e3` (job 140871026873, lines
// `golden stableKeyHash(...) = ...`), and Dart agrees with them at `09f826c`. Pinning a foreign
// value is the whole point: if this file's hash function drifts, these three assertions break even
// though every other check in the suite is self-consistent.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const ROOT = path.resolve(__dirname, '../..');
const JS_DIR = 'webos_app/app/js';
const MODULE_NAME = 'playlist_parser.js';
const CONTRACTS_NAME = 'playlist_contracts.js';
const FIXTURE_DIR = path.join(ROOT, 'Tests/fixtures/multi-source');

const REQUIRED_API = [
  'limits',
  'streamSchemes',
  'sensitiveQueryKeys',
  'stableKeyHash',
  'utf8ByteLength',
  'nameKey',
  'displayName',
  'isNoiseToken',
  'canonicalStreamUrl',
  'isSensitiveUrl',
  'protocolHint',
  'parsePlaylist',
  'registerParsedPlaylist'
];

// Same sealing rationale as `Tests/webos/live_contracts.test.js:32`: the module is evaluated in this
// realm with every browser and host I/O global shadowed by a parameter, so a module that reached for
// storage or the network throws here instead of passing on a laptop and failing on a TV.
// `TextEncoder`, `URL` and `URLSearchParams` are sealed too, even though a newer shell would provide
// them: byte counting and reference parsing are re-implemented on purpose, so the port carries no
// dependency whose Chromium-68 availability could only be proven on a device, and no host
// normalizer can quietly mint a different `sourceId` from the same row.
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

// `URL` and `URLSearchParams` are sealed as *parameters*, not only avoided by convention: the module
// header says a normalizing URL class must never be used, and shadowing it with `undefined` is what
// turns that statement into an executed check rather than a comment.
function loadInto(scope, moduleName) {
  const modulePath = path.join(ROOT, JS_DIR, moduleName);
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

function loadParser() {
  const scope = {};
  loadInto(scope, MODULE_NAME);
  const namespace = scope.CC;
  if (!namespace) {
    assert.fail(MODULE_NAME + ' did not attach a CC namespace to window');
  }
  const keys = Object.keys(namespace);
  if (keys.length !== 1) {
    assert.fail(MODULE_NAME + ' must attach exactly one CC namespace, found: ' + JSON.stringify(keys));
  }
  if (keys[0] !== 'playlistParser') {
    assert.fail(
      MODULE_NAME + ' must attach the namespace `playlistParser` (the name task B4-J calls), found: ' + keys[0]
    );
  }
  return namespace.playlistParser;
}

const CC = loadParser();

function fixture(name) {
  const file = path.join(FIXTURE_DIR, name);
  if (!fs.existsSync(file)) {
    assert.fail('fixture ' + name + ' is missing; the three suites share these exact files');
  }
  return fs.readFileSync(file, 'utf8');
}

function codes(result) {
  return result.issues.map(function (item) {
    return item.code;
  });
}

function lines(result) {
  return result.issues.map(function (item) {
    return item.line;
  });
}

// ---- 1. surface -----------------------------------------------------------------------

test('the module exposes the exact surface the other two ports expose', function () {
  for (const name of REQUIRED_API) {
    assert.notEqual(CC[name], undefined, MODULE_NAME + ' must expose `' + name + '`');
  }
  assert.deepEqual(
    {
      maxBytes: CC.limits.maxBytes,
      maxLines: CC.limits.maxLines,
      maxMembers: CC.limits.maxMembers,
      maxUrlsPerMember: CC.limits.maxUrlsPerMember,
      maxUrlChars: CC.limits.maxUrlChars
    },
    { maxBytes: 10485760, maxLines: 200000, maxMembers: 50000, maxUrlsPerMember: 100, maxUrlChars: 8192 },
    'the ceilings are the same five numbers on all three ports'
  );
  assert.deepEqual(CC.streamSchemes, ['http', 'https'], 'only HTTP(S) is playable');
  assert.deepEqual(
    CC.sensitiveQueryKeys,
    ['token', 'key', 'password', 'signature', 'auth', 'credential'],
    'the credential key list is shared, not re-invented per port'
  );
});

// ---- 2. golden digests ----------------------------------------------------------------

test('stableKeyHash reproduces the digests the Swift runner printed', function () {
  // Verbatim from `macos-15` job 140871026873 at head e2400e3.
  assert.equal(CC.stableKeyHash(''), '811c9dc59e3779b985ebca6bc2b2ae35');
  assert.equal(CC.stableKeyHash('playlist:valid'), '981a29df6c39c1531339e5c1aef7688f');
  assert.equal(CC.stableKeyHash('پرس'), 'e724bb8086a3208c85ff01962c8b8030');
});

test('the empty-input vector exposes the seeds, which is what makes it a structural proof', function () {
  // Zero bytes hashed leaves every accumulator at its seed, so the value is the four seeds written in
  // order. A port that switched to a single pass, to a zero seed, or to a real digest would produce
  // something else entirely rather than a subtly different-but-plausible string.
  assert.equal(
    CC.stableKeyHash(''),
    '811c9dc5' + '9e3779b9' + '85ebca6b' + 'c2b2ae35',
    'the four FNV-1a seeds, concatenated'
  );
});

test('stableKeyHash is deterministic, lowercase, 32 hex, and separated by one character', function () {
  const a = CC.stableKeyHash('https://dup.example/a.m3u8');
  const b = CC.stableKeyHash('https://dup.example/a.m3u8');
  assert.equal(a, b, 'one input is one digest, so a refresh cannot invent a second source');
  assert.match(a, /^[0-9a-f]{32}$/, 'the digest renders as exactly 32 lowercase hex characters');
  const shifted = CC.stableKeyHash('https://dup.example/b.m3u8');
  assert.notEqual(a, shifted, 'a one-character change must move the whole identity');
  // Segment independence: pass 1 differs, so the concatenation cannot be a 32-bit value padded out.
  assert.notEqual(a.substring(0, 8), a.substring(8, 16));
  assert.equal(
    CC.stableKeyHash('x').substring(0, 8) === CC.stableKeyHash('x').substring(8, 16),
    false,
    'the four passes are independent seeded runs, not one value repeated'
  );
});

test('byte counting is UTF-8, so the ceiling matches what a download actually costs', function () {
  assert.equal(CC.utf8ByteLength('abc'), 3, 'ASCII is one byte per character');
  assert.equal(CC.utf8ByteLength('Press TV'), 8);
  assert.equal(CC.utf8ByteLength('پرس'), 6, 'three Persian letters are two bytes each');
  assert.equal(CC.utf8ByteLength('\u00e9'), 2, 'U+00E9 is two bytes');
  assert.equal(CC.utf8ByteLength('\u{1F600}'), 4, 'a surrogate pair is one four-byte code point');
  // The hash goes through the same byte sequence, which is why a Persian channel name agrees with the
  // Dart and Swift ports; here the golden vector in section 2 is the evidence.
  assert.equal(
    CC.stableKeyHash('پرس').length,
    32,
    'non-ASCII input still produces the fixed-width digest'
  );
});

// ---- 3. name normalisation ------------------------------------------------------------

test('nameKey folds width, diacritics, Arabic letters, Persian digits and punctuation', function () {
  assert.equal(CC.nameKey('IRIB ۱'), CC.nameKey('irib 1'), 'Persian digits fold to ASCII');
  assert.equal(CC.nameKey('IRIB ١'), CC.nameKey('irib 1'), 'Arabic-Indic digits fold too');
  assert.equal(CC.nameKey('  Press-TV  '), 'press tv', 'punctuation becomes a word break');
  assert.equal(CC.nameKey('press'), 'press', 'an already-clean name is unchanged');
  assert.equal(CC.nameKey('NAVEK'), 'navek');
  assert.equal(CC.nameKey('نیک'), 'نیک', 'the Arabic block survives as letters, not noise');
  assert.equal(CC.nameKey('یوسف'), CC.nameKey('يوسف'), 'Arabic yeh becomes Persian yeh');
  assert.equal(CC.nameKey('کتاب'), CC.nameKey('كتاب'), 'Arabic kaf becomes Persian kaf');
  assert.equal(CC.nameKey('اطلاع'), CC.nameKey('إطّلاع'), 'hamza forms fold and harakat drop');
  assert.equal(CC.nameKey('موزه'), CC.nameKey('مؤزه'), 'waw-with-hamza folds to waw');
  assert.equal(CC.nameKey('مریم\u200c'), CC.nameKey('مریم'), 'ZWNJ is a space, then punctuation');
  assert.equal(CC.nameKey('a\u00a0b'), 'a b', 'a non-breaking space becomes an ordinary one');
  assert.equal(CC.nameKey('ＦＵＬＬ'), 'full', 'fullwidth ASCII folds to halfwidth');
  assert.equal(CC.nameKey(''), '', 'an empty name keys empty rather than throwing');
  assert.equal(CC.nameKey('!!!'), '', 'pure punctuation keys empty, so it cannot match a station');
});

test('displayName removes quality brackets and keeps meaningful ones', function () {
  assert.equal(CC.displayName('Press TV (720p)'), 'Press TV');
  assert.equal(CC.displayName('IRIB 1 [SD]'), 'IRIB 1');
  assert.equal(CC.displayName('Foo (4K) (Backup)'), 'Foo');
  assert.equal(CC.displayName('Foo (not available)'), 'Foo', 'a `not` prefix is noise too');
  assert.equal(CC.displayName('BBC (Live)'), 'BBC (Live)', 'a bracket that is not noise survives');
  assert.equal(CC.displayName('Unclosed (720p'), 'Unclosed (720p', 'an unclosed bracket is literal');
  assert.equal(CC.displayName('A  (  )  B'), 'A B', 'empty brackets are noise');
  assert.equal(CC.displayName('  Lead   Trail  '), 'Lead Trail');
  assert.equal(CC.displayName('Tabbed\tName'), 'Tabbed Name', 'whitespace folds, not just spaces');
  assert.equal(CC.isNoiseToken('1080i'), true);
  assert.equal(CC.isNoiseToken('hevc'), true);
  assert.equal(CC.isNoiseToken('news'), false);
});

test('the display name and the match key answer different questions', function () {
  // Both ports pin this pair, because conflating the two is how a refresh turns one station into two.
  assert.equal(CC.nameKey(CC.displayName('Press TV (720p)')), 'press tv');
  assert.equal(CC.nameKey('Press TV (720p)'), 'press tv 720p');
});

// ---- 4. fixture verdicts --------------------------------------------------------------

test('valid.m3u yields three channels with their attributes intact', function () {
  const parsed = CC.parsePlaylist('playlist:valid', fixture('valid.m3u'), null);
  assert.equal(parsed.format, 'm3uChannelList', 'a header plus EXTINF rows is a channel list');
  assert.equal(parsed.channels.length, 3, 'three EXTINF rows with addresses are three channels');
  assert.deepEqual(codes(parsed), [], 'a well-formed playlist reports no issues');
  assert.equal(parsed.truncated, false, 'nothing was dropped');
  assert.match(parsed.contentHash, /^[0-9a-f]{32}$/, 'the content hash is a stableKeyHash');

  const press = parsed.channels[0];
  assert.equal(press.providerChannelId, 'PressTV', 'the country suffix is not identity');
  assert.equal(press.displayName, 'Press TV', 'the quality marker is dropped from the name');
  assert.deepEqual(
    press.streamUrls,
    ['https://press.example/720.m3u8', 'https://press.example/1080.m3u8'],
    'quality variants stay one channel in first-seen order'
  );
  assert.equal(press.line, 2, 'a channel remembers its physical line for reporting');
  assert.equal(press.countryCode, 'IR', 'the dotted suffix is the country, uppercased');
  assert.equal(press.group, 'News');
  assert.equal(press.logoUrl, 'https://img.example/press.png');
  assert.deepEqual(press.languages, ['English']);
  assert.equal(press.tvgId, 'PressTV.ir', 'the raw attribute survives the identity fold');

  assert.equal(parsed.channels[1].displayName, 'IRIB 1', 'bracketed SD marker removed');
  assert.deepEqual(parsed.channels[1].streamUrls, ['https://irib.example/1.m3u8']);
  assert.deepEqual(parsed.channels[1].languages, ['Persian']);
  assert.equal(parsed.channels[2].displayName, 'Music TV');
  assert.equal(parsed.channels[2].group, 'Music');
  assert.equal(parsed.channels[2].line, 7);
});

test('empty.m3u is an empty channel list, not a failure', function () {
  const parsed = CC.parsePlaylist('playlist:empty', fixture('empty.m3u'), null);
  assert.equal(parsed.format, 'empty');
  assert.equal(parsed.channels.length, 0);
  assert.deepEqual(codes(parsed), [], 'a header with no rows is a legal playlist');
});

test('hls-master.m3u8 is refused as a media manifest', function () {
  const parsed = CC.parsePlaylist('playlist:hls', fixture('hls-master.m3u8'), null);
  assert.equal(parsed.format, 'hlsMediaManifest');
  assert.equal(parsed.channels.length, 0, 'a manifest variant is not a channel');
  assert.deepEqual(codes(parsed), ['unsupportedMediaManifest']);
  assert.deepEqual(lines(parsed), [1], 'the refusal is about the whole document, so it is line 1');
});

test('malformed.m3u reports each defect once, at its own line', function () {
  const parsed = CC.parsePlaylist('playlist:malformed', fixture('malformed.m3u'), null);
  assert.equal(parsed.format, 'm3uChannelList', 'one good row still makes a channel list');
  assert.equal(parsed.channels.length, 1, 'only Good TV is usable');
  assert.equal(parsed.channels[0].providerChannelId, 'Good');
  assert.deepEqual(
    codes(parsed),
    ['missingStream', 'malformedEntry', 'invalidUrl', 'missingName'],
    'four rows, four distinct defects, in line order'
  );
  assert.deepEqual(lines(parsed), [4, 5, 7, 8]);
  // The load-bearing pair: `missingStream` is charged to the row's own header line (No Stream TV,
  // line 4, never received an address line) while `invalidUrl` is charged to the address that failed
  // (line 7, the `ftp://` under Broken URL TV's header on line 6). Reporting both codes for one row,
  // or attributing a refused address to the header, would make the user-facing advice wrong.
  const streamIssues = parsed.issues.filter(function (item) {
    return item.code === 'missingStream';
  });
  const urlIssues = parsed.issues.filter(function (item) {
    return item.code === 'invalidUrl';
  });
  assert.equal(streamIssues.length, 1, 'exactly one row never received an address');
  assert.equal(streamIssues[0].line, 4, 'line 4 is the address-less row');
  assert.equal(urlIssues.length, 1, 'exactly one row got an address and had it refused');
  assert.equal(urlIssues[0].line, 7, 'the refused address line, not its header, owns invalidUrl');
});

test('a playlist with no #EXTM3U header is not treated as a channel list', function () {
  const parsed = CC.parsePlaylist(
    'playlist:noheader',
    '#EXTINF:-1 tvg-id="Solo.ir",Solo TV\nhttps://solo.example/live.m3u8\n',
    null
  );
  assert.equal(parsed.format, 'invalid');
  assert.equal(parsed.channels.length, 0, 'a body the parser cannot trust yields no channels');
  assert.deepEqual(codes(parsed), ['malformedEntry']);
});

test('a repeated id merges rows in first-seen order', function () {
  const parsed = CC.parsePlaylist(
    'playlist:twin',
    '#EXTM3U\n#EXTINF:-1 tvg-id="Dup.ir",First Name\nhttps://dup.example/a.m3u8\n' +
      '#EXTINF:-1 tvg-id="Dup.ir",Second Name\nhttps://dup.example/b.m3u8\n',
    null
  );
  assert.equal(parsed.channels.length, 1, 'one id is one channel');
  assert.equal(parsed.channels[0].displayName, 'First Name', 'the first row keeps the name');
  assert.equal(parsed.channels[0].line, 2, 'and keeps its line, so a re-list does not move it');
  assert.deepEqual(
    parsed.channels[0].streamUrls,
    ['https://dup.example/a.m3u8', 'https://dup.example/b.m3u8'],
    'the second row contributes its address, not a second station'
  );
});

test('duplicates.m3u gives two members and three addresses', function () {
  const parsed = CC.parsePlaylist('playlist:duplicates', fixture('duplicates.m3u'), null);
  assert.equal(parsed.channels.length, 2);
  assert.deepEqual(parsed.channels[0].streamUrls, [
    'https://dup.example/a.m3u8',
    'https://dup.example/b.m3u8'
  ]);
});

test('an address with no row before it is not a channel', function () {
  const parsed = CC.parsePlaylist('playlist:none', '#EXTM3U\nhttps://cdn.example/orphan.m3u8\n', null);
  assert.equal(parsed.channels.length, 0);
  assert.equal(parsed.format, 'empty');
  assert.deepEqual(codes(parsed), [], 'a stray line is ignored rather than reported as a station');
});

// ---- 5. addresses ---------------------------------------------------------------------

test('relative addresses resolve only against an HTTP(S) base', function () {
  const text = '#EXTM3U\n#EXTINF:-1 tvg-id="Rel.ir",Rel TV\nlive/720.m3u8\n';
  const withoutBase = CC.parsePlaylist('playlist:rel', text, null);
  assert.equal(withoutBase.channels.length, 0, 'a relative address with no base is not playable');
  assert.deepEqual(codes(withoutBase), ['invalidUrl']);

  const withBase = CC.parsePlaylist('playlist:rel', text, 'https://cdn.example/live/index.m3u8');
  assert.deepEqual(
    withBase.channels[0].streamUrls,
    ['https://cdn.example/live/live/720.m3u8'],
    'the base directory is kept, exactly as Uri.resolve and Foundation both do'
  );

  const fileBase = CC.parsePlaylist('playlist:rel', text, 'file:///tmp/index.m3u8');
  assert.equal(
    fileBase.channels.length,
    0,
    'a local base must not smuggle a relative path into something a player will fetch'
  );
  assert.deepEqual(codes(fileBase), ['invalidUrl']);
});

test('relative resolution follows RFC 3986 dot segments', function () {
  const base = 'https://cdn.example/live/deep/index.m3u8';
  const cases = [
    ['a.m3u8', 'https://cdn.example/live/deep/a.m3u8'],
    ['./a.m3u8', 'https://cdn.example/live/deep/a.m3u8'],
    ['../a.m3u8', 'https://cdn.example/live/a.m3u8'],
    ['/abs/a.m3u8', 'https://cdn.example/abs/a.m3u8'],
    ['a/../../b.m3u8', 'https://cdn.example/live/b.m3u8'],
    ['a/m3u8/../b.m3u8', 'https://cdn.example/live/deep/a/b.m3u8'],
    ['?only=query.m3u8', 'https://cdn.example/live/deep/index.m3u8?only=query.m3u8']
  ];
  for (const pair of cases) {
    const text = '#EXTM3U\n#EXTINF:-1 tvg-id="R.ir",R TV\n' + pair[0] + '\n';
    const parsed = CC.parsePlaylist('playlist:rel', text, base);
    const actual = parsed.channels.length === 1 ? parsed.channels[0].streamUrls[0] : codes(parsed);
    assert.deepEqual(actual, pair[1], 'resolving ' + pair[0] + ' against the base');
  }
});

test('canonicalStreamUrl folds only what the three ports agreed to fold', function () {
  const keeps = [
    ['https://cdn.example/a.m3u8', 'https://cdn.example/a.m3u8'],
    ['HTTPS://CDN.Example.COM/A.M3U8', 'https://cdn.example.com/A.M3U8'],
    ['http://cdn.example:80/a.m3u8', 'http://cdn.example/a.m3u8'],
    ['https://cdn.example:443/a.m3u8', 'https://cdn.example/a.m3u8'],
    ['https://cdn.example:8080/a.m3u8', 'https://cdn.example:8080/a.m3u8'],
    ['https://cdn.example:08/a.m3u8', 'https://cdn.example:8/a.m3u8'],
    ['https://cdn.example/a.m3u8?Token=1', 'https://cdn.example/a.m3u8?Token=1'],
    // An empty query is dropped, because both `Uri.query` and `URLComponents.query` answer ""
    // for `a.m3u8?` and the canonical rebuild only writes a query it finds non-empty.
    ['https://cdn.example/a.m3u8?', 'https://cdn.example/a.m3u8'],
    ['http://192.0.2.5:9000/live.m3u8', 'http://192.0.2.5:9000/live.m3u8'],
    ['https://[2001:db8::1]:8443/live.m3u8', 'https://[2001:db8::1]:8443/live.m3u8'],
    ['https://cdn.example/a%20b.m3u8', 'https://cdn.example/a%20b.m3u8']
  ];
  for (const pair of keeps) {
    assert.equal(CC.canonicalStreamUrl(pair[0]), pair[1], 'canonicalizing ' + pair[0]);
  }
  const refuses = [
    'ftp://cdn.example/a.m3u8',
    'file:///tmp/a.m3u8',
    'https://cdn.example',
    'https://cdn.example/',
    'https:///a.m3u8',
    'cdn.example/a.m3u8',
    'https://user@cdn.example/a.m3u8',
    'https://cdn.example/a.m3u8#1',
    'https://cdn.example:abc/a.m3u8',
    'https://[2001:db8::1/live.m3u8',
    'https://cdn example/a.m3u8'
  ];
  for (const raw of refuses) {
    assert.equal(CC.canonicalStreamUrl(raw), null, 'refusing ' + raw);
  }
  // Query case and path case survive, because a CDN manifest is case-sensitive and lowercasing it
  // would point two different streams at one sourceId.
  assert.notEqual(
    CC.canonicalStreamUrl('https://cdn.example/A.m3u8'),
    CC.canonicalStreamUrl('https://cdn.example/a.m3u8')
  );
});

test('canonicalization is idempotent, which the registry depends on', function () {
  const once = CC.canonicalStreamUrl('HTTPS://CDN.Example.COM:443/A.M3U8?X=1');
  assert.equal(CC.canonicalStreamUrl(once), once, 'a canonical address canonicalizes to itself');
});

test('isSensitiveUrl keys on query names, not on substrings', function () {
  const sensitive = [
    'https://cdn.example/a.m3u8?token=abc',
    'https://cdn.example/a.m3u8?Key=abc',
    'https://cdn.example/a.m3u8?x=1&signature=abc',
    'https://cdn.example/a.m3u8?auth',
    'https://user@cdn.example/a.m3u8'
  ];
  for (const raw of sensitive) {
    assert.equal(CC.isSensitiveUrl(raw), true, 'a credential-bearing address: ' + raw);
  }
  // `/monkey.m3u8` contains `key` and `/tokens` contains `token`; a substring test would drop both
  // channels, which is a worse outcome than the leak it tries to prevent.
  const harmless = [
    'https://cdn.example/monkey.m3u8',
    'https://cdn.example/tokens/count.m3u8',
    'https://cdn.example/a.m3u8?keyring=1',
    'https://cdn.example/token/live.m3u8',
    'https://cdn.example/a.m3u8'
  ];
  for (const raw of harmless) {
    assert.equal(CC.isSensitiveUrl(raw), false, 'not a credential: ' + raw);
  }
});

test('protocolHint reads the path extension and ignores the query', function () {
  assert.equal(CC.protocolHint('https://cdn.example/a.m3u8'), 'hls');
  assert.equal(CC.protocolHint('https://cdn.example/a.M3U8'), 'hls', 'the extension is matched folded');
  assert.equal(CC.protocolHint('https://cdn.example/a.mpd'), 'dash');
  assert.equal(CC.protocolHint('https://cdn.example/a.mp4'), 'mp4');
  assert.equal(CC.protocolHint('https://cdn.example/a.ts'), 'unknown');
  assert.equal(
    CC.protocolHint('https://cdn.example/c.mp4?x=M3U8'),
    'mp4',
    'a query that merely mentions a manifest does not change the container'
  );
});

// ---- 6. ceilings ----------------------------------------------------------------------

test('the byte ceiling refuses the whole document and hashes nothing', function () {
  const huge = '#EXTM3U\n' + 'x'.repeat(CC.limits.maxBytes);
  const parsed = CC.parsePlaylist('playlist:big', huge, null);
  assert.equal(parsed.format, 'm3uChannelList', 'the format answer still needs the header');
  assert.deepEqual(codes(parsed), ['oversizedInput']);
  assert.equal(parsed.contentHash, '', 'refused bytes are not hashed into a catalog identity');
  assert.equal(parsed.channels.length, 0, 'nothing is parsed');
  assert.equal(parsed.truncated, true);
  assert.ok(parsed.inputBytes > CC.limits.maxBytes, 'the reported size is the real UTF-8 cost');
});

test('the line ceiling keeps the permitted prefix and says so', function () {
  const text = '#EXTM3U\n' + 'filler\n'.repeat(CC.limits.maxLines);
  const parsed = CC.parsePlaylist('playlist:lines', text, null);
  assert.deepEqual(codes(parsed), ['limitExceeded']);
  assert.equal(parsed.truncated, true);
  assert.match(parsed.contentHash, /^[0-9a-f]{32}$/, 'the document still has its identity');
});

test('the member ceiling keeps 50,000 real rows plus one honest issue', function () {
  let text = '#EXTM3U\n';
  for (let i = 0; i < CC.limits.maxMembers + 1; i++) {
    text += '#EXTINF:-1 tvg-id="C' + i + '.ir",Channel ' + i + '\nhttps://e.example/' + i + '.m3u8\n';
  }
  const parsed = CC.parsePlaylist('playlist:many', text, null);
  assert.equal(parsed.channels.length, CC.limits.maxMembers, 'the permitted prefix survives');
  assert.equal(codes(parsed).indexOf('limitExceeded') !== -1, true, 'and the cost is reported');
  assert.equal(parsed.truncated, true);
});

test('the per-member URL ceiling detaches the row rather than truncating a list', function () {
  let text = '#EXTINF:-1 tvg-id="Many.ir",Many TV\n';
  for (let i = 0; i < CC.limits.maxUrlsPerMember; i++) {
    text += 'https://e.example/' + i + '.m3u8\n';
  }
  text += 'https://e.example/overflow.m3u8\n';
  const parsed = CC.parsePlaylist('playlist:urlcap', '#EXTM3U\n' + text, null);
  // Crossing the ceiling closes the row rather than deleting it: the user keeps the 100 addresses
  // that fit, and the issue plus `truncated` say the list is not the whole one. Dropping the row
  // would silently lose 100 playable streams to protect against one.
  assert.equal(parsed.channels.length, 1, 'the row survives with the addresses that fit');
  assert.equal(parsed.channels[0].streamUrls.length, CC.limits.maxUrlsPerMember, 'and keeps exactly the ceiling');
  assert.equal(codes(parsed).indexOf('limitExceeded') !== -1, true, 'the overflow is reported, not hidden');
  assert.equal(parsed.truncated, true);
});

test('the URL character ceiling drops the address, never a prefix of it', function () {
  const long = 'https://e.example/' + 'z'.repeat(CC.limits.maxUrlChars) + '.m3u8';
  const parsed = CC.parsePlaylist(
    'playlist:urlchars',
    '#EXTM3U\n#EXTINF:-1 tvg-id="Long.ir",Long TV\n' + long + '\n',
    null
  );
  assert.equal(parsed.channels.length, 0, 'half an address would still look playable');
  assert.deepEqual(codes(parsed), ['limitExceeded']);
  assert.equal(parsed.truncated, true);
});

// ---- 7. registry ----------------------------------------------------------------------

const duplicatesRegistry = CC.registerParsedPlaylist(
  CC.parsePlaylist('playlist:duplicates', fixture('duplicates.m3u'), null),
  'playlist:duplicates',
  'fixture:provider'
);

test('registerParsedPlaylist spells out identity rules 1, 3 and 4', function () {
  // The digest function is anchored by the runner-printed golden digests above; spelling the *recipe* out
  // here is what catches a port that hashed the parts in a different order or joined them with
  // something other than newlines. Both halves together make the identifiers cross-port constants.
  const firstMemberId =
    'member:' + CC.stableKeyHash('playlist:duplicates\nprovider\nfixture:provider\nDup');
  assert.equal(duplicatesRegistry.members.length, 2, 'two ids are two members');
  assert.equal(duplicatesRegistry.sources.length, 3, 'three addresses are three sources');
  assert.equal(duplicatesRegistry.members[0].memberId, firstMemberId);
  assert.equal(
    duplicatesRegistry.sources[0].sourceId,
    'source:' + CC.stableKeyHash(firstMemberId + '\nurl\nhttps://dup.example/a.m3u8'),
    'identity rule 3 keys on the canonical address'
  );
  assert.equal(duplicatesRegistry.sources[0].channelId, firstMemberId, 'rule 4 until the user associates');
  assert.equal(duplicatesRegistry.sources[0].memberId, firstMemberId);
  assert.equal(duplicatesRegistry.sources[0].playlistId, 'playlist:duplicates');
  assert.equal(duplicatesRegistry.sources[0].providerNamespace, 'fixture:provider');
  assert.equal(duplicatesRegistry.sources[0].streamUrl, 'https://dup.example/a.m3u8');
  assert.equal(duplicatesRegistry.sources[0].streamSecretRef, null);
  assert.equal(
    duplicatesRegistry.sources[0].sourceId.indexOf('https://'),
    -1,
    'an identifier never embeds the raw address it was built from'
  );
});

test('priority restarts per member, so every channel keeps a primary', function () {
  assert.deepEqual(
    duplicatesRegistry.sources.map(function (source) {
      return source.priority;
    }),
    [0, 1, 0]
  );
  assert.deepEqual(
    duplicatesRegistry.sources.map(function (source) {
      return source.label;
    }),
    ['منبع اصلی', 'منبع ۲', 'منبع اصلی'],
    'the primary label is Persian and the ordinal digits are Persian too'
  );
  assert.deepEqual(
    duplicatesRegistry.members.map(function (member) {
      return member.ordinal;
    }),
    [0, 1],
    'ordinals follow parse order, which is the order the user saw'
  );
});

test('nothing claims a stream works because it was listed', function () {
  for (const source of duplicatesRegistry.sources) {
    assert.equal(source.health, 'unverified', 'parsing a playlist is not evidence that it plays');
    assert.equal(
      source.rendererCapability,
      'Not Yet Verified',
      'the record states the absence of evidence instead of inventing or omitting it'
    );
    assert.equal(source.origin, 'playlist', 'a parsed address is not a user addition');
    assert.equal(source.enabled, true, 'fresh sources are enabled but unverified');
    assert.equal(source.lastSuccessfulPlaybackAt, null);
    assert.equal(source.lastFailedPlaybackAt, null);
    assert.equal(source.lastErrorCode, null);
  }
});

test('two spellings of one origin are one source', function () {
  const text =
    '#EXTM3U\n#EXTINF:-1 tvg-id="Dup.ir",Dup TV\n' +
    'https://dup.example/a.m3u8\nHTTPS://Dup.Example:443/a.m3u8\nhttps://dup.example/b.m3u8\n';
  const registry = CC.registerParsedPlaylist(
    CC.parsePlaylist('playlist:dedupe', text, null),
    'playlist:dedupe',
    'fixture:provider'
  );
  assert.equal(registry.sources.length, 2, 'the uppercase duplicate collapses silently');
  assert.deepEqual(codes(registry), [], 'deduplicating is not an error worth reporting');
  assert.deepEqual(
    registry.sources.map(function (source) {
      return source.priority;
    }),
    [0, 1],
    'the surviving sources keep consecutive priorities'
  );
});

test('a credential-bearing address is refused rather than persisted', function () {
  const text =
    '#EXTM3U\n#EXTINF:-1 tvg-id="Sec.ir",Sec TV\n' +
    'https://sec.example/a.m3u8?token=abc\nhttps://sec.example/b.m3u8\n';
  const registry = CC.registerParsedPlaylist(
    CC.parsePlaylist('playlist:secret', text, null),
    'playlist:secret',
    'fixture:provider'
  );
  assert.equal(registry.sources.length, 1, 'only the clean address becomes a source');
  assert.deepEqual(codes(registry), ['secretStorageUnavailable']);
  const stored = JSON.stringify(registry);
  assert.equal(stored.indexOf('token=abc'), -1, 'the credential never reaches the emitted records');
  assert.equal(stored.indexOf('token'), -1, 'not even the query key survives in a message or field');
  assert.equal(registry.members.length, 1, 'the member itself survives with its usable source');
});

test('a member with every address refused keeps no empty source list', function () {
  const text = '#EXTM3U\n#EXTINF:-1 tvg-id="Only.ir",Only TV\nhttps://o.example/a.m3u8?key=1\n';
  const registry = CC.registerParsedPlaylist(
    CC.parsePlaylist('playlist:onlysecret', text, null),
    'playlist:onlysecret',
    'fixture:provider'
  );
  assert.equal(registry.sources.length, 0);
  assert.equal(registry.members.length, 1, 'the member is recorded so the issue has an owner');
  assert.deepEqual(codes(registry), ['secretStorageUnavailable']);
});

test('registration is pure, namespace-scoped, and empty for an empty parse', function () {
  const parsed = CC.parsePlaylist('playlist:valid', fixture('valid.m3u'), null);
  const first = CC.registerParsedPlaylist(parsed, 'playlist:valid', 'builtin:ccloud');
  const again = CC.registerParsedPlaylist(parsed, 'playlist:valid', 'builtin:ccloud');
  assert.deepEqual(first, again, 're-parsing the same bytes must not move a single identity');

  const other = CC.registerParsedPlaylist(parsed, 'playlist:valid', 'builtin:other');
  assert.notEqual(first.members[0].memberId, other.members[0].memberId, 'namespace separates providers');
  const otherPlaylist = CC.registerParsedPlaylist(parsed, 'playlist:other', 'builtin:ccloud');
  assert.notEqual(
    first.members[0].memberId,
    otherPlaylist.members[0].memberId,
    'the same provider id under a second playlist is a different member'
  );

  const empty = CC.registerParsedPlaylist(
    CC.parsePlaylist('playlist:empty', fixture('empty.m3u'), null),
    'playlist:empty',
    'fixture:provider'
  );
  assert.deepEqual(empty, { members: [], sources: [], issues: [] }, 'nothing to register, nothing to report');
});

test('normalizedName is the match key, kept separate from the display name', function () {
  const registry = CC.registerParsedPlaylist(
    CC.parsePlaylist('playlist:valid', fixture('valid.m3u'), null),
    'playlist:valid',
    'fixture:provider'
  );
  assert.equal(registry.members[0].displayName, 'Press TV');
  assert.equal(registry.members[0].normalizedName, 'press tv');
  assert.equal(registry.members[0].tvgId, 'PressTV.ir', 'the raw id survives for a later identity review');
  assert.deepEqual(registry.members[0].languages, ['English']);
  assert.equal(registry.members[0].logoUrl, 'https://img.example/press.png');
});

test('a playlist-level id collision cannot steal a prototype key', function () {
  // `constructor` and `__proto__` are legal tvg-id values. On an ordinary object they would collide
  // with Object.prototype: the second row would look like an existing member and the channel would
  // vanish with no issue recorded.
  const text =
    '#EXTM3U\n#EXTINF:-1 tvg-id="constructor.ir",Constructor TV\nhttps://c.example/a.m3u8\n' +
    '#EXTINF:-1 tvg-id="toString.ir",ToString TV\nhttps://t.example/a.m3u8\n';
  const parsed = CC.parsePlaylist('playlist:proto', text, null);
  assert.equal(parsed.channels.length, 2, 'both rows survive');
  const registry = CC.registerParsedPlaylist(parsed, 'playlist:proto', 'fixture:provider');
  assert.equal(registry.members.length, 2);
  assert.equal(registry.sources.length, 2);
});

test('fallback identity separates two rows with no tvg-id', function () {
  const text =
    '#EXTM3U\n#EXTINF:-1 group-title="News",Same Name\nhttps://a.example/live.m3u8\n' +
    '#EXTINF:-1 group-title="News",Same Name\nhttps://b.example/live.m3u8\n';
  const parsed = CC.parsePlaylist('playlist:fallback', text, null);
  assert.equal(parsed.channels.length, 2, 'without an occurrence index one stream would silently vanish');
  const registry = CC.registerParsedPlaylist(parsed, 'playlist:fallback', 'fixture:provider');
  assert.notEqual(registry.members[0].memberId, registry.members[1].memberId);
  assert.equal(registry.members[0].providerChannelId.indexOf('fallback:'), 0);
  assert.equal(
    registry.members[0].providerChannelId,
    'fallback:same name||News||0',
    'the tuple is name|country|group|logo|occurrence, and a row with no tvg-id has no country'
  );
  assert.equal(
    registry.members[1].providerChannelId,
    'fallback:same name||News||1',
    'the second identical row differs only by its occurrence index'
  );
  const again = CC.registerParsedPlaylist(parsed, 'playlist:fallback', 'fixture:provider');
  assert.deepEqual(registry.members, again.members, 'occurrence numbering is deterministic per parse');
});

// ---- 8. agreement with the catalog codec ----------------------------------------------

test('registered records are what the schema-v1 codec writes and reads back', function () {
  const scope = {};
  loadInto(scope, CONTRACTS_NAME);
  loadInto(scope, MODULE_NAME);
  const contracts = scope.CC.playlistContracts;
  const parser = scope.CC.playlistParser;
  assert.notEqual(contracts, undefined, 'the codec module must still load beside the parser');
  assert.notEqual(parser, undefined, 'and must not overwrite its namespace');

  const registry = parser.registerParsedPlaylist(
    parser.parsePlaylist('playlist:valid', fixture('valid.m3u'), null),
    'playlist:valid',
    'builtin:ccloud'
  );
  // The codec exports only the document-level API, which is what task B4-J actually calls, so the
  // records are checked by putting them through a real state document rather than a private reader.
  // Going through `encodeState` as well as `decodeState` is the point: a record the app can read but
  // not write is one it cannot keep across a restart.
  const state = contracts.emptyState();
  state.members = registry.members;
  state.sources = registry.sources;

  const encoded = contracts.encodeState(state);
  const decoded = contracts.decodeState(encoded);

  assert.equal(decoded.members.length, 3, 'every member of the fixture survived a save');
  assert.equal(
    decoded.members[0].memberId,
    registry.members[0].memberId,
    'the codec keeps the identity the parser minted'
  );
  assert.equal(decoded.members[0].ordinal, 0);
  assert.deepEqual(decoded.members[0].languages, ['English']);
  assert.equal(decoded.sources.length, 4, 'two addresses for Press TV plus one each for IRIB 1 and Music TV');
  assert.equal(decoded.sources[0].sourceId, registry.sources[0].sourceId, 'source identity survives a save');
  assert.equal(decoded.sources[0].streamUrl, 'https://press.example/720.m3u8');
  assert.equal(decoded.sources[0].channelId, decoded.members[0].memberId, 'rule 4: a new channel is its member');
  assert.equal(
    decoded.sources[0].rendererCapability,
    'Not Yet Verified',
    'the parser never claims more than the codec can record'
  );
  assert.equal(decoded.sources[0].health, 'unverified');
  assert.equal(decoded.sources[0].origin, 'playlist');
  assert.equal(
    contracts.encodeState(decoded),
    encoded,
    'the round trip is a fixed point, so saving twice cannot move an identity or add a claim'
  );
});

// ---- 9. the language ceiling ----------------------------------------------------------

// A crude slice, same as `Tests/webos/live_contracts.test.js:920`: this module is one IIFE of
// ES5-shaped code, so the only comment markers in it are the ones removed and every string literal is
// quoted on one line.
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

// String literals blanked, for the checks that must not be confused by the parser's own vocabulary.
// An M3U parser necessarily contains the `#EXTM3U` and `#EXTINF` markers, so the private-class-field
// probe used for `playlist_contracts.js` cannot be applied to this file verbatim: it would report the
// M3U tag names as class fields. Blanking strings for that one probe keeps the check meaningful
// instead of dropping it.
function stringsBlanked(code) {
  return code.replace(/"[^"]*"/g, '""').replace(/'[^']*'/g, "''");
}

test('the module stays inside the language ceiling the webOS build is checked against', function () {
  const source = fs.readFileSync(path.join(ROOT, JS_DIR, MODULE_NAME), 'utf8');
  const code = codeOnly(source);
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
    ['Number.isInteger', /Number\.isInteger/],
    ['String.prototype.padStart', /\.padStart\(/],
    ['Object.assign', /Object\.assign/]
  ];
  for (const entry of runtimeCeiling) {
    assert.equal(entry[1].test(code), false, MODULE_NAME + ' must not use ' + entry[0] + ' (Chromium 68 ceiling)');
  }
  assert.equal(/#[A-Za-z]/.test(stringsBlanked(code)), false, MODULE_NAME + ' must not use a private class field');
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
  // No host API is reached for: no storage, no network, no DOM, and deliberately no URL class, whose
  // normalization would mint a different sourceId from the same row.
  for (const forbidden of [
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
    'TextEncoder'
  ]) {
    assert.ok(code.indexOf(forbidden) === -1, MODULE_NAME + ' must not touch ' + forbidden);
  }
});

test('nothing in the module reads the realm it was loaded in', function () {
  // The loader above shadows `URL`, `Buffer`, `process` and `require`, so a dependency on one would
  // already have thrown. This check is about the other direction: a module that wrote to a real global
  // would leak state between the two loads in section 8 and break the purity claim in section 7.
  const before = Object.keys(global);
  loadInto({}, MODULE_NAME);
  const after = Object.keys(global);
  assert.deepEqual(before, after, 'loading the module adds nothing to the host global object');
});
