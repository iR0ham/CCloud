import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models.dart';

/// Live channel data (Famelack dataset): countries metadata → per-country channel list.
class LiveTvClient {
  LiveTvClient._();

  static final LiveTvClient instance = LiveTvClient._();

  static const List<String> _bases = [
    'https://raw.githubusercontent.com/famelack/famelack-data/main/tv',
    'https://cdn.jsdelivr.net/gh/famelack/famelack-data@main/tv',
  ];

  final http.Client _client = http.Client();

  List<LiveTvCountry>? _countries;
  DateTime? _countriesAt;
  final Map<String, List<LiveTvChannel>> _channels = {};
  final Map<String, DateTime> _channelsAt = {};
  Future<List<LiveTvCountry>>? _countriesInFlight;
  final Map<String, Future<List<LiveTvChannel>>> _channelsInFlight = {};

  static const Duration _countriesTtl = Duration(minutes: 10);
  static const Duration _channelsTtl = Duration(minutes: 5);

  Future<List<LiveTvCountry>> countries({bool force = false}) async {
    if (!force &&
        _countries != null &&
        _countriesAt != null &&
        DateTime.now().difference(_countriesAt!) < _countriesTtl) {
      return _countries!;
    }
    final running = _countriesInFlight;
    if (running != null) return running;

    final future = _loadCountries();
    _countriesInFlight = future;
    try {
      final items = await future;
      _countries = items;
      _countriesAt = DateTime.now();
      return items;
    } finally {
      _countriesInFlight = null;
    }
  }

  Future<List<LiveTvCountry>> _loadCountries() async {
    final data = await _get('/countries_metadata.json');
    final decoded = jsonDecode(data);
    if (decoded is! Map) throw const ApiException('داده‌های پخش زنده نامعتبر بود');

    final items = <LiveTvCountry>[];
    decoded.forEach((code, value) {
      if (value is! Map) return;
      final country = value['country']?.toString() ?? '';
      final hasChannels = value['hasChannels'] == true;
      final rawCount = value['channelCount'];
      final count = rawCount is int ? rawCount : int.tryParse('$rawCount') ?? 0;
      if (!hasChannels || count <= 0 || country.length <= 1) return;
      items.add(LiveTvCountry(
        code: code.toString().toUpperCase(),
        englishName: country,
        channelCount: count,
      ));
    });
    if (items.isEmpty) throw const ApiException('کشوری برای پخش زنده پیدا نشد');
    return sortLiveCountries(items);
  }

  Future<List<LiveTvChannel>> channels(String countryCode, {bool force = false}) async {
    final code = countryCode.toLowerCase();
    final cached = _channels[code];
    final cachedAt = _channelsAt[code];
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _channelsTtl) {
      return cached;
    }
    final running = _channelsInFlight[code];
    if (running != null) return running;

    final future = _loadChannels(code);
    _channelsInFlight[code] = future;
    try {
      final items = await future;
      _channels[code] = items;
      _channelsAt[code] = DateTime.now();
      return items;
    } finally {
      _channelsInFlight.remove(code);
    }
  }

  Future<List<LiveTvChannel>> _loadChannels(String code) async {
    final data = await _get('/countries/$code.json');
    final decoded = jsonDecode(data);
    if (decoded is! List) throw const ApiException('فهرست شبکه‌ها نامعتبر بود');
    final items = decoded
        .whereType<Map>()
        .map((e) => LiveTvChannel.fromJson(e.cast<String, dynamic>()))
        .where((channel) => channel.streams.isNotEmpty)
        .toList();
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (items.isEmpty) throw const ApiException('شبکه‌ای برای این کشور پیدا نشد');
    return items;
  }

  Future<String> _get(String path) async {
    Object? lastError;
    for (final base in _bases) {
      try {
        final response = await _client
            .get(
              Uri.parse('$base$path'),
              headers: const {'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 25));
        if (response.statusCode == 404) {
          lastError = const ApiException('داده‌های پخش زنده روی سرور پیدا نشد');
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastError = ApiException('خطای سرور (کد ${response.statusCode})');
          continue;
        }
        if (response.bodyBytes.isEmpty) {
          lastError = const ApiException('پاسخ خالی از سرور');
          continue;
        }
        return utf8.decode(response.bodyBytes, allowMalformed: true);
      } catch (_) {
        lastError = const ApiException('اتصال به سرور پخش زنده برقرار نشد');
      }
    }
    throw lastError is ApiException
        ? lastError
        : const ApiException('اتصال به سرور پخش زنده برقرار نشد');
  }
}
