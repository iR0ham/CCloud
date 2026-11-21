import 'package:flutter_test/flutter_test.dart';

import 'package:ccloud/core/live_catalog.dart';
import 'package:ccloud/core/models.dart';
import 'package:ccloud/core/playback.dart';

LiveTvChannel _channel(
  String name,
  List<String> streams, {
  String country = 'IR',
  List<String> languages = const [],
}) => LiveTvChannel(
  nanoid: 'n-$name',
  name: name,
  streams: streams,
  languages: languages,
  country: country,
  isGeoBlocked: false,
);

M3uEntry _entry(
  String name,
  List<String> streams, {
  String countryCode = 'IR',
}) => M3uEntry(
  id: liveNameKey(name),
  name: name,
  countryCode: countryCode,
  group: 'News',
  streams: streams,
);

void main() {
  group('name normalization', () {
    test('folds Arabic/Persian letters, digits and separators', () {
      expect(liveNameKey('پرس تی‌وی'), liveNameKey('پرس تی وی'));
      expect(liveNameKey('شبکهٔ يك'), liveNameKey('شبکه یک'));
      expect(liveNameKey('IRIB ۱'), liveNameKey('irib 1'));
      expect(liveNameKey('  Press-TV  '), 'press tv');
    });

    test('strips quality noise from the display name', () {
      expect(m3uDisplayName('Press TV (720p)'), 'Press TV');
      expect(m3uDisplayName('IRIB 1 [SD]'), 'IRIB 1');
      expect(m3uDisplayName('BBC Persian (1080i)'), 'BBC Persian');
      expect(m3uDisplayName('News (English)'), 'News (English)');
    });

    test('parses tvg-id, group and the stream URL', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="PressTV.us@SD" tvg-logo="x" group-title="News",Press TV (720p)
https://a.example/live.m3u8
#EXTINF:-1 tvg-id="IRIB1.ir" group-title="General",IRIB 1
https://b.example/one.m3u8
''';
      final entries = parseM3u(playlist);
      expect(entries.length, 2);
      expect(entries.first.id, 'PressTV');
      expect(entries.first.name, 'Press TV');
      expect(entries.first.countryCode, 'US');
      expect(entries.first.group, 'News');
      expect(entries.first.streams, ['https://a.example/live.m3u8']);
      expect(entries.last.id, 'IRIB1');
      expect(entries.last.countryCode, 'IR');
    });

    test('ignores unknown lines without an EXTINF header', () {
      final entries = parseM3u('https://orphan.example/stream.m3u8');
      expect(entries, isEmpty);
    });
  });

  group('Iran merge', () {
    test('iptv-org adds no channels', () {
      final famelack = [_channel('Press TV', ['https://f/press.m3u8'])];
      final merged = mergeIranChannels(
        famelack: famelack,
        byCountry: [
          _entry('Press TV', ['https://i/press.m3u8']),
          _entry('Diaspora TV', ['https://i/diaspora.m3u8']),
        ],
        byLanguage: [_entry('Manoto TV', ['https://i/manoto.m3u8'])],
      );
      expect(merged.length, 1);
      expect(merged.single.name, 'Press TV');
    });

    test('adds only unique URLs, case-insensitively', () {
      final famelack = [
        _channel('Press TV', ['https://A.example/live.m3u8']),
      ];
      final merged = mergeIranChannels(
        famelack: famelack,
        byCountry: [
          _entry('press tv', [
            'https://a.example/live.m3u8',
            'https://backup.example/live.m3u8',
          ]),
        ],
        byLanguage: [
          _entry('Press TV', ['https://BACKUP.example/live.m3u8']),
        ],
      );
      expect(merged.single.streams, [
        'https://A.example/live.m3u8',
        'https://backup.example/live.m3u8',
      ]);
    });

    test('countries come before the Persian playlist and match by name', () {
      final famelack = [
        _channel('IRIB ۱', ['https://f/one.m3u8']),
        _channel('Press TV', ['https://f/press.m3u8']),
      ];
      final merged = mergeIranChannels(
        famelack: famelack,
        byCountry: [
          _entry('IRIB 1', ['https://i/one.m3u8']),
        ],
        byLanguage: [
          _entry('IRIB 1', ['https://i/one-fa.m3u8']),
          _entry('Press TV', ['https://i/press.m3u8']),
        ],
      );
      expect(merged.map((c) => c.name), ['IRIB ۱', 'Press TV']);
      expect(merged.first.streams, [
        'https://f/one.m3u8',
        'https://i/one.m3u8',
        'https://i/one-fa.m3u8',
      ]);
    });

    test('sorts channels case-insensitively like the macOS list', () {
      final merged = mergeIranChannels(
        famelack: [
          _channel('z TV', ['https://z']),
          _channel('Alpha TV', ['https://a']),
        ],
        byCountry: const [],
        byLanguage: const [],
      );
      expect(merged.map((c) => c.name), ['Alpha TV', 'z TV']);
    });
  });

  group('live playback sources', () {
    final channel = _channel('Press TV', [
      'https://cdn.example/live.m3u8',
      'https://cdn.example/backup.mp4',
    ]);

    test('one MediaSource per URL with Persian labels', () {
      final args = PlayerArgs.forChannel(channel, 'ایران');
      expect(args.sources.length, 2);
      expect(args.sources.first.id, 1);
      expect(args.sources.first.qualityLabel, 'منبع اصلی');
      expect(args.sources.last.qualityLabel, 'منبع ۲');
      expect(args.sources.first.kind, 'hls');
      expect(args.sources.last.kind, 'mp4');
      expect(args.preferredSourceId, 1);
      expect(args.subtitle, 'پخش زنده • ایران');
      expect(args.isLive, isTrue);
    });

    test('a single stream is labelled with its own quality', () {
      final args = PlayerArgs.forChannel(
        _channel('IRIB 1', ['https://cdn.example/one.m3u8']),
        'ایران',
      );
      expect(args.sources.single.qualityLabel, 'کیفیت اصلی');
    });

    test('a chosen stream becomes the only source', () {
      final args = PlayerArgs.forChannel(
        channel,
        'ایران',
        streamOverride: 'https://cdn.example/backup.mp4',
      );
      expect(args.sources.length, 1);
      expect(args.sources.single.url, 'https://cdn.example/backup.mp4');
      expect(args.sources.single.qualityLabel, 'کیفیت اصلی');
    });
  });
}
