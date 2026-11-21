import 'dart:convert';

import 'package:ccloud/core/link_health.dart';
import 'package:ccloud/core/models.dart';
import 'package:ccloud/core/playback.dart';
import 'package:ccloud/core/stores.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaItem movie({int id = 1, String title = 'Film'}) => MediaItem.fromJson({
  'id': id,
  'type': 'movie',
  'title': title,
  'description': '',
  'year': 2024,
  'imdb': 7.5,
  'rating': 7.5,
  'duration': '120',
  'image': '',
  'cover': '',
  'genres': [],
  'sources': [],
  'countries': [],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resume rule', () {
    test('requires more than 60 seconds of duration', () {
      expect(resumePosition(position: 30, duration: 60), isNull);
      expect(resumePosition(position: 30, duration: 60.5), 30);
      expect(resumePosition(position: 30, duration: 61), 30);
    });

    test('requires more than 15 seconds watched', () {
      expect(resumePosition(position: 15, duration: 600), isNull);
      expect(
        resumePosition(position: 15.1, duration: 600),
        closeTo(15.1, 1e-9),
      );
    });

    test('treats 98 percent or more as finished', () {
      expect(resumePosition(position: 98, duration: 100), isNull);
      expect(resumePosition(position: 97.9, duration: 100), 97.9);
    });

    test('never resumes without a known duration or position', () {
      expect(resumePosition(position: 40, duration: null), isNull);
      expect(resumePosition(position: null, duration: 600), isNull);
    });
  });

  group('legacy history migration', () {
    test('converts an old percentage when the duration is known', () {
      expect(migratedPositionFromProgress(0.5, 120), 60);
      expect(migratedPositionFromProgress(2, 120), 120);
      expect(migratedPositionFromProgress(0.5, null), isNull);
      expect(migratedPositionFromProgress(0.5, 0), isNull);
    });

    test('loads percent-only records from older Android builds', () async {
      final item = movie(id: 7, title: 'Old Movie');
      final payload = {
        'item': item.toJson(),
        'lastWatchedAt': '2026-10-01T10:00:00.000',
        'progress': 0.42,
        'episodes': [],
      };
      SharedPreferences.setMockInitialValues({
        'ccloud.history': [jsonEncode(payload)],
      });
      final prefs = await SharedPreferences.getInstance();
      final store = HistoryStore(prefs);

      expect(store.entries, hasLength(1));
      final entry = store.entryFor(item);
      expect(entry, isNotNull);
      expect(entry!.progress, closeTo(0.42, 1e-9));
      expect(entry.position, isNull);
      expect(entry.duration, isNull);
      // Unknown duration means no exact resume point, but the record survives.
      expect(entry.resumePosition, isNull);
      expect(store.resumePositionFor(item), isNull);
    });

    test('loads old series episodes without position fields', () async {
      final series = MediaItem.fromJson({
        ...movie(id: 9, title: 'Show').toJson(),
        'type': 'serie',
      });
      final payload = {
        'item': series.toJson(),
        'lastWatchedAt': '2026-10-01T10:00:00.000',
        'progress': 0.5,
        'episodes': [
          {
            'id': 11,
            'seasonTitle': 'فصل ۱',
            'label': 'قسمت ۱',
            'watchedAt': '2026-10-01T10:00:00.000',
            'progress': 0.5,
          },
        ],
      };
      SharedPreferences.setMockInitialValues({
        'ccloud.history': [jsonEncode(payload)],
      });
      final prefs = await SharedPreferences.getInstance();
      final store = HistoryStore(prefs);

      final last = store.lastWatchedEpisode(9);
      expect(last?.id, 11);
      expect(last?.position, isNull);
      expect(store.resumePositionForEpisode(9, 11), isNull);
    });
  });

  group('second-precision history', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('stores position and duration and derives a resume point', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = HistoryStore(prefs);
      final item = movie();

      await store.record(item, progress: 0.25, position: 150, duration: 600);

      final entry = store.entryFor(item)!;
      expect(entry.position, 150);
      expect(entry.duration, 600);
      expect(entry.resumePosition, 150);
      expect(store.resumePositionFor(item), 150);
    });

    test('does not resume a finished movie', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = HistoryStore(prefs);
      final item = movie();

      await store.record(item, progress: 1, position: 600, duration: 600);
      expect(store.resumePositionFor(item), isNull);
    });

    test('series keeps the newest episode and its own position', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = HistoryStore(prefs);
      final series = MediaItem.fromJson({
        ...movie(id: 3, title: 'Series').toJson(),
        'type': 'serie',
      });

      await store.record(
        series,
        progress: 0.3,
        position: 90,
        duration: 600,
        episodeId: 1,
        seasonTitle: 'فصل ۱',
        episodeLabel: 'قسمت ۱',
        at: DateTime(2026, 1, 1, 10),
      );
      await store.record(
        series,
        progress: 0.2,
        position: 60,
        duration: 600,
        episodeId: 2,
        seasonTitle: 'فصل ۱',
        episodeLabel: 'قسمت ۲',
        at: DateTime(2026, 1, 1, 11),
      );

      expect(store.lastWatchedEpisode(3)?.id, 2);
      expect(store.resumePositionForEpisode(3, 2), 60);
      expect(store.resumePositionForEpisode(3, 1), 90);
    });

    test('keeps at most 80 records, newest first', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = HistoryStore(prefs);
      final base = DateTime(2026, 1, 1);
      for (var i = 0; i < 85; i++) {
        await store.record(
          movie(id: i + 1, title: 'Movie $i'),
          progress: 0.1,
          position: 10,
          duration: 600,
          at: base.add(Duration(minutes: i)),
        );
      }

      expect(store.entries, hasLength(80));
      expect(store.entries.first.item.id, 85);
      expect(store.entries.last.item.id, 6);
    });

    test('round-trips position and duration through JSON', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = HistoryStore(prefs);
      await store.record(
        movie(id: 4),
        progress: 0.5,
        position: 300,
        duration: 600,
      );

      final reopened = HistoryStore(prefs);
      final entry = reopened.entryFor(movie(id: 4))!;
      expect(entry.position, 300);
      expect(entry.duration, 600);
      expect(entry.resumePosition, 300);
    });
  });

  group('LinkHealth', () {
    test('key strips query and fragment', () {
      expect(
        linkHealthKey('https://cdn.example/a/master.m3u8?token=1#t=4'),
        'https://cdn.example/a/master.m3u8',
      );
      expect(
        linkHealthKey('https://cdn.example/a/master.m3u8'),
        'https://cdn.example/a/master.m3u8',
      );
      expect(linkHealthKey('udp://1.2.3.4:8000?x=1'), 'udp://1.2.3.4:8000');
    });

    test('two failures deprioritise, success clears the record', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LinkHealthStore(prefs);
      const url = 'https://cdn.example/live.m3u8?token=abc';

      expect(store.isDeprioritised(url), isFalse);
      await store.recordFailure(url);
      expect(store.failureCount(url), 1);
      expect(store.isDeprioritised(url), isFalse);
      await store.recordFailure('https://cdn.example/live.m3u8?token=xyz');
      expect(store.failureCount(url), 2);
      expect(store.isDeprioritised(url), isTrue);
      expect(
        store.areAllDeprioritised([url, 'https://cdn.example/live.m3u8']),
        isTrue,
      );

      await store.recordSuccess(url);
      expect(store.isDeprioritised(url), isFalse);
    });

    test('records expire after seven days', () async {
      final failedAt = DateTime(2026, 1, 1, 12);
      SharedPreferences.setMockInitialValues({
        LinkHealthStore.storageKey: jsonEncode({
          'https://cdn.example/a.m3u8': {
            'failures': 3,
            'lastFailure': failedAt.toIso8601String(),
          },
          'https://cdn.example/b.m3u8': {
            'failures': 3,
            'lastFailure': failedAt
                .add(const Duration(days: 6))
                .toIso8601String(),
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = LinkHealthStore(
        prefs,
        now: failedAt.add(const Duration(days: 7, hours: 1)),
      );

      expect(store.failureCount('https://cdn.example/a.m3u8'), 0);
      expect(store.failureCount('https://cdn.example/b.m3u8'), 3);
    });

    test('keeps only the 300 newest records', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final base = DateTime(2026, 1, 1);
      final store = LinkHealthStore(prefs, clock: () => base);

      for (var i = 0; i < 305; i++) {
        await store.recordFailure(
          'https://cdn.example/$i.m3u8',
          at: base.add(Duration(seconds: i)),
        );
      }

      final raw = prefs.getString(LinkHealthStore.storageKey);
      expect(raw, isNotNull);
      final decoded = (jsonDecode(raw!) as Map).cast<String, dynamic>();
      expect(decoded, hasLength(300));
      expect(decoded.containsKey('https://cdn.example/304.m3u8'), isTrue);
      expect(decoded.containsKey('https://cdn.example/0.m3u8'), isFalse);
      expect(decoded.containsKey('https://cdn.example/4.m3u8'), isFalse);
      expect(decoded.containsKey('https://cdn.example/5.m3u8'), isTrue);
    });
  });

  group('player labels', () {
    test('speed labels match the macOS %.2g format', () {
      expect(speedLabel(0.5), '0.5x');
      expect(speedLabel(0.75), '0.75x');
      expect(speedLabel(1), '1x');
      expect(speedLabel(1.25), '1.2x');
      expect(speedLabel(1.5), '1.5x');
      expect(speedLabel(2), '2x');
    });

    test('audio labels prefer the Persian language name', () {
      expect(
        audioTrackLabel(language: 'fa-IR', title: 'Persian', ordinal: 0),
        'فارسی',
      );
      expect(
        audioTrackLabel(language: 'eng', title: 'English 5.1', ordinal: 1),
        'انگلیسی',
      );
      expect(
        audioTrackLabel(language: 'zzz', title: 'Commentary', ordinal: 0),
        'Commentary',
      );
      expect(audioTrackLabel(ordinal: 1), 'صدای ۲');
    });

    test('player clock matches macOS PlayerTime.string', () {
      expect(formatPlayerTime(0), '0:00');
      expect(formatPlayerTime(5.4), '0:05');
      expect(formatPlayerTime(754), '12:34');
      expect(formatPlayerTime(3723), '1:02:03');
      expect(formatPlayerTime(double.nan), '0:00');
    });

    test('episode labels follow the macOS numbering rule', () {
      Episode episode(String title) => Episode(
        id: 7,
        title: title,
        description: null,
        duration: null,
        image: null,
        sources: const [],
      );
      expect(episodeLabelText(episode('قسمت 12')), 'قسمت ۱۲');
      expect(episodeLabelText(episode('قسمت ۳')), 'قسمت ۳');
      expect(episodeLabelText(episode('پایان فصل')), 'پایان فصل');
    });
  });
}
