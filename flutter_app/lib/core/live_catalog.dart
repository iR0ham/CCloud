import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'live_tv_client.dart';
import 'models.dart';

// MARK: - Merged live catalogue
//
// Famelack's Iran file is the whole «ایران» list: every channel with its
// streams, languages and geo-block flag. iptv-org's Iran and Persian playlists
// only back those rows up with extra stream URLs; the channels only it knows
// about are mostly diaspora or dead links, so they never reach the list.

/// One channel from an iptv-org playlist, with every URL that shares its id.
class M3uEntry {
  M3uEntry({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.group,
    required this.streams,
  });

  final String id;
  final String name;
  final String countryCode;
  final String group;
  final List<String> streams;
}

/// Normalised channel name used to match the two datasets.
///
/// The two spell the same channel differently ("Press TV (720p)" vs
/// "Press TV"), so matching folds diacritics and width, lowercases, maps the
/// Arabic/Persian letter variants, turns Persian digits into ASCII, drops
/// punctuation and collapses spaces.
String liveNameKey(String name) {
  final buffer = StringBuffer();
  for (final rune in name.runes) {
    var value = rune;
    // Width fold (fullwidth ASCII and the ideographic space).
    if (value >= 0xFF01 && value <= 0xFF5E) {
      value -= 0xFEE0;
    } else if (value == 0x3000) {
      value = 0x20;
    }
    // Diacritics: Latin combining marks and Arabic harakat/tajweed marks.
    if ((value >= 0x0300 && value <= 0x036F) ||
        (value >= 0x0610 && value <= 0x061A) ||
        (value >= 0x064B && value <= 0x065F) ||
        value == 0x0670 ||
        (value >= 0x06D6 && value <= 0x06ED)) {
      continue;
    }
    switch (value) {
      case 0x064A: // ي
      case 0x0626: // ئ
      case 0x0649: // ى
        value = 0x06CC; // ی
      case 0x0643: // ك
        value = 0x06A9; // ک
      case 0x0629: // ة
        value = 0x0647; // ه
      case 0x0622: // آ
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0671: // ٱ
        value = 0x0627; // ا
      case 0x0624: // ؤ
        value = 0x0648; // و
      case 0x200C: // ZWNJ
      case 0x200D: // ZWJ
      case 0x00A0: // NBSP
        value = 0x20;
      default:
        if (value >= 0x06F0 && value <= 0x06F9) {
          value = 0x0030 + value - 0x06F0;
        } else if (value >= 0x0660 && value <= 0x0669) {
          value = 0x0030 + value - 0x0660;
        }
    }
    buffer.writeCharCode(value);
  }

  final cleaned = buffer.toString().toLowerCase();
  final key = StringBuffer();
  var pendingSpace = false;
  for (final rune in cleaned.runes) {
    final kept =
        (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0x0600 && rune <= 0x06FF);
    if (kept) {
      if (pendingSpace && key.isNotEmpty) key.write(' ');
      key.writeCharCode(rune);
      pendingSpace = false;
    } else {
      pendingSpace = true;
    }
  }
  return key.toString();
}

/// iptv-org appends the stream quality to the channel name; the row shows the
/// name only: `Press TV (720p)` → `Press TV`.
String m3uDisplayName(String raw) {
  final result = StringBuffer();
  var index = 0;
  while (index < raw.length) {
    final character = raw[index];
    if (character == '(' || character == '[') {
      final closer = character == '(' ? ')' : ']';
      final end = raw.indexOf(closer, index + 1);
      if (end >= 0 && _isNoiseToken(raw.substring(index + 1, end))) {
        index = end + 1;
        continue;
      }
    }
    result.write(character);
    index++;
  }
  return result
      .toString()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
}

bool _isNoiseToken(String inner) {
  final token = inner.toLowerCase().replaceAll(' ', '');
  if (token.isEmpty) return true;
  const noise = {
    '4k',
    '8k',
    'sd',
    'hd',
    'fhd',
    'uhd',
    'hevc',
    'multiaudio',
    'backup',
  };
  if (noise.contains(token)) return true;
  if (token.startsWith('not')) return true;
  return RegExp(r'^\d{1,4}[kpi]\d*$').hasMatch(token);
}

