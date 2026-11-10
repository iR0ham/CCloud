import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Persian, user-facing API failure.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CacheEntry {
  _CacheEntry(this.data, this.storedAt);

  final List<Map<String, dynamic>> data;
  final DateTime storedAt;
}

/// HTTP client for the CCloud backend.
///
/// Mirrors the macOS client:
/// * three interchangeable hosts, tried in fallback order; the last good host is kept,
/// * the server labels JSON as `text/html`, so the body is always decoded as UTF-8 bytes,
/// * 75 s in-memory cache and in-flight de-duplication,
/// * `page` is 0-based and paths keep their trailing slash.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  static const String apiKey = '4F5A9C3D9A86FA54EACEDDD635185';
  static const List<String> hosts = [
    'server-hi-speed-iran.info',
    'hostinnegar.com',
    'windowsdiba.info',
  ];

  static const Duration _cacheTtl = Duration(seconds: 75);
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _overallTimeout = Duration(seconds: 90);
  static const int maxSearchLength = 120;

  static const Set<String> _knownHosts = {
    'server-hi-speed-iran.info',
    'www.server-hi-speed-iran.info',
    'hostinnegar.com',
    'www.hostinnegar.com',
    'windowsdiba.info',
    'www.windowsdiba.info',
  };

  final http.Client _client = http.Client();
  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<List<Map<String, dynamic>>>> _inFlight = {};
  final List<void Function(String host)> _hostListeners = [];

  int _preferredIndex = 0;
  String _activeHost = hosts.first;

  String get activeHost => _activeHost;

  void addHostListener(void Function(String host) listener) =>
      _hostListeners.add(listener);

  // MARK: - Endpoints

  Future<List<Genre>> genres() async {
    final items = await _fetch('/api/genre/all/$apiKey/');
    return _dedupe(items.map(Genre.fromJson), (g) => '${g.id}');
  }

  Future<List<MediaItem>> movies({
    required int page,
    int genreId = 0,
    SortOption sort = SortOption.newest,
  }) async {
    final items = await _fetch(
      '/api/movie/by/filtres/$genreId/${sort.apiPath}/${page < 0 ? 0 : page}/$apiKey/',
    );
    return _dedupe(
      items.map(MediaItem.fromJson),
      (m) => '${m.type.toLowerCase()}:${m.id}',
    );
  }

  Future<List<MediaItem>> series({
    required int page,
    int genreId = 0,
    SortOption sort = SortOption.newest,
  }) async {
    final items = await _fetch(
      '/api/serie/by/filtres/$genreId/${sort.apiPath}/${page < 0 ? 0 : page}/$apiKey/',
    );
    return _dedupe(
      items.map(MediaItem.fromJson),
      (m) => '${m.type.toLowerCase()}:${m.id}',
    );
  }

  Future<List<Season>> seasons(int seriesId) async {
    if (seriesId <= 0) throw const ApiException('شناسه سریال نامعتبر');
    final items = await _fetch('/api/season/by/serie/$seriesId/$apiKey/');
    return _dedupe(items.map(Season.fromJson), (s) => '${s.id}');
  }

  Future<List<MediaItem>> search(String query) async {
    final normalized = normalizeSearchQuery(query);
    if (normalized.isEmpty) return const [];
    final encoded = Uri.encodeComponent(normalized);
    final items = await _fetch('/api/search/$encoded/$apiKey/');
    return _dedupe(
      items.map(MediaItem.fromJson),
      (m) => '${m.type.toLowerCase()}:${m.id}',
    );
  }

  Future<List<Country>> countries() async {
    final items = await _fetch('/api/country/all/$apiKey/');
    return _dedupe(items.map(Country.fromJson), (c) => '${c.id}');
  }

  Future<List<MediaItem>> countryPosters({
    required int countryId,
    required int page,
    SortOption sort = SortOption.newest,
  }) async {
    if (countryId <= 0) throw const ApiException('شناسه کشور نامعتبر');
    final items = await _fetch(
      '/api/poster/by/filtres/0/$countryId/${sort.apiPath}/${page < 0 ? 0 : page}/$apiKey/',
    );
    return _dedupe(
      items.map(MediaItem.fromJson),
      (m) => '${m.type.toLowerCase()}:${m.id}',
    );
  }

  Future<bool> healthCheck() async {
    try {
      final items = await _fetch('/api/genre/all/$apiKey/', allowCache: false);
      return items.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Resolve a poster/cover/country-image field into a usable URL.
  String? imageUrl(String path) {
    var raw = path.trim();
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower == 'null' || lower == 'n/a') return null;
    raw = raw.replaceAll(r'\/', '/').replaceAll('\r', '').replaceAll('\n', '');
    if (raw.startsWith('//')) {
      raw = 'https:$raw';
    } else if (raw.startsWith('/')) {
      raw = 'https://$_activeHost$raw';
    } else if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      raw = 'https://$_activeHost/$raw';
    }
    final uri = Uri.tryParse(raw.replaceAll(' ', '%20'));
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    if (_knownHosts.contains(uri.host.toLowerCase())) {
      return uri.replace(host: _activeHost, scheme: 'https').toString();
    }
    return uri.toString();
  }

  // MARK: - Fetch pipeline

  Future<List<Map<String, dynamic>>> _fetch(String path, {bool allowCache = true}) {
    if (allowCache) {
      final cached = _cache[path];
      if (cached != null &&
          DateTime.now().difference(cached.storedAt) <= _cacheTtl) {
        return Future.value(cached.data);
      }
    }
    final running = _inFlight[path];
    if (running != null) return running;

    final future = _perform(path);
    _inFlight[path] = future;
    return future.then((data) {
      if (data.length <= 4000) {
        _cache[path] = _CacheEntry(data, DateTime.now());
        if (_cache.length > 64) {
          String? oldestKey;
          DateTime? oldestAt;
          _cache.forEach((key, value) {
            if (oldestAt == null || value.storedAt.isBefore(oldestAt!)) {
              oldestAt = value.storedAt;
              oldestKey = key;
            }
          });
          if (oldestKey != null) _cache.remove(oldestKey);
        }
      }
      return data;
    }).whenComplete(() {
      _inFlight.remove(path);
    });
  }

  Future<List<Map<String, dynamic>>> _perform(String path) async {
    final deadline = DateTime.now().add(_overallTimeout);
    final retryHosts = <int>[];
    ApiException? lastTransient;
    ApiException? lastPermanent;

    for (var pass = 0; pass < 2; pass++) {
      if (pass == 1) {
        if (retryHosts.isEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      final order = pass == 0
          ? List<int>.generate(hosts.length, (i) => (i + _preferredIndex) % hosts.length)
          : retryHosts;

      for (final index in order) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining.inSeconds < 1) break;
        final timeout = remaining < _requestTimeout ? remaining : _requestTimeout;

        try {
          final data = await _fetchOnce(hosts[index], path, timeout);
          _noteSuccess(index);
          return data;
        } on _TransientFailure catch (failure) {
          lastTransient = failure.error;
          if (pass == 0 && !retryHosts.contains(index)) retryHosts.add(index);
        } on _PermanentFailure catch (failure) {
          lastPermanent = failure.error;
        }
      }
    }

    if (lastPermanent != null) throw lastPermanent;
    if (lastTransient != null) throw lastTransient;
    throw const ApiException('اتصال به سرور برقرار نشد');
  }

  Future<List<Map<String, dynamic>>> _fetchOnce(
    String host,
    String path,
    Duration timeout,
  ) async {
    final uri = Uri.parse('https://$host$path');
    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
          'User-Agent': 'CCloudAndroid/1.0 (Android)',
        },
      ).timeout(timeout);
    } on TimeoutException {
      throw const _TransientFailure(ApiException('پاسخ سرور دیر رسید'));
    } on SocketException {
      throw const _TransientFailure(ApiException('اتصال به سرور برقرار نشد'));
    } on http.ClientException {
      throw const _TransientFailure(ApiException('خطای شبکه'));
    }

    final status = response.statusCode;
    if (status == 408 || status == 429 || status >= 500) {
      throw _TransientFailure(ApiException('خطای سرور (کد $status)'));
    }
    if (status < 200 || status >= 300) {
      throw _PermanentFailure(ApiException('خطای سرور (کد $status)'));
    }
    if (response.bodyBytes.isEmpty) {
      throw const _TransientFailure(ApiException('پاسخ خالی از سرور'));
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final trimmed = text.replaceFirst('\uFEFF', '').trimLeft();
    if (trimmed.isEmpty) {
      throw const _TransientFailure(ApiException('پاسخ خالی از سرور'));
    }
    if (trimmed.startsWith('<')) {
      // HTML error page served with a 2xx status.
      throw const _TransientFailure(ApiException('خطای سرور (کد 502)'));
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw const ApiException('داده‌های دریافتی نامعتبر بود');
    }

    final List<dynamic>? list = _extractList(decoded);
    if (list == null) {
      throw const ApiException('ساختار پاسخ نامعتبر');
    }
    return list
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  List<dynamic>? _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in ['posters', 'data', 'items', 'results']) {
        final value = decoded[key];
        if (value is List) return value;
      }
    }
    return null;
  }

  void _noteSuccess(int index) {
    _preferredIndex = index;
    final host = hosts[index];
    if (host != _activeHost) {
      _activeHost = host;
      for (final listener in _hostListeners) {
        listener(host);
      }
    }
  }

  void invalidateCache() => _cache.clear();

  // MARK: - Helpers

  static List<T> _dedupe<T>(Iterable<T> items, String Function(T item) key) {
    final seen = <String>{};
    final result = <T>[];
    for (final item in items) {
      if (seen.add(key(item))) result.add(item);
    }
    return result;
  }

  /// Arabic ي/ك → Persian ی/ک, strip bidi marks, slashes → space, collapse spaces.
  static String normalizeSearchQuery(String raw) {
    var text = raw
        .replaceAll('\u064A', '\u06CC')
        .replaceAll('\u0643', '\u06A9')
        .replaceAll('\u200E', '')
        .replaceAll('\u200F', '')
        .replaceAll('/', ' ')
        .replaceAll('\\', ' ')
        .replaceAll('\u0000', '');
    text = text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).join(' ');
    if (text.length > maxSearchLength) {
      text = text.substring(0, maxSearchLength);
    }
    return text;
  }
}

class _TransientFailure implements Exception {
  const _TransientFailure(this.error);

  final ApiException error;
}

class _PermanentFailure implements Exception {
  const _PermanentFailure(this.error);

  final ApiException error;
}
