/* M3U channel-list parser and source registry (webOS).
 *
 * This is the JavaScript half of a three-port contract. The Dart original lives in
 * `flutter_app/lib/core/playlist_parser.dart` + `source_registry.dart` + `live_catalog.dart`, the
 * Swift port in `Sources/Core/LivePlaylistParser.swift` + `Sources/Core/LiveTVM3UText.swift`, and
 * the same five files under `Tests/fixtures/multi-source/` are what all three are judged against.
 * Verdicts, issue codes, ceiling numbers and identity strings are therefore not free choices here:
 * a playlist that yields three members on Android must yield three members on a TV, or the catalog
 * a user syncs between them is a coin flip.
 *
 * Written in plain ES2017 (`var`, function expressions, string concatenation, explicit index loops)
 * because the runtime is webOS 4 / Chromium 68, and `Tests/webos/playlist_parser.test.js` enforces
 * that ceiling by scanning this file's text — `node --check`, which is all CI runs, accepts newer
 * syntax happily. See `webos_app/app/js/playlist_contracts.js:14` for the same rule.
 *
 * Two deliberate omissions, both load-bearing:
 *
 * * No `new URL()`. It normalizes what the other two ports do not: it collapses `..` and `.`
 *   segments, drops the default port, percent-encodes spaces, and resolves `https://h` to the path
 *   `/`. `Uri.tryParse` (Dart) and `URLComponents` (Swift) keep the text as written, and identity
 *   is hashed from that text, so a normalizing parser would mint a different `sourceId` for the same
 *   row and duplicate a station on refresh. Authorities are therefore split by hand.
 * * No storage and no network. Fetching belongs to `webos_app/app/js/api.js`, persisting to task
 *   B4-J. A contract layer that reached for `localStorage` could not be tested without a TV, and no
 *   TV run is available under the repository's GitHub-hosted-only policy. Nothing in this file is
 *   read by the current screens yet, so shipping it cannot change today's behaviour.
 *
 * Identity rules, restated because they are the reason the exactness above matters:
 * `memberId = "member:" + stableKeyHash(playlistId + "\nprovider\n" + namespace + "\n" +
 * providerChannelId)`, `sourceId = "source:" + stableKeyHash(memberId + "\nurl\n" + canonicalUrl)`.
 * `stableKeyHash` is four seeded FNV-1a passes, NOT a cryptographic digest: it is a stable identity
 * key for one app's own records, and the empty-input vector `811c9dc59e3779b985ebca6bc2b2ae35` is
 * literally the four seeds, which is what proves the accumulator is seeded rather than zero.
 */
window.CC = window.CC || {};