/// Parses an extended M3U playlist. A `tvg-id` may carry several URLs (quality
/// variants); they are merged into one entry in first-seen order.
List<M3uEntry> parseM3u(String text) {
  final order = <String>[];
  final entries = <String, M3uEntry>{};
  M3uEntry? pending;

  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.startsWith('#EXTINF:')) {
      pending = _entryFrom(line);
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;
    final entry = pending;
    if (entry == null) continue;
    pending = null;
    if (!entry.streams.contains(line)) entry.streams.add(line);
    if (!entries.containsKey(entry.id)) order.add(entry.id);
    entries[entry.id] = entry;
  }

  return [
    for (final id in order)
      if (entries[id] != null && entries[id]!.streams.isNotEmpty) entries[id]!,
  ];
}

M3uEntry? _entryFrom(String line) {
  final comma = line.lastIndexOf(',');
  if (comma < 0) return null;
  final name = m3uDisplayName(line.substring(comma + 1));
  if (name.isEmpty) return null;

  var base = _attribute('tvg-id', line);
  final at = base.indexOf('@');
  if (at >= 0) base = base.substring(0, at);
  var countryCode = '';
  final dot = base.lastIndexOf('.');
  if (dot >= 0) {
    countryCode = base.substring(dot + 1).toUpperCase();
    base = base.substring(0, dot);
  }
  final id = base.isEmpty ? 'name:${liveNameKey(name)}' : base;
  return M3uEntry(
    id: id,
    name: name,
    countryCode: countryCode,
    group: _attribute('group-title', line),
    streams: [],
  );
}

String _attribute(String name, String line) {
  final match = RegExp('${RegExp.escape(name)}="([^"]*)"').firstMatch(line);
  return match?.group(1) ?? '';
}

class _MergedGroup {
  _MergedGroup(this.entry, this.countryCode, this.languages, this.streams);

  final M3uEntry entry;
  String countryCode;
  final List<String> languages;
  final List<String> streams;
}

/// Adds iptv-org's extra URLs to famelack's rows. iptv-org never adds a
/// channel, and URLs are compared case-insensitively.
List<LiveTvChannel> mergeIranChannels({
  required List<LiveTvChannel> famelack,
  required List<M3uEntry> byCountry,
  required List<M3uEntry> byLanguage,
}) {
  final groups = <String, _MergedGroup>{};
  final playlist = <(M3uEntry, String?)>[
    for (final entry in byCountry) (entry, null),
    for (final entry in byLanguage) (entry, 'fas'),
  ];

  for (final (entry, language) in playlist) {
    final key = liveNameKey(entry.name);
    if (key.isEmpty || entry.streams.isEmpty) continue;
    final existing = groups[key];
    if (existing != null) {
      if (existing.countryCode.isEmpty) {
        existing.countryCode = entry.countryCode;
      }
      if (language != null && !existing.languages.contains(language)) {
        existing.languages.add(language);
      }
      for (final url in entry.streams) {
        if (!existing.streams.any(
          (current) => current.toLowerCase() == url.toLowerCase(),
        )) {
          existing.streams.add(url);
        }
      }
    } else {
      groups[key] = _MergedGroup(entry, entry.countryCode, [
        ?language,
      ], List<String>.of(entry.streams));
    }
  }

  final merged = <LiveTvChannel>[];
  for (final channel in famelack) {
    final key = liveNameKey(channel.name);
    final group = key.isEmpty ? null : groups[key];
    if (group == null) {
      merged.add(channel);
      continue;
    }
    final extra = <String>[
      for (final url in group.streams)
        if (!channel.streams.any(
          (current) => current.toLowerCase() == url.toLowerCase(),
        ))
          url,
    ];
    merged.add(
      extra.isEmpty
          ? channel
          : channel.copyWithStreams([...channel.streams, ...extra]),
    );
  }
  merged.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return merged;
}

// MARK: - Catalogue

class _PlaylistCache {
  _PlaylistCache(this.entries, this.at);

  final List<M3uEntry> entries;
  final DateTime at;
}

class LiveCatalog {
  LiveCatalog._();

  static final LiveCatalog instance = LiveCatalog._();

