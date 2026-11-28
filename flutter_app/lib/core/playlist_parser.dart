import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'identity_hash.dart';
import 'live_catalog.dart';
import 'live_contracts.dart';

// MARK: - Multi-source playlist parsing (Task B2-D)
//
// This is the parser the Multi-Source product work needs: it turns one fetched playlist into
// provider rows plus visible issues, without touching playback, storage or the network. It
// deliberately does not replace parseM3u in `live_catalog.dart` — that function still builds the
// existing built-in Iran list, and changing it would alter shipping behavior for every user at
// once. What this file does reuse is the normalization, because two foldings of the same channel
// name would silently split one station into two: liveNameKey and m3uDisplayName are imported
// rather than reimplemented.
//
// The Swift (`Sources/Core/LivePlaylistParser.swift`) and webOS (`webos_app/app/js/playlist_parser.js`)
// ports read the same bytes under `Tests/fixtures/multi-source/` and must reach the same verdicts.
// Every rule below is therefore stated in code rather than left to a runtime default:
// classification, issue codes, line numbers, ceilings and URL canonicalization are all part of
// that shared contract.

/// What a fetched document turned out to be.
enum PlaylistFormat { m3uChannelList, hlsMediaManifest, empty, invalid }

/// Resource-safety ceilings from the specification. They are not product quotas: nothing stops a
/// user at a smaller playlist, and crossing one truncates the parse *and says so* through
/// `PlaylistParseResult.truncated` plus a `limitExceeded` or `oversizedInput` issue, so a partial
/// catalog can never be mistaken for a complete one.
const int playlistMaxBytes = 10 * 1024 * 1024;
const int playlistMaxLines = 200000;
const int playlistMaxMembers = 50000;
const int playlistMaxUrlsPerMember = 100;
const int playlistMaxUrlChars = 8192;

/// The schemes a stream address may use. Anything else (`ftp:`, `file:`, `udp:`) is refused before
/// it can reach a player, because the renderer evidence collected so far covers HTTP(S) only.
const List<String> streamSchemes = ['http', 'https'];

/// Keys that make a query string a credential rather than a parameter.
const List<String> sensitiveQueryKeys = [
  'token',
  'key',
  'password',
  'signature',
  'auth',
  'credential',
];

/// One channel as a single playlist stated it, before any identity or association work.
class ParsedChannel {
  const ParsedChannel({
    required this.providerChannelId,
    required this.displayName,
    required this.streamUrls,
    required this.line,
    this.logoUrl,
    this.group,
    this.countryCode,
    this.languages = const [],
    this.tvgId,
  });

  /// The provider's own channel identifier with the country suffix removed, or a `fallback:` key
  /// when the row carried no `tvg-id` (identity rule 2).
  final String providerChannelId;
  final String displayName;

  /// Canonical, already-resolved HTTP(S) addresses in first-seen order. A row with none of these is
  /// not reported as a channel at all.
  final List<String> streamUrls;

  /// Physical line of the `#EXTINF` row, 1-based, so an issue can point at the row that caused it.
  final int line;
  final String? logoUrl;
  final String? group;
  final String? countryCode;
  final List<String> languages;

  /// The untouched `tvg-id` attribute, including any `@quality` or `.country` suffix. This and
  /// `line` are what make a later identity review debuggable without re-parsing.
  final String? tvgId;
}

/// The outcome of parsing one playlist document.
class PlaylistParseResult {
  const PlaylistParseResult({
    required this.format,
    required this.channels,
    required this.issues,
    required this.contentHash,
    required this.inputBytes,
    required this.truncated,
  });

  final PlaylistFormat format;
  final List<ParsedChannel> channels;
  final List<CatalogIssue> issues;

  /// stableKeyHash over the exact decoded text, so a refresh that fetched identical content can
  /// skip re-parsing without comparing a whole playlist's worth of strings. Empty when the payload
  /// was refused before parsing, because then there is no imported content to key.
  final String contentHash;

