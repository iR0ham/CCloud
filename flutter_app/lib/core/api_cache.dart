import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Shared size ceiling for one cached payload, mirroring the macOS
/// `APIClient.maxCacheEntryBytes` (4 MiB).
const int apiCacheEntryLimitBytes = 4 * 1024 * 1024;

class ApiCacheEntry {
  ApiCacheEntry(this.data, this.storedAt);

  final List<Map<String, dynamic>> data;
  final DateTime storedAt;
}

/// Short-lived per-path list cache, mirroring the macOS `APIClient` memory
/// cache: 75 seconds is fresh, at most 64 entries, oldest entry evicted first.
class ApiMemoryCache {
  ApiMemoryCache({
    this.ttl = const Duration(seconds: 75),
    this.maxEntries = 64,
    this.maxEntryBytes = apiCacheEntryLimitBytes,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final int maxEntryBytes;
  final DateTime Function() _clock;
  final Map<String, ApiCacheEntry> _entries = {};

  int get length => _entries.length;

  List<Map<String, dynamic>>? read(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (_clock().difference(entry.storedAt) <= ttl) return entry.data;
    _entries.remove(key);
    return null;
  }

  void write(String key, List<Map<String, dynamic>> data) {
    if (utf8.encode(jsonEncode(data)).length > maxEntryBytes) return;
    _entries[key] = ApiCacheEntry(data, _clock());
    while (_entries.length > maxEntries) {
      String? oldestKey;
      DateTime? oldestAt;
      _entries.forEach((key, value) {
        if (oldestAt == null || value.storedAt.isBefore(oldestAt!)) {
          oldestAt = value.storedAt;
          oldestKey = key;
        }
      });
      if (oldestKey == null) break;
      _entries.remove(oldestKey);
    }
  }

  void clear() => _entries.clear();
}

/// On-disk copy of the last successful payload per API path.
///
/// The file name is the SHA-256 (hex) of the path plus `.json`, so query-string
/// variants and long search URLs stay distinct and filesystem-safe. Missing
/// network + an existing copy gives the app something to show in offline mode.
class OfflineCache {
  OfflineCache(
    this.directory, {
    this.maxEntries = 240,
    this.maxEntryBytes = apiCacheEntryLimitBytes,
  });

  final Directory directory;
  final int maxEntries;
  final int maxEntryBytes;

  /// Uses the app support directory, like the macOS `offline-cache` folder.
  static Future<OfflineCache> open() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}offline-cache',
    );
    await directory.create(recursive: true);
    return OfflineCache(directory);
  }

  static String fileNameFor(String path) {
    final digest = sha256.convert(utf8.encode(path));
    return '${digest.toString()}.json';
  }

  File fileFor(String path) =>
      File('${directory.path}${Platform.pathSeparator}${fileNameFor(path)}');

  /// Reads a stored payload; null when there is none or it cannot be read.
  Future<List<int>?> read(String path) async {
    try {
      final bytes = await fileFor(path).readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// Writes [bytes] atomically and prunes the oldest files beyond [maxEntries].
  /// Oversized payloads are ignored, matching the macOS disk fallback.
  Future<void> store(String path, List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxEntryBytes) return;
    final file = fileFor(path);
    try {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      await prune();
    } catch (_) {
      // The disk copy is best effort: a read-only folder must not fail the
      // request that already succeeded on the network.
    }
  }

  /// Keeps the [maxEntries] newest files (by modification time).
  Future<void> prune() async {
    final List<File> files;
    try {
      final entries = await directory.list(followLinks: false).toList();
      files = [
        for (final entry in entries)
          if (entry is File && entry.path.endsWith('.json')) entry,
      ];
    } catch (_) {
      return;
    }
    if (files.length <= maxEntries) return;

    final dated = <({File file, DateTime at})>[];
    for (final file in files) {
      DateTime at;
      try {
        at = await file.lastModified();
      } catch (_) {
        at = DateTime.fromMillisecondsSinceEpoch(0);
      }
      dated.add((file: file, at: at));
    }
    dated.sort((a, b) => a.at.compareTo(b.at));
    for (final entry in dated.take(dated.length - maxEntries)) {
      try {
        await entry.file.delete();
      } catch (_) {}
    }
  }
}