  static const List<String> _bases = [
    'https://iptv-org.github.io/iptv',
    'https://cdn.jsdelivr.net/gh/iptv-org/iptv@gh-pages',
  ];

  static const Duration _playlistTtl = Duration(minutes: 15);

  final http.Client _client = http.Client();
  final LiveTvClient _famelack = LiveTvClient.instance;
  final Map<String, _PlaylistCache> _playlists = {};
  final Map<String, Future<List<M3uEntry>>> _playlistInFlight = {};

  List<LiveTvChannel>? _iranCache;
  Future<List<LiveTvChannel>>? _iranInFlight;

  Future<List<LiveTvCountry>> countries({bool force = false}) =>
      _famelack.countries(force: force);

  /// Iran is merged with iptv-org's backup URLs; every other country is the
  /// Famelack list unchanged.
  Future<List<LiveTvChannel>> channels(
    LiveTvCountry country, {
    bool force = false,
  }) async {
    if (country.code.toUpperCase() != 'IR') {
      return _famelack.channels(country.code, force: force);
    }
    if (!force) {
      final cached = _iranCache;
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final running = _iranInFlight;
    if (running != null) return running;

    final future = _loadIran();
    _iranInFlight = future;
    try {
      final channels = await future;
      _iranCache = channels;
      return channels;
    } finally {
      _iranInFlight = null;
    }
  }

  void clearCache() {
    _iranCache = null;
    _iranInFlight = null;
    _playlists.clear();
    _playlistInFlight.clear();
    _famelack.clearCache();
  }

  Future<List<LiveTvChannel>> _loadIran() async {
    // Three independent sources; one failure must not drop the list.
    final results = await Future.wait<Object>([
      _orEmpty<List<LiveTvChannel>>(_famelack.channels('IR'), const []),
      _orEmpty<List<M3uEntry>>(playlist('/countries/ir.m3u'), const []),
      _orEmpty<List<M3uEntry>>(playlist('/languages/fas.m3u'), const []),
    ]);
    final channels = mergeIranChannels(
      famelack: results[0] as List<LiveTvChannel>,
      byCountry: results[1] as List<M3uEntry>,
      byLanguage: results[2] as List<M3uEntry>,
    );
    if (channels.isEmpty) {
      throw const ApiException('محتوایی برای نمایش پیدا نشد (live channels)');
    }
    return channels;
  }

  Future<T> _orEmpty<T>(Future<T> future, T fallback) async {
    try {
      return await future;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<M3uEntry>> playlist(String path) {
    final cached = _playlists[path];
    if (cached != null && DateTime.now().difference(cached.at) < _playlistTtl) {
      return Future.value(cached.entries);
    }
    final running = _playlistInFlight[path];
    if (running != null) return running;

    final future = _loadPlaylist(path);
    _playlistInFlight[path] = future;
    return future
        .then((entries) {
          _playlists[path] = _PlaylistCache(entries, DateTime.now());
          return entries;
        })
        .whenComplete(() => _playlistInFlight.remove(path));
  }

  Future<List<M3uEntry>> _loadPlaylist(String path) async {
    Object? lastError;
    for (final base in _bases) {
      try {
        final response = await _client
            .get(
              Uri.parse('$base$path'),
              headers: {
                'Accept': 'audio/x-mpegurl',
                'User-Agent': ApiClient.userAgent,
              },
            )
            .timeout(const Duration(seconds: 25));
        if (response.statusCode == 404) {
          lastError = const ApiException('محتوایی برای نمایش پیدا نشد (live)');
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastError = ApiException('خطای سرور (کد ${response.statusCode})');
          continue;
        }
        final text = utf8.decode(response.bodyBytes, allowMalformed: true);
        final entries = parseM3u(text);
        if (entries.isEmpty) {
          throw const ApiException(
            'محتوایی برای نمایش پیدا نشد (live channels)',
          );
        }
        return entries;
      } catch (error) {
        lastError = error is ApiException
            ? error
            : const ApiException('اتصال به سرور پخش زنده برقرار نشد');
      }
    }
    throw lastError is ApiException
        ? lastError
        : const ApiException('اتصال به سرور پخش زنده برقرار نشد');
  }
}