  /// Length of the parsed text in UTF-8 bytes, kept beside the hash so a size regression is visible
  /// in the same record.
  final int inputBytes;
  final bool truncated;
}

class _Row {
  _Row({
    required this.key,
    required this.providerChannelId,
    required this.displayName,
    required this.number,
    this.logoUrl,
    this.group,
    this.countryCode,
    this.languages = const [],
    this.tvgId,
  });

  final String key;
  final String providerChannelId;
  final String displayName;

  /// Physical line of this row's `#EXTINF`. A repeated provider id keeps the first row's number,
  /// because re-listing a station must not move it.
  final int number;
  final String? logoUrl;
  final String? group;
  final String? countryCode;
  final List<String> languages;
  final String? tvgId;
  final List<String> urls = [];

  /// True once any non-comment line followed this row, whether or not it was usable. It is what
  /// separates "the playlist never gave this row an address" (`missingStream`) from "the address it
  /// gave was refused" (`invalidUrl`), so one bad row cannot report both.
  bool sawAddressLine = false;
}

/// Parses one M3U playlist [text] into provider rows.
///
/// [playlistId] only labels issues; identity is built by `registerParsedPlaylist`. Relative
/// addresses resolve against [baseUri] **only** when that base is HTTP(S): a `file:` base must not
/// smuggle a relative path into something a player will fetch.
PlaylistParseResult parsePlaylist({
  required String playlistId,
  required String text,
  Uri? baseUri,
}) {
  final issues = <CatalogIssue>[];
  final inputBytes = utf8.encode(text).length;

  // The size ceiling is checked before any splitting or hashing: refusing a ten-megabyte payload
  // cheaply is the whole point of a ceiling, and hashing refused bytes is wasted work.
  if (inputBytes > playlistMaxBytes) {
    return PlaylistParseResult(
      format: _firstLine(text).startsWith('#EXTM3U')
          ? PlaylistFormat.m3uChannelList
          : PlaylistFormat.invalid,
      channels: const [],
      issues: [
        CatalogIssue(
          code: 'oversizedInput',
          message: 'playlist for $playlistId is $inputBytes bytes, above the '
              '$playlistMaxBytes-byte ceiling, so nothing was parsed',
          line: 1,
        ),
      ],
      contentHash: '',
      inputBytes: inputBytes,
      truncated: true,
    );
  }

  final contentHash = stableKeyHash(text);
  // A leading BOM belongs to the encoding, not to the `#EXTM3U` token.
  final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final allLines = body.split(RegExp(r'\r?\n'));
  var truncated = false;

  var lineCount = allLines.length;
  if (lineCount > playlistMaxLines) {
    truncated = true;
    issues.add(CatalogIssue(
      code: 'limitExceeded',
      message: 'playlist for $playlistId has ${allLines.length} lines; parsing stopped at the '
          '$playlistMaxLines-line ceiling',
      line: playlistMaxLines,
    ));
    lineCount = playlistMaxLines;
  }

  final order = <String>[];
  final rows = <String, _Row>{};
  final fallbackOccurrences = <String, int>{};
  _Row? open;
  var sawExtInf = false;
  var sawStreamInf = false;

  void closeOpen() {
    final row = open;
    if (row == null) return;
    open = null;
    if (row.urls.isEmpty && !row.sawAddressLine) {
      issues.add(CatalogIssue(
        code: 'missingStream',
        message: '"${row.displayName}" has no stream address on line ${row.number}',
        line: row.number,
      ));
    }
  }

  for (var index = 0; index < lineCount; index++) {
    final line = index + 1;
    final raw = allLines[index].trim();
    if (raw.isEmpty) continue;

    if (raw.startsWith('#EXTINF')) {
      sawExtInf = true;
      closeOpen();
      if (rows.length >= playlistMaxMembers) {
        // The permitted prefix is kept rather than discarded, so the user sees 50,000 real rows
        // plus one honest issue instead of an empty list.
        truncated = true;
        issues.add(CatalogIssue(
          code: 'limitExceeded',
          message: 'playlist for $playlistId exceeded the $playlistMaxMembers-member ceiling '
              'on line $line',
          line: line,
        ));
        break;
      }
      final row = _rowFrom(
        raw,
        number: line,
        issues: issues,
        fallbackOccurrences: fallbackOccurrences,
      );
      if (row == null) continue;
      final existing = rows[row.key];
      if (existing != null) {
        // Repeated non-empty provider ids merge in first-seen order: the first row keeps its line,
        // name and metadata so a re-listed station does not jump position.
        existing.sawAddressLine = false;
        open = existing;
        continue;
      }
      order.add(row.key);
      rows[row.key] = row;
      open = row;
      continue;
    }

    if (raw.startsWith('#')) {
      if (raw.startsWith('#EXT-X-STREAM-INF')) sawStreamInf = true;
      continue;
    }

    final row = open;
    if (row == null) continue; // An address with no row before it is not a channel.
    row.sawAddressLine = true;
    if (row.urls.length >= playlistMaxUrlsPerMember) {
      truncated = true;
      issues.add(CatalogIssue(
        code: 'limitExceeded',
        message: '"${row.displayName}" exceeded $playlistMaxUrlsPerMember stream addresses '
            'on line $line',
        line: line,
      ));
      open = null;
      continue;
    }
    // The character ceiling is charged here rather than inside the canonicalizer because crossing
    // it drops a stream the user could otherwise see, so the parse is partial and must say so.
    // A URL is never truncated to fit either: half an address would still look playable.
    if (raw.length > playlistMaxUrlChars) {
      truncated = true;
      issues.add(CatalogIssue(
        code: 'limitExceeded',
        message: 'stream address on line $line is ${raw.length} characters, above the '
            '$playlistMaxUrlChars-character ceiling',
        line: line,
      ));
      continue;
    }
    final canonical = _canonicalAddress(raw, line, baseUri, issues);
    if (canonical != null && !row.urls.contains(canonical)) {
      row.urls.add(canonical);
    }
  }
  closeOpen();

  if (!sawExtInf && sawStreamInf) {
    return PlaylistParseResult(
      format: PlaylistFormat.hlsMediaManifest,
      channels: const [],
      issues: [
        CatalogIssue(
          code: 'unsupportedMediaManifest',
          message: 'playlist for $playlistId is an HLS media manifest, not an M3U channel list, '
              'so no channels were imported',
          line: 1,
        ),
      ],
      contentHash: contentHash,
      inputBytes: inputBytes,
      truncated: truncated,
    );
  }

  if (!_firstLine(body).startsWith('#EXTM3U')) {
    issues.add(CatalogIssue(
      code: 'malformedEntry',
      message: 'playlist for $playlistId has no #EXTM3U header, so it is not treated as a '
          'channel list',
      line: 1,
    ));
    return PlaylistParseResult(
      format: PlaylistFormat.invalid,
      channels: const [],
      issues: issues,
      contentHash: contentHash,
      inputBytes: inputBytes,
      truncated: truncated,
    );
  }

  final channels = <ParsedChannel>[
    for (final key in order)
      if (rows[key] != null && rows[key]!.urls.isNotEmpty)
        ParsedChannel(
          providerChannelId: rows[key]!.providerChannelId,
          displayName: rows[key]!.displayName,
          streamUrls: List<String>.unmodifiable(rows[key]!.urls),
          line: rows[key]!.number,
          logoUrl: rows[key]!.logoUrl,
          group: rows[key]!.group,
          countryCode: rows[key]!.countryCode,
          languages: rows[key]!.languages,
          tvgId: rows[key]!.tvgId,
        ),
  ];

  return PlaylistParseResult(
    format: order.isEmpty ? PlaylistFormat.empty : PlaylistFormat.m3uChannelList,
    channels: channels,
    issues: issues,
    contentHash: contentHash,
    inputBytes: inputBytes,
    truncated: truncated,
  );
}