(function () {
  var CC = window.CC;

  // ---- ceilings (identical numbers on all three ports) --------------------------------
  var MAX_BYTES = 10 * 1024 * 1024;
  var MAX_LINES = 200000;
  var MAX_MEMBERS = 50000;
  var MAX_URLS_PER_MEMBER = 100;
  var MAX_URL_CHARS = 8192;
  // Written as an escape, never as a literal: an invisible character in the source is what a later editor
  // silently deletes, and the ceiling check below would then stop stripping a real BOM.
  var BOM = '\uFEFF';

  var STREAM_SCHEMES = ['http', 'https'];
  var SENSITIVE_QUERY_KEYS = [
    'token',
    'key',
    'password',
    'signature',
    'auth',
    'credential'
  ];
  var ATTRIBUTE_NAMES = ['tvg-id', 'tvg-logo', 'group-title', 'tvg-language'];
  var NOISE_TOKENS = ['4k', '8k', 'sd', 'hd', 'fhd', 'uhd', 'hevc', 'multiaudio', 'backup'];

  // ---- stableKeyHash ------------------------------------------------------------------
  // Four independent FNV-1a passes, each with its own seed, concatenated as 8 lowercase hex each.
  // Math.imul gives the low 32 bits of the product, which is exactly what the other ports obtain by
  // masking a 64-bit multiply (Dart) or using multiply-overflow (Swift `&*`), so all three agree.
  var FNV_SEEDS = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35];
  var FNV_PRIME = 0x01000193;

  function utf8ByteLength(value) {
    var total = 0;
    var i = 0;
    while (i < value.length) {
      var code = value.charCodeAt(i);
      if (code < 0x80) {
        total += 1;
        i += 1;
      } else if (code < 0x800) {
        total += 2;
        i += 1;
      } else if (code >= 0xd800 && code <= 0xdbff) {
        var next = i + 1 < value.length ? value.charCodeAt(i + 1) : 0;
        if (next >= 0xdc00 && next <= 0xdfff) {
          total += 4;
          i += 2;
        } else {
          // A lone high surrogate cannot be encoded as UTF-8 at all. Dart's `utf8.encode` throws on
          // it; this port counts it as 3 bytes, which is what a replacement character would cost.
          // Nothing here hashes those bytes for identity, so the only observable effect is whether a
          // pathological playlist crosses the 10 MiB ceiling, and being generous by one byte is the
          // safe direction for a ceiling check.
          total += 3;
          i += 1;
        }
      } else {
        total += 3;
        i += 1;
      }
    }
    return total;
  }

  function utf8Bytes(value) {
    var out = [];
    var i = 0;
    while (i < value.length) {
      var code = value.charCodeAt(i);
      if (code < 0x80) {
        out.push(code);
        i += 1;
      } else if (code < 0x800) {
        out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
        i += 1;
      } else if (code >= 0xd800 && code <= 0xdbff) {
        var next = i + 1 < value.length ? value.charCodeAt(i + 1) : 0;
        if (next >= 0xdc00 && next <= 0xdfff) {
          var point = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
          out.push(
            0xf0 | (point >> 18),
            0x80 | ((point >> 12) & 0x3f),
            0x80 | ((point >> 6) & 0x3f),
            0x80 | (point & 0x3f)
          );
          i += 2;
        } else {
          out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
          i += 1;
        }
      } else {
        out.push(
          0xe0 | (code >> 12),
          0x80 | ((code >> 6) & 0x3f),
          0x80 | (code & 0x3f)
        );
        i += 1;
      }
    }
    return out;
  }

  function hex8(value) {
    var text = (value >>> 0).toString(16);
    while (text.length < 8) {
      text = '0' + text;
    }
    return text;
  }

  function stableKeyHash(value) {
    var bytes = utf8Bytes(value);
    var out = '';
    for (var seed = 0; seed < FNV_SEEDS.length; seed++) {
      var hash = FNV_SEEDS[seed];
      for (var i = 0; i < bytes.length; i++) {
        hash = Math.imul(hash ^ bytes[i], FNV_PRIME) >>> 0;
      }
      out += hex8(hash);
    }
    return out;
  }

  // ---- name normalisation -------------------------------------------------------------
  // The scalar recipe from `live_catalog.dart:liveNameKey`, reproduced code-unit by code-unit.
  // Every mapped range is in the Basic Multilingual Plane, so a supplementary code point is never a
  // candidate for folding and the keep-filter below drops both of its surrogates: iterating UTF-16
  // units here produces the same string as iterating Dart runes. `LiveTVNameKey.key` on macOS is
  // *not* this recipe (it uses ICU folding and does not map Persian digits), which is why the
  // multi-source path carries its own key on every port rather than reusing the shipping one.
  function nameKey(name) {
    var buffer = '';
    for (var i = 0; i < name.length; i++) {
      var value = name.charCodeAt(i);
      if (value >= 0xff01 && value <= 0xff5e) {
        value -= 0xfee0;
      } else if (value === 0x3000) {
        value = 0x20;
      }
      if (
        (value >= 0x0300 && value <= 0x036f) ||
        (value >= 0x0610 && value <= 0x061a) ||
        (value >= 0x064b && value <= 0x065f) ||
        value === 0x0670 ||
        (value >= 0x06d6 && value <= 0x06ed)
      ) {
        continue;
      }
      if (value === 0x064a || value === 0x0626 || value === 0x0649) {
        value = 0x06cc;
      } else if (value === 0x0643) {
        value = 0x06a9;
      } else if (value === 0x0629) {
        value = 0x0647;
      } else if (value === 0x0622 || value === 0x0623 || value === 0x0625 || value === 0x0671) {
        value = 0x0627;
      } else if (value === 0x0624) {
        value = 0x0648;
      } else if (value === 0x200c || value === 0x200d || value === 0x00a0) {
        value = 0x20;
      } else if (value >= 0x06f0 && value <= 0x06f9) {
        value = 0x30 + (value - 0x06f0);
      } else if (value >= 0x0660 && value <= 0x0669) {
        value = 0x30 + (value - 0x0660);
      }
      buffer += String.fromCharCode(value);
    }

    var cleaned = buffer.toLowerCase();
    var key = '';
    var pendingSpace = false;
    for (var j = 0; j < cleaned.length; j++) {
      var rune = cleaned.charCodeAt(j);
      var kept =
        (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x61 && rune <= 0x7a) ||
        (rune >= 0x0600 && rune <= 0x06ff);
      if (kept) {
        if (pendingSpace && key.length > 0) {
          key += ' ';
        }
        key += String.fromCharCode(rune);
        pendingSpace = false;
      } else {
        pendingSpace = true;
      }
    }
    return key;
  }

  function isNoiseToken(inner) {
    var token = inner.toLowerCase().split(' ').join('');
    if (token.length === 0) {
      return true;
    }
    if (NOISE_TOKENS.indexOf(token) !== -1) {
      return true;
    }
    if (token.substring(0, 3) === 'not') {
      return true;
    }
    return /^\d{1,4}[kpi]\d*$/.test(token);
  }

  // iptv-org appends the stream quality to the display name: `Press TV (720p)` shows as `Press TV`.
  // Same rule as `m3uDisplayName` in Dart and `LiveTVM3UText.displayName` in Swift, including the
  // `(`/`[` pairing that must survive when the bracketed text is not noise, e.g. `A (B) C`.
  function displayName(raw) {
    var result = '';
    var index = 0;
    while (index < raw.length) {
      var character = raw.charAt(index);
      if (character === '(' || character === '[') {
        var closer = character === '(' ? ')' : ']';
        var end = raw.indexOf(closer, index + 1);
        if (end >= 0 && isNoiseToken(raw.substring(index + 1, end))) {
          index = end + 1;
          continue;
        }
      }
      result += character;
      index += 1;
    }
    var parts = result.split(/\s+/);
    var kept = [];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        kept.push(parts[i]);
      }
    }
    return kept.join(' ');
  }

  function persianDigits(value) {
    var text = String(value);
    var out = '';
    for (var i = 0; i < text.length; i++) {
      var code = text.charCodeAt(i);
      out += code >= 0x30 && code <= 0x39 ? String.fromCharCode(0x06f0 + (code - 0x30)) : text.charAt(i);
    }
    return out;
  }

  // ---- address handling ---------------------------------------------------------------
  function hasPrefix(value, prefix) {
    return value.length >= prefix.length && value.substring(0, prefix.length) === prefix;
  }

  function isAlphaNumeric(value, code) {
    return (
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      value === '+' || value === '-' || value === '.'
    );
  }

  // RFC 3986 scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) followed by ":".
  function schemeOf(value) {
    if (value.length === 0) {
      return '';
    }
    var first = value.charAt(0);
    if (!((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z'))) {
      return '';
    }
    var i = 1;
    while (i < value.length) {
      var character = value.charAt(i);
      if (!isAlphaNumeric(character, value.charCodeAt(i))) {
        break;
      }
      i += 1;
    }
    if (i >= value.length || value.charAt(i) !== ':') {
      return '';
    }
    return value.substring(0, i);
  }

  // Splits a reference into its five parts *without* normalizing any of them, so that the text the
  // identity hash is computed from is the text the playlist contained.
  function splitReference(value) {
    var rest = value;
    var fragment = null;
    var hash = rest.indexOf('#');
    if (hash >= 0) {
      fragment = rest.substring(hash + 1);
      rest = rest.substring(0, hash);
    }
    var query = null;
    var mark = rest.indexOf('?');
    if (mark >= 0) {
      query = rest.substring(mark + 1);
      rest = rest.substring(0, mark);
    }
    var scheme = schemeOf(rest);
    var hadScheme = scheme.length > 0;
    var path = hadScheme ? rest.substring(scheme.length + 1) : rest;
    var authority = null;
    if (hasPrefix(path, '//')) {
      var after = path.substring(2);
      var cut = after.length;
      for (var i = 0; i < after.length; i++) {
        var character = after.charAt(i);
        if (character === '/' || character === '?' || character === '#') {
          cut = i;
          break;
        }
      }
      authority = after.substring(0, cut);
      path = after.substring(cut);
    }
    return {
      scheme: scheme,
      hadScheme: hadScheme,
      authority: authority,
      path: path,
      query: query,
      fragment: fragment
    };
  }

  function joinReference(scheme, authority, path, query, fragment) {
    var out = scheme + '://' + authority + path;
    if (query !== null) {
      out += '?' + query;
    }
    if (fragment !== null) {
      out += '#' + fragment;
    }
    return out;
  }

  // RFC 3986 §5.2.4. Written out rather than trusted to the platform, because the platform's own
  // resolver is exactly the normalizer this port is not allowed to use.
  function removeDotSegments(path) {
    var input = path;
    var output = '';
    while (input.length > 0) {
      if (hasPrefix(input, '../')) {
        input = input.substring(3);
      } else if (hasPrefix(input, './')) {
        input = input.substring(2);
      } else if (hasPrefix(input, '/./')) {
        input = '/' + input.substring(3);
      } else if (hasPrefix(input, '/../')) {
        input = '/' + input.substring(4);
        var cut = output.lastIndexOf('/');
        output = cut >= 0 ? output.substring(0, cut) : '';
      } else if (input === '.' || input === '..') {
        input = '';
      } else {
        var end = input.indexOf('/', 1);
        if (end < 0) {
          output += input;
          input = '';
        } else {
          output += input.substring(0, end);
          input = input.substring(end);
        }
      }
    }
    return output;
  }

  // RFC 3986 §5.3 with the reference known to be relative (the caller checked the scheme).
  function resolveAgainst(base, reference) {
    if (reference.authority !== null) {
      return joinReference(
        base.scheme,
        reference.authority,
        removeDotSegments(reference.path),
        reference.query,
        reference.fragment
      );
    }
    if (reference.path.length === 0) {
      return joinReference(
        base.scheme,
        base.authority,
        base.path,
        reference.query === null ? base.query : reference.query,
        reference.fragment
      );
    }
    var merged;
    if (hasPrefix(reference.path, '/')) {
      merged = removeDotSegments(reference.path);
    } else {
      var basePath = base.path;
      var prefix = '';
      if (base.authority !== null && basePath.length === 0) {
        prefix = '/';
      } else {
        var slash = basePath.lastIndexOf('/');
        if (slash >= 0) {
          prefix = basePath.substring(0, slash + 1);
        }
      }
      merged = removeDotSegments(prefix + reference.path);
    }
    return joinReference(
      base.scheme,
      base.authority,
      merged,
      reference.query,
      reference.fragment
    );
  }

  // Reduces a stream address to the form identity is computed from, or null when it is unusable.
  // Only scheme and host fold; path and query keep their case, because CDN paths are
  // case-sensitive. A fragment is refused rather than stripped (`a.m3u8#1` and `a.m3u8#2` were two
  // rows in the playlist), and userinfo is refused because it is a credential, not an address.
  function canonicalStreamUrl(rawUrl) {
    var reference = splitReference(rawUrl);
    var scheme = reference.scheme.toLowerCase();
    if (STREAM_SCHEMES.indexOf(scheme) === -1) {
      return null;
    }
    if (reference.fragment !== null) {
      return null;
    }
    if (reference.authority === null) {
      return null;
    }
    if (reference.authority.indexOf('@') >= 0) {
      return null;
    }
    var host = reference.authority;
    var port = '';
    if (hasPrefix(host, '[')) {
      var close = host.indexOf(']');
      if (close < 0) {
        return null;
      }
      var tail = host.substring(close + 1);
      if (tail.length === 0) {
        host = host.substring(0, close + 1);
      } else if (tail.charAt(0) === ':') {
        host = host.substring(0, close + 1);
        port = tail.substring(1);
      } else {
        return null;
      }
    } else {
      var colon = host.lastIndexOf(':');
      if (colon >= 0) {
        port = host.substring(colon + 1);
        host = host.substring(0, colon);
      }
    }
    if (host.length === 0) {
      return null;
    }
    if (port.length > 0 && !/^\d+$/.test(port)) {
      return null;
    }
    // Both `Uri` and `URLComponents` refuse a port outside the 16-bit range, and writing one through
    // would put an address no player can open into a persisted `sourceId`.
    var numericPort = port.length > 0 ? parseInt(port, 10) : 0;
    if (numericPort > 65535) {
      return null;
    }
    // Authority characters this port will accept, and no more. Dart's `Uri` and Foundation's
    // `URLComponents` both reject a reg-name containing a space, a control character, a quote or a
    // backslash, and both *transform* a non-ASCII host (IDNA or percent-encoding) in a way a hand
    // split cannot reproduce, so those addresses are refused here rather than guessed at. Every
    // fixture, golden vector and iptv-org authority is plain ASCII, so the refusal path is a
    // documented divergence with no effect on the current catalog: an exotic host yields one visible
    // `invalidUrl` issue instead of a `sourceId` that only two of three ports agree on.
    if (hasPrefix(host, '[')) {
      if (!/^\[[0-9A-Fa-f:.]+\]$/.test(host)) {
        return null;
      }
    } else if (!/^[A-Za-z0-9\-._~!$&\x27()*+,;=%]+$/.test(host)) {
      return null;
    }
    var path = reference.path;
    if (path.length === 0 || path === '/') {
      return null;
    }
    var out = scheme + '://' + host.toLowerCase();
    if (port.length > 0) {
      var defaultPort = scheme === 'http' ? 80 : 443;
      if (numericPort !== defaultPort) {
        out += ':' + numericPort;
      }
    }
    out += path;
    if (reference.query !== null && reference.query.length > 0) {
      out += '?' + reference.query;
    }
    return out;
  }

  // True when the address carries a credential that must never be persisted as plaintext. Exact
  // query keys, case-insensitively: a substring test would flag `/monkey.m3u8` and drop a
  // legitimate channel, which is worse than the leak it tries to prevent.
  function isSensitiveUrl(rawUrl) {
    var reference = splitReference(rawUrl);
    if (reference.authority !== null && reference.authority.indexOf('@') >= 0) {
      return true;
    }
    if (reference.query === null) {
      return false;
    }
    var pairs = reference.query.split('&');
    for (var i = 0; i < pairs.length; i++) {
      var pair = pairs[i];
      if (pair.length === 0) {
        continue;
      }
      var equals = pair.indexOf('=');
      var key = (equals < 0 ? pair : pair.substring(0, equals)).toLowerCase();
      if (SENSITIVE_QUERY_KEYS.indexOf(key) !== -1) {
        return true;
      }
    }
    return false;
  }

  function protocolHint(canonicalUrl) {
    var reference = splitReference(canonicalUrl);
    var path = reference.path.toLowerCase();
    if (hasSuffix(path, '.m3u8')) {
      return 'hls';
    }
    if (hasSuffix(path, '.mpd')) {
      return 'dash';
    }
    if (hasSuffix(path, '.mp4')) {
      return 'mp4';
    }
    return 'unknown';
  }

  function hasSuffix(path, suffix) {
    return path.length >= suffix.length && path.substring(path.length - suffix.length) === suffix;
  }

  function issue(code, message, line) {
    return { code: code, message: message, line: line === undefined ? null : line };
  }

  function firstLine(text) {
    var end = text.indexOf('\n');
    var line = end < 0 ? text : text.substring(0, end);
    // `replaceFirst` semantics, matching Dart: only the leading carriage return of a CRLF line is
    // removed, so a line containing an interior CR normalizes the same way on every port.
    var cr = line.indexOf('\r');
    if (cr >= 0) {
      line = line.substring(0, cr) + line.substring(cr + 1);
    }
    return line.trim();
  }

  // ---- parse --------------------------------------------------------------------------
  function attributesOf(header) {
    var result = {};
    for (var i = 0; i < ATTRIBUTE_NAMES.length; i++) {
      var name = ATTRIBUTE_NAMES[i];
      var pattern = new RegExp(name.replace(/-/g, '\\-') + '="([^"]*)"');
      var match = pattern.exec(header);
      if (match === null) {
        continue;
      }
      var value = match[1].trim();
      if (value.length > 0) {
        result[name] = value;
      }
    }
    return result;
  }

  // Turns one `#EXTINF` row into a draft. The split is on the *last* comma because both attributes
  // and names may contain one, and iptv-org puts the name after the final one.
  function rowFrom(header, number, issues, fallbackOccurrences) {
    var comma = header.lastIndexOf(',');
    if (comma < 0) {
      issues.push(issue(
        'malformedEntry',
        'line ' + number + ' is an #EXTINF row with no display-name field',
        number
      ));
      return null;
    }
    var name = displayName(header.substring(comma + 1));
    if (name.length === 0) {
      issues.push(issue(
        'missingName',
        'line ' + number + ' is an #EXTINF row whose display name is empty',
        number
      ));
      return null;
    }

    var attributes = attributesOf(header.substring(0, comma));
    var rawId = attributes['tvg-id'] === undefined ? '' : attributes['tvg-id'];
    var logo = attributes['tvg-logo'] === undefined ? null : attributes['tvg-logo'];
    var group = attributes['group-title'] === undefined ? null : attributes['group-title'];

    // A trailing `@quality` marker is not identity and the last dotted suffix is the country, not
    // part of the station name — the same rule the shipping Iran list uses.
    var base = rawId;
    var at = base.indexOf('@');
    if (at >= 0) {
      base = base.substring(0, at);
    }
    var countryCode = null;
    var dot = base.lastIndexOf('.');
    if (dot >= 0) {
      countryCode = base.substring(dot + 1).toUpperCase();
      base = base.substring(0, dot);
    }

    var providerChannelId;
    if (base.length > 0) {
      providerChannelId = base;
    } else {
      // The occurrence index keeps two unnamed rows apart; without it they collapse into one channel
      // and one of the user's streams silently vanishes.
      var tuple = nameKey(name) + '|' + (countryCode === null ? '' : countryCode) + '|' +
        (group === null ? '' : group) + '|' + (logo === null ? '' : logo);
      var occurrence = fallbackOccurrences[tuple] === undefined ? 0 : fallbackOccurrences[tuple];
      fallbackOccurrences[tuple] = occurrence + 1;
      providerChannelId = 'fallback:' + tuple + '|' + occurrence;
    }

    var languages = [];
    var rawLanguages = attributes['tvg-language'] === undefined ? '' : attributes['tvg-language'];
    var parts = rawLanguages.split(',');
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i].trim();
      if (part.length > 0) {
        languages.push(part);
      }
    }

    return {
      key: providerChannelId,
      providerChannelId: providerChannelId,
      displayName: name,
      number: number,
      logoUrl: logo,
      group: group,
      countryCode: countryCode,
      languages: languages,
      // The unstripped attribute survives so a later identity review can see `@SD` and `.ir`.
      tvgId: rawId.length === 0 ? null : rawId,
      urls: [],
      sawAddressLine: false
    };
  }

  function canonicalAddress(raw, line, baseReference, issues) {
    var reference = splitReference(raw);
    var candidate = null;
    if (reference.hadScheme) {
      candidate = raw;
    } else if (
      baseReference !== null &&
      baseReference.authority !== null &&
      STREAM_SCHEMES.indexOf(baseReference.scheme.toLowerCase()) !== -1
    ) {
      // The authority check is not defensive padding: `Uri.resolve` on an authority-less base yields
      // the reference as an authority (`https:live.m3u8` -> host `live.m3u8`, empty path), which the
      // canonicalizer then refuses. A hand-written resolver that inserted the literal `null` here
      // would instead *accept* a host named "null", so the two ports would disagree on one row.
      candidate = resolveAgainst(baseReference, reference);
    }
    if (candidate === null) {
      issues.push(issue(
        'invalidUrl',
        'stream address on line ' + line + ' is not absolute and no HTTP(S) base was supplied',
        line
      ));
      return null;
    }
    var canonical = canonicalStreamUrl(candidate);
    if (canonical === null) {
      issues.push(issue(
        'invalidUrl',
        'stream address on line ' + line + ' is not an HTTP(S) address this build can play',
        line
      ));
      return null;
    }
    return canonical;
  }

  /**
   * Parses one M3U playlist `text` into provider rows.
   *
   * `playlistId` only labels issues; identity is built by `registerParsedPlaylist`. `baseUri` is the
   * address the playlist was fetched from, as a string or null, and a relative address resolves
   * against it **only** when that base is HTTP(S): a `file:` base must not smuggle a relative path
   * into something a player will fetch.
   */
  function parsePlaylist(playlistId, text, baseUri) {
    var issues = [];
    var inputBytes = utf8ByteLength(text);

    // Checked before any splitting or hashing: refusing a ten-megabyte payload cheaply is the whole
    // point of a ceiling, and hashing refused bytes is wasted work.
    if (inputBytes > MAX_BYTES) {
      return {
        format: hasPrefix(firstLine(text), '#EXTM3U') ? 'm3uChannelList' : 'invalid',
        channels: [],
        issues: [issue(
          'oversizedInput',
          'playlist for ' + playlistId + ' is ' + inputBytes + ' bytes, above the ' + MAX_BYTES +
            '-byte ceiling, so nothing was parsed',
          1
        )],
        contentHash: '',
        inputBytes: inputBytes,
        truncated: true
      };
    }

    var contentHash = stableKeyHash(text);
    // A leading BOM belongs to the encoding, not to the `#EXTM3U` token.
    var body = hasPrefix(text, BOM) ? text.substring(1) : text;
    var allLines = body.split(/\r?\n/);
    var truncated = false;
    var lineCount = allLines.length;
    if (lineCount > MAX_LINES) {
      truncated = true;
      issues.push(issue(
        'limitExceeded',
        'playlist for ' + playlistId + ' has ' + allLines.length + ' lines; parsing stopped at the ' +
          MAX_LINES + '-line ceiling',
        MAX_LINES
      ));
      lineCount = MAX_LINES;
    }

    // Null-prototype maps: a tvg-id of `constructor` or `__proto__` is a legal playlist value, and on
    // an ordinary object it would collide with Object.prototype and swallow or invent a row.
    var rows = Object.create(null);
    var fallbackOccurrences = Object.create(null);
    var order = [];
    var open = null;
    var sawExtInf = false;
    var sawStreamInf = false;

    function closeOpen() {
      var row = open;
      if (row === null) {
        return;
      }
      open = null;
      if (row.urls.length === 0 && !row.sawAddressLine) {
        issues.push(issue(
          'missingStream',
          '"' + row.displayName + '" has no stream address on line ' + row.number,
          row.number
        ));
      }
    }

    var baseReference = null;
    if (baseUri !== undefined && baseUri !== null) {
      baseReference = splitReference(String(baseUri));
      if (!baseReference.hadScheme) {
        baseReference = null;
      }
    }

    for (var index = 0; index < lineCount; index++) {
      var line = index + 1;
      var raw = allLines[index].trim();
      if (raw.length === 0) {
        continue;
      }

      if (hasPrefix(raw, '#EXTINF')) {
        sawExtInf = true;
        closeOpen();
        if (order.length >= MAX_MEMBERS) {
          // The permitted prefix is kept rather than discarded, so the user sees 50,000 real rows
          // plus one honest issue instead of an empty list.
          truncated = true;
          issues.push(issue(
            'limitExceeded',
            'playlist for ' + playlistId + ' exceeded the ' + MAX_MEMBERS + '-member ceiling on line ' +
              line,
            line
          ));
          break;
        }
        var row = rowFrom(raw, line, issues, fallbackOccurrences);
        if (row === null) {
          continue;
        }
        var existing = rows[row.key];
        if (existing !== undefined) {
          // Repeated ids merge in first-seen order: the first row keeps its line, name and metadata
          // so a re-listed station does not jump position.
          existing.sawAddressLine = false;
          open = existing;
          continue;
        }
        order.push(row.key);
        rows[row.key] = row;
        open = row;
        continue;
      }

      if (hasPrefix(raw, '#')) {
        if (hasPrefix(raw, '#EXT-X-STREAM-INF')) {
          sawStreamInf = true;
        }
        continue;
      }

      var pending = open;
      if (pending === null) {
        continue; // An address with no row before it is not a channel.
      }
      pending.sawAddressLine = true;
      if (pending.urls.length >= MAX_URLS_PER_MEMBER) {
        truncated = true;
        issues.push(issue(
          'limitExceeded',
          '"' + pending.displayName + '" exceeded ' + MAX_URLS_PER_MEMBER + ' stream addresses on line ' +
            line,
          line
        ));
        open = null;
        continue;
      }
      // The character ceiling is charged here rather than inside the canonicalizer because crossing
      // it drops a stream the user could otherwise see, so the parse is partial and must say so. A
      // URL is never truncated to fit either: half an address would still look playable.
      if (raw.length > MAX_URL_CHARS) {
        truncated = true;
        issues.push(issue(
          'limitExceeded',
          'stream address on line ' + line + ' is ' + raw.length + ' characters, above the ' +
            MAX_URL_CHARS + '-character ceiling',
          line
        ));
        continue;
      }
      var canonical = canonicalAddress(raw, line, baseReference, issues);
      if (canonical !== null && pending.urls.indexOf(canonical) === -1) {
        pending.urls.push(canonical);
      }
    }
    closeOpen();

    if (!sawExtInf && sawStreamInf) {
      return {
        format: 'hlsMediaManifest',
        channels: [],
        issues: [issue(
          'unsupportedMediaManifest',
          'playlist for ' + playlistId + ' is an HLS media manifest, not an M3U channel list, so no ' +
            'channels were imported',
          1
        )],
        contentHash: contentHash,
        inputBytes: inputBytes,
        truncated: truncated
      };
    }

    if (!hasPrefix(firstLine(body), '#EXTM3U')) {
      issues.push(issue(
        'malformedEntry',
        'playlist for ' + playlistId + ' has no #EXTM3U header, so it is not treated as a channel list',
        1
      ));
      return {
        format: 'invalid',
        channels: [],
        issues: issues,
        contentHash: contentHash,
        inputBytes: inputBytes,
        truncated: truncated
      };
    }

    var channels = [];
    for (var k = 0; k < order.length; k++) {
      var entry = rows[order[k]];
      if (entry !== undefined && entry.urls.length > 0) {
        channels.push({
          providerChannelId: entry.providerChannelId,
          displayName: entry.displayName,
          streamUrls: entry.urls.slice(),
          line: entry.number,
          logoUrl: entry.logoUrl,
          group: entry.group,
          countryCode: entry.countryCode,
          languages: entry.languages.slice(),
          tvgId: entry.tvgId
        });
      }
    }

    return {
      format: order.length === 0 ? 'empty' : 'm3uChannelList',
      channels: channels,
      issues: issues,
      contentHash: contentHash,
      inputBytes: inputBytes,
      truncated: truncated
    };
  }

  // ---- registry -----------------------------------------------------------------------
  // Records are emitted in exactly the field names and value shapes that `CC.playlistContracts`
  // both reads and writes: required strings are strings, every absent optional is `null`, and
  // `rendererCapability` carries the codec's own `Not Yet Verified` label rather than `null`, because
  // `writeSource` demands one of the four RendererSupport labels while `readSource` would have
  // defaulted a missing one. Task B4-J can therefore persist what this returns with no translation
  // layer that could drift from the codec.
  function registerParsedPlaylist(parsed, playlistId, providerNamespace) {
    var members = [];
    var sources = [];
    var issues = [];
    var channels = parsed.channels;

    for (var i = 0; i < channels.length; i++) {
      var channel = channels[i];
      var memberId = 'member:' + stableKeyHash(
        playlistId + '\nprovider\n' + providerNamespace + '\n' + channel.providerChannelId
      );
      members.push({
        memberId: memberId,
        playlistId: playlistId,
        providerNamespace: providerNamespace,
        providerChannelId: channel.providerChannelId,
        displayName: channel.displayName,
        normalizedName: nameKey(channel.displayName),
        ordinal: members.length,
        logoUrl: channel.logoUrl,
        group: channel.group,
        countryCode: channel.countryCode,
        languages: channel.languages.slice(),
        tvgId: channel.tvgId
      });

      var seen = Object.create(null);
      var priority = 0;
      for (var j = 0; j < channel.streamUrls.length; j++) {
        var canonical = canonicalStreamUrl(channel.streamUrls[j]);
        if (canonical === null) {
          // Defensive rather than redundant: the parser already canonicalized, so reaching here means
          // canonicalization stopped being idempotent, and that is a bug worth a visible issue
          // rather than a silently missing source.
          issues.push(issue(
            'invalidUrl',
            'member ' + memberId + ' offered an address that is not canonicalizable: line ' +
              channel.line,
            channel.line
          ));
          continue;
        }
        // Two spellings of one origin are one source. Deduplicating is not an error, so it reports
        // nothing: the ceilings in the parser own the `limitExceeded` cases.
        if (seen[canonical] === true) {
          continue;
        }
        seen[canonical] = true;

        if (isSensitiveUrl(canonical)) {
          // No platform has a verified secret store yet, and the contract forbids persisting a
          // credential-bearing address as plaintext. Refusing with this code is the honest outcome:
          // once a secret store is verified, the same row becomes a `streamSecretRef` instead.
          issues.push(issue(
            'secretStorageUnavailable',
            'a stream address for ' + channel.displayName + ' carries a credential and was not ' +
              'stored, because no verified secret store exists on this platform',
            channel.line
          ));
          continue;
        }

        sources.push({
          sourceId: 'source:' + stableKeyHash(memberId + '\nurl\n' + canonical),
          // Rule 4: a new logical channel uses its member ID until the user associates it.
          channelId: memberId,
          memberId: memberId,
          playlistId: playlistId,
          providerNamespace: providerNamespace,
          label: priority === 0 ? 'منبع اصلی' : 'منبع ' + persianDigits(priority + 1),
          streamUrl: canonical,
          streamSecretRef: null,
          protocolHint: protocolHint(canonical),
          // The label, not null: the codec's writer refuses a missing capability, and naming the
          // value keeps "we have no evidence" identical to what Dart and Swift serialize.
          rendererCapability: 'Not Yet Verified',
          origin: 'playlist',
          priority: priority,
          enabled: true,
          health: 'unverified',
          lastSuccessfulPlaybackAt: null,
          lastFailedPlaybackAt: null,
          lastErrorCode: null
        });
        priority++;
      }
    }

    return { members: members, sources: sources, issues: issues };
  }

  CC.playlistParser = {
    limits: {
      maxBytes: MAX_BYTES,
      maxLines: MAX_LINES,
      maxMembers: MAX_MEMBERS,
      maxUrlsPerMember: MAX_URLS_PER_MEMBER,
      maxUrlChars: MAX_URL_CHARS
    },
    streamSchemes: STREAM_SCHEMES.slice(),
    sensitiveQueryKeys: SENSITIVE_QUERY_KEYS.slice(),
    stableKeyHash: stableKeyHash,
    utf8ByteLength: utf8ByteLength,
    nameKey: nameKey,
    displayName: displayName,
    isNoiseToken: isNoiseToken,
    canonicalStreamUrl: canonicalStreamUrl,
    isSensitiveUrl: isSensitiveUrl,
    protocolHint: protocolHint,
    parsePlaylist: parsePlaylist,
    registerParsedPlaylist: registerParsedPlaylist
  };
})();
