import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// URL key used by link health: the address without query and fragment.
///
/// Mirrors the macOS `LinkHealth.key(for:)` behaviour: signed tokens and
/// redirect parameters must not create separate history records for the same
/// stream path.
String linkHealthKey(String url) {
  var end = url.length;
  final query = url.indexOf('?');
  final fragment = url.indexOf('#');
  if (query >= 0) end = query;
  if (fragment >= 0 && fragment < end) end = fragment;
  return url.substring(0, end);
}

/// Health record for a single stream URL.
@immutable
class LinkHealthRecord {
  const LinkHealthRecord({required this.failures, required this.lastFailure});

  final int failures;
  final DateTime lastFailure;

  LinkHealthRecord afterFailure(DateTime at) =>
      LinkHealthRecord(failures: failures + 1, lastFailure: at);

  Map<String, dynamic> toJson() => {
    'failures': failures,
    'lastFailure': lastFailure.toIso8601String(),
  };

  static LinkHealthRecord? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final failures = (raw['failures'] as num?)?.toInt() ?? 0;
    final lastFailure = DateTime.tryParse(raw['lastFailure']?.toString() ?? '');
    if (failures <= 0 || lastFailure == null) return null;
    return LinkHealthRecord(failures: failures, lastFailure: lastFailure);
  }
}

/// Remembers which stream links failed repeatedly so that the player can try
/// them last instead of wasting time on them.
///
/// Contract (matching the macOS app):
///  * two failures deprioritise a link;
///  * records expire after seven days;
///  * at most 300 records are kept, newest failure wins;
///  * a successful playback removes the record.
class LinkHealthStore extends ChangeNotifier {
  LinkHealthStore(this._prefs, {DateTime Function()? clock, DateTime? now})
    : _clock = clock ?? DateTime.now {
    _load(now ?? _clock());
  }

  static const String storageKey = 'ccloud.linkHealth';
  static const Duration ttl = Duration(days: 7);
  static const int maxEntries = 300;
  static const int failuresBeforeDeprioritised = 2;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final Map<String, LinkHealthRecord> _records = {};

  DateTime get _now => _clock();

  int failureCount(String url) => _records[linkHealthKey(url)]?.failures ?? 0;

  bool isDeprioritised(String url) =>
      failureCount(url) >= failuresBeforeDeprioritised;

  /// True only when every stream of [urls] is known to fail twice.
  bool areAllDeprioritised(Iterable<String> urls) {
    final list = urls.toList();
    return list.isNotEmpty && list.every(isDeprioritised);
  }

  Future<void> recordFailure(String url, {DateTime? at}) async {
    final key = linkHealthKey(url);
    if (key.isEmpty) return;
    final moment = at ?? _now;
    final previous = _records[key];
    _records[key] = previous == null
        ? LinkHealthRecord(failures: 1, lastFailure: moment)
        : previous.afterFailure(moment);
    _prune(moment);
    notifyListeners();
    await _save();
  }

  Future<void> recordSuccess(String url) async {
    final key = linkHealthKey(url);
    if (_records.remove(key) == null) return;
    notifyListeners();
    await _save();
  }

  void _load(DateTime now) {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        final record = LinkHealthRecord.fromJson(value);
        if (record != null && !_isExpired(record, now)) {
          _records[key.toString()] = record;
        }
      });
    } catch (_) {
      // Corrupt payload: start from a clean slate rather than crashing.
    }
    _prune(now);
  }

  Future<void> _save() async {
    final payload = <String, dynamic>{
      for (final entry in _records.entries) entry.key: entry.value.toJson(),
    };
    await _prefs.setString(storageKey, jsonEncode(payload));
  }

  bool _isExpired(LinkHealthRecord record, DateTime now) =>
      now.difference(record.lastFailure) > ttl;

  void _prune(DateTime now) {
    _records.removeWhere((_, record) => _isExpired(record, now));
    if (_records.length <= maxEntries) return;
    final ordered = _records.entries.toList()
      ..sort((a, b) => b.value.lastFailure.compareTo(a.value.lastFailure));
    final keep = ordered.take(maxEntries).map((e) => e.key).toSet();
    _records.removeWhere((key, _) => !keep.contains(key));
  }
}
