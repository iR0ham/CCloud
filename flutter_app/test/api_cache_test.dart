import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccloud/core/api_cache.dart';

void main() {
  group('memory cache', () {
    test('a payload is fresh for 75 seconds and stale afterwards', () {
      var now = DateTime.utc(2026, 11, 21, 12);
      final cache = ApiMemoryCache(clock: () => now);
      final data = [
        {'id': 1},
      ];
      cache.write('/api/genre/all/key/', data);

      now = now.add(const Duration(seconds: 74));
      expect(cache.read('/api/genre/all/key/'), same(data));

      now = now.add(const Duration(seconds: 2));
      expect(cache.read('/api/genre/all/key/'), isNull);
      expect(cache.length, 0);
    });

    test('keeps at most 64 entries, evicting the oldest', () {
      var now = DateTime.utc(2026, 11, 21, 12);
      final cache = ApiMemoryCache(clock: () => now);
      for (var i = 0; i < 70; i++) {
        cache.write('/path/$i', [
          {'i': i},
        ]);
        now = now.add(const Duration(seconds: 1));
      }
      expect(cache.length, 64);
      expect(cache.read('/path/0'), isNull);
      expect(cache.read('/path/5'), isNull);
      expect(cache.read('/path/6'), isNotNull);
      expect(cache.read('/path/69'), isNotNull);
    });

    test('skips a payload larger than four megabytes', () {
      final cache = ApiMemoryCache();
      final big = [
        {'blob': 'x' * (apiCacheEntryLimitBytes + 1)},
      ];
      cache.write('/big', big);
      expect(cache.read('/big'), isNull);
      expect(cache.length, 0);
    });

    test('clear empties everything', () {
      final cache = ApiMemoryCache();
      cache.write('/a', [
        {'id': 1},
      ]);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.read('/a'), isNull);
    });
  });

  group('offline cache', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('ccloud-offline-test');
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('file name is SHA-256 of the path plus .json', () {
      const path = '/api/movie/by/filtres/0/newest/0/key/';
      final expected = '${sha256.convert(utf8.encode(path))}.json';
      expect(OfflineCache.fileNameFor(path), expected);
      expect(RegExp(r'^[0-9a-f]{64}\.json$').hasMatch(expected), isTrue);
      expect(
        OfflineCache.fileNameFor('/api/search/%D8%AF%D8%B1%D8%A7%D9%85%D8%A7/key/'),
        isNot(expected),
      );
    });

    test('stores and reads a payload back', () async {
      final cache = OfflineCache(temp);
      await cache.store('/a', utf8.encode('[{"id":1}]'));
      final bytes = await cache.read('/a');
      expect(bytes, isNotNull);
      expect(utf8.decode(bytes!), '[{"id":1}]');
      expect(await cache.read('/missing'), isNull);
    });

    test('ignores payloads over four megabytes', () async {
      final cache = OfflineCache(temp, maxEntryBytes: 4 * 1024 * 1024);
      await cache.store('/big', List<int>.filled(4 * 1024 * 1024 + 1, 120));
      expect(cache.fileFor('/big').existsSync(), isFalse);
    });

    test('prune keeps only the 240 newest files', () async {
      final cache = OfflineCache(temp);
      final start = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 242; i++) {
        final file = File('${temp.path}/entry-$i.json');
        file.writeAsStringSync('$i');
        file.setLastModifiedSync(start.add(Duration(minutes: i)));
      }

      await cache.prune();

      final remaining = temp
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList();
      expect(remaining.length, 240);
      expect(File('${temp.path}/entry-0.json').existsSync(), isFalse);
      expect(File('${temp.path}/entry-1.json').existsSync(), isFalse);
      expect(File('${temp.path}/entry-2.json').existsSync(), isTrue);
      expect(File('${temp.path}/entry-241.json').existsSync(), isTrue);
    });

    test('storing a new payload prunes past the limit', () async {
      final cache = OfflineCache(temp, maxEntries: 2);
      await cache.store('/one', [1]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cache.store('/two', [2]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cache.store('/three', [3]);
      expect(cache.fileFor('/one').existsSync(), isFalse);
      expect(cache.fileFor('/two').existsSync(), isTrue);
      expect(cache.fileFor('/three').existsSync(), isTrue);
    });
  });
}