/// Parses [text] off the UI isolate through the same parsePlaylist.
///
/// `compute` needs a top-level function and one sendable argument, hence the map. Both entry points
/// must agree exactly — a remote refresh that answered differently from a cached re-parse would
/// change the catalog with no user action to explain it.
Future<PlaylistParseResult> parsePlaylistAsync({
  required String playlistId,
  required String text,
  Uri? baseUri,
}) {
  return compute(
    _parsePlaylistOffIsolate,
    <String, Object?>{
      'playlistId': playlistId,
      'text': text,
      'baseUri': baseUri?.toString() ?? '',
    },
  );
}

PlaylistParseResult _parsePlaylistOffIsolate(Map<String, Object?> args) {
  final base = args['baseUri'] as String;
  return parsePlaylist(
    playlistId: args['playlistId']! as String,
    text: args['text']! as String,
    baseUri: base.isEmpty ? null : Uri.parse(base),
  );
}

/// Turns one `#EXTINF` [header] row into a draft, recording the issue that made it unusable.
_Row? _rowFrom(
  String header, {
  required int number,
  required List<CatalogIssue> issues,
  required Map<String, int> fallbackOccurrences,
}) {
  // iptv-org puts the display name after the last comma, so the split is on the *last* comma:
  // attributes and names may each contain one, and the name is whatever follows the final one.
  final comma = header.lastIndexOf(',');
  if (comma < 0) {
    issues.add(CatalogIssue(
      code: 'malformedEntry',
      message: 'line $number is an #EXTINF row with no display-name field',
      line: number,
    ));
    return null;
  }
  final name = m3uDisplayName(header.substring(comma + 1));
  if (name.isEmpty) {
    issues.add(CatalogIssue(
      code: 'missingName',
      message: 'line $number is an #EXTINF row whose display name is empty',
      line: number,
    ));
    return null;
  }

  final attributes = _attributesOf(header.substring(0, comma));
  final rawId = attributes['tvg-id'] ?? '';
  final logo = attributes['tvg-logo'];
  final group = attributes['group-title'];

  // Exactly the existing parser's rule: a trailing `@quality` marker is not identity, and the last
  // dotted suffix is the country rather than part of the station name.
  var base = rawId;
  final at = base.indexOf('@');
  if (at >= 0) base = base.substring(0, at);
  String? countryCode;
  final dot = base.lastIndexOf('.');
  if (dot >= 0) {
    countryCode = base.substring(dot + 1).toUpperCase();
    base = base.substring(0, dot);
  }

  String providerChannelId;
  if (base.isNotEmpty) {
    providerChannelId = base;
  } else {
    // Identity rule 2. The occurrence index is what keeps two unnamed rows apart; without it they
    // collapse into one channel and one of the user's streams silently vanishes.
    final tuple = '${liveNameKey(name)}|${countryCode ?? ''}|${group ?? ''}|${logo ?? ''}';
    final occurrence = fallbackOccurrences[tuple] ?? 0;
    fallbackOccurrences[tuple] = occurrence + 1;
    providerChannelId = 'fallback:$tuple|$occurrence';
  }

  final languages = <String>[
    for (final part in (attributes['tvg-language'] ?? '').split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  return _Row(
    key: providerChannelId,
    providerChannelId: providerChannelId,
    displayName: name,
    number: number,
    logoUrl: logo,
    group: group,
    countryCode: countryCode,
    languages: languages,
    // The unstripped attribute survives so a later identity review can see `@SD` and `.ir`.
    tvgId: rawId.isEmpty ? null : rawId,
  );
}

Map<String, String> _attributesOf(String header) {
  final result = <String, String>{};
  for (final name in const [
    'tvg-id',
    'tvg-logo',
    'group-title',
    'tvg-language',
  ]) {
    final match = RegExp('${RegExp.escape(name)}="([^"]*)"').firstMatch(header);
    final value = match?.group(1)?.trim();
    if (value != null && value.isNotEmpty) result[name] = value;
  }
  return result;
}

String? _canonicalAddress(
  String raw,
  int line,
  Uri? baseUri,
  List<CatalogIssue> issues,
) {
  final parsed = Uri.tryParse(raw);
  Uri? candidate;
  if (parsed != null && parsed.hasScheme) {
    candidate = parsed;
  } else if (baseUri != null && streamSchemes.contains(baseUri.scheme.toLowerCase())) {
    candidate = baseUri.resolve(raw);
  }
  if (candidate == null) {
    issues.add(CatalogIssue(
      code: 'invalidUrl',
      message: 'stream address on line $line is not absolute and no HTTP(S) base was supplied',
      line: line,
    ));
    return null;
  }
  final canonical = canonicalStreamUrl(candidate.toString());
  if (canonical == null) {
    issues.add(CatalogIssue(
      code: 'invalidUrl',
      message: 'stream address on line $line is not an HTTP(S) address this build can play',
      line: line,
    ));
    return null;
  }
  return canonical;
}

/// Reduces a stream address to the form identity is computed from, or `null` if it is unusable.
///
/// Only the scheme and host fold to lowercase; path and query keep their case, because CDN paths
/// are case-sensitive and lowercasing one would silently point two different manifests at one
/// `sourceId`. Default ports are dropped for the same reason: `:443` and no port are the same
/// origin, and keeping both spellings would double every source list.
///
/// A fragment is refused rather than stripped. Stripping would make `a.m3u8#1` and `a.m3u8#2` the
/// same source while the playlist presented them as two rows — a merge nobody asked for, which
/// `identityCollision` is the place to surface. Userinfo is refused for the same class of reason:
/// it is a credential, not part of an address.
String? canonicalStreamUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (!streamSchemes.contains(scheme)) return null;
  if (uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (uri.hasFragment) return null;
  if (uri.path.isEmpty || uri.path == '/') return null;

  final buffer = StringBuffer('$scheme://${uri.host.toLowerCase()}');
  if (uri.hasPort) {
    final defaultPort = scheme == 'http' ? 80 : 443;
    if (uri.port != defaultPort) buffer.write(':${uri.port}');
  }
  buffer.write(uri.path);
  if (uri.query.isNotEmpty) buffer.write('?${uri.query}');
  return buffer.toString();
}

/// True when [rawUrl] carries a credential that must never be persisted as plaintext.
///
/// Detection is on exact query *keys*, case-insensitively, rather than on substring matches: a
/// substring test flags `/monkey.m3u8` and drops a legitimate channel, which is worse than the leak
/// it tries to prevent. A signed URL is not rejected here — the registry rejects it, because only
/// the registry knows whether this platform has a secret store.
bool isSensitiveUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return false;
  if (uri.userInfo.isNotEmpty) return true;
  for (final pair in uri.query.split('&')) {
    if (pair.isEmpty) continue;
    final equals = pair.indexOf('=');
    final key = (equals < 0 ? pair : pair.substring(0, equals)).trim().toLowerCase();
    if (sensitiveQueryKeys.contains(key)) return true;
  }
  return false;
}

/// Protocol hint from the canonical path extension only.
///
/// The query is ignored deliberately: `c.MP4?x=M3U8` is an mp4 file whose query merely mentions a
/// manifest. A hint never claims the renderer can play the stream — only `SourceHealth` and
/// `rendererCapability` carry evidence, and both start unverified.
String protocolHintFor(String canonicalUrl) {
  final path = Uri.tryParse(canonicalUrl)?.path.toLowerCase() ?? '';
  if (path.endsWith('.m3u8')) return 'hls';
  if (path.endsWith('.mpd')) return 'dash';
  if (path.endsWith('.mp4')) return 'mp4';
  return 'unknown';
}

String _firstLine(String text) {
  final end = text.indexOf('\n');
  final line = end < 0 ? text : text.substring(0, end);
  return line.replaceFirst('\r', '').trim();
}
