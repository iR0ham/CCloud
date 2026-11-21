import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ccloud/core/downloads_store.dart';
import 'package:ccloud/core/models.dart';

DownloadItem _item({
  required String id,
  String title = 'فیلم نمونه',
  String fileName = 'فیلم نمونه 720p.mp4',
  DownloadState state = DownloadState.downloading,
  int received = 0,
  int total = 0,
  String? error,
}) => DownloadItem(
  id: id,
  title: title,
  subtitle: '2024 • درام',
  posterURL: null,
  sourceURL: 'https://example.com/$id.mp4',
  fileName: fileName,
  kind: 'mp4',
  state: state,
  receivedBytes: received,
  totalBytes: total,
  createdAt: DateTime.utc(2026, 11, 21, 10),
  errorMessage: error,
);

Future<void> _writeMetadata(File file, List<DownloadItem> items) async {
  await file.writeAsString(
    jsonEncode(items.map((item) => item.toJson()).toList()),
    flush: true,
  );
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ccloud-downloads-test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  DownloadsStore openStore() => DownloadsStore(
    directory: Directory('${temp.path}${Platform.pathSeparator}CCloud')
      ..createSync(recursive: true),
    metadataFile: File('${temp.path}${Platform.pathSeparator}downloads.json'),
  );

  group('file naming', () {
    test('uses "<title> <quality>.<ext>"', () {
      expect(
        DownloadsStore.fileNameFor(
          title: 'Dune',
          quality: '1080p',
          extensionName: 'mkv',
        ),
        'Dune 1080p.mkv',
      );
    });

    test('folds slashes and colons to dashes', () {
      expect(
        DownloadsStore.fileNameFor(
          title: 'Spider-Man: No Way/Home',
          quality: '720p',
          extensionName: 'mp4',
        ),
        'Spider-Man- No Way-Home 720p.mp4',
      );
    });

    test('replaces an empty title with CCloud', () {
      expect(
        DownloadsStore.fileNameFor(
          title: '   ',
          quality: 'کیفیت اصلی',
          extensionName: 'mp4',
        ),
        'CCloud کیفیت اصلی.mp4',
      );
    });

    test('caps the base name at 90 characters', () {
      final name = DownloadsStore.fileNameFor(
        title: 'x' * 140,
        quality: '720p',
        extensionName: 'mp4',
      );
      expect(name, '${'x' * 90} 720p.mp4');
    });
  });

  group('state machine', () {
    test('an interrupted download becomes failed on load', () async {
      final store = openStore();
      await _writeMetadata(store.metadataFile, [
        _item(id: 'a', received: 100, total: 1000),
      ]);
      final reloaded = openStore();
      expect(reloaded.items.single.state, DownloadState.failed);
      expect(reloaded.items.single.errorMessage, 'دانلود پیش از پایان قطع شد.');
      expect(reloaded.items.single.receivedBytes, 100);
    });

    test('cancel removes the record and deletes the file', () async {
      final store = openStore();
      await _writeMetadata(store.metadataFile, [
        _item(id: 'cancel-me', state: DownloadState.completed),
      ]);
      final reloaded = openStore();
      final file = reloaded.fileFor(reloaded.items.single);
      file.writeAsStringSync('video-bytes');
      expect(file.existsSync(), isTrue);

      reloaded.cancel('cancel-me');

      expect(reloaded.items, isEmpty);
      expect(file.existsSync(), isFalse);
      final saved = jsonDecode(reloaded.metadataFile.readAsStringSync());
      expect(saved, isEmpty);
    });

    test('clear list removes finished records but keeps files', () async {
      final store = openStore();
      await _writeMetadata(store.metadataFile, [
        _item(
          id: 'done',
          state: DownloadState.completed,
          received: 10,
          total: 10,
        ),
        _item(id: 'broken', state: DownloadState.failed, error: 'اتصال شبکه قطع شد.'),
      ]);
      final reloaded = openStore();
      final kept = reloaded.fileFor(
        reloaded.items.firstWhere((item) => item.id == 'done'),
      );
      kept.writeAsStringSync('kept');

      reloaded.clearFinished();

      expect(reloaded.items, isEmpty);
      expect(kept.existsSync(), isTrue);
    });

    test('remove keeps a completed file on disk', () async {
      final store = openStore();
      await _writeMetadata(store.metadataFile, [
        _item(id: 'keep', state: DownloadState.completed),
      ]);
      final reloaded = openStore();
      final file = reloaded.fileFor(reloaded.items.single);
      file.writeAsStringSync('kept');

      reloaded.remove('keep');

      expect(reloaded.items, isEmpty);
      expect(file.existsSync(), isTrue);
    });

    test('progress is clamped and 0% when the size is unknown', () {
      expect(_item(id: 'x', received: 50, total: 200).progress, 0.25);
      expect(_item(id: 'x', received: 300, total: 200).progress, 1.0);
      expect(_item(id: 'x', received: 50, total: 0).progress, 0.0);
    });

    test('a downloading file that vanished is reported failed on load', () async {
      final store = openStore();
      await _writeMetadata(store.metadataFile, [
        _item(
          id: 'missing',
          fileName: 'gone.mp4',
          state: DownloadState.completed,
        ),
      ]);
      final reloaded = openStore();
      expect(reloaded.items.single.state, DownloadState.failed);
      expect(
        reloaded.items.single.errorMessage,
        'فایل از پوشهٔ دانلودها حذف شده است.',
      );
    });
  });

  group('download eligibility', () {
    test('only progressive container types are downloadable', () {
      const progressive = ['mp4', 'mkv', 'webm', 'avi', 'mov'];
      for (final kind in progressive) {
        expect(
          MediaSource(id: 1, quality: '720p', type: kind, url: 'https://x/y')
              .isFileDownloadable,
          isTrue,
          reason: kind,
        );
      }
      for (final kind in ['hls', 'm3u8', 'dash', 'mpd']) {
        expect(
          MediaSource(id: 1, quality: '720p', type: kind, url: 'https://x/y')
              .isFileDownloadable,
          isFalse,
          reason: kind,
        );
      }
    });

    test('store rejects playlists and duplicates', () {
      final store = openStore();
      const playlist = MediaSource(
        id: 2,
        quality: '720p',
        type: 'hls',
        url: 'https://example.com/live.m3u8',
      );
      expect(
        store.start(title: 'x', source: playlist),
        DownloadStartResult.unsupported,
      );
      expect(store.items, isEmpty);
    });
  });
}
