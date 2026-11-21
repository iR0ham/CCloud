import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'models.dart';

// MARK: - In-app download manager
//
// Saves progressive files (mp4/mkv/webm/avi/mov) into a CCloud folder inside
// the platform's Downloads location. HLS/DASH playlists are not one file, so
// the callers fall back to copying the link. Metadata lives in Application
// Support and an interrupted download is reported as failed so it can be
// retried; there is no resume, matching the macOS `DownloadsStore`.
//
// Android has no public "Downloads/CCloud" path the app may write to without
// broad storage permissions, so the folder is the app-allowed external files
// directory: Android/data/<package>/files/CCloud (visible from a file manager
// on Android 10 and older, removed with the app). Windows and desktop Linux
// use the real user Downloads folder.

enum DownloadState { downloading, completed, failed }

enum DownloadStartResult { started, duplicate, unsupported }

class DownloadItem {
  DownloadItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.posterURL,
    required this.sourceURL,
    required this.fileName,
    required this.kind,
    required this.state,
    required this.receivedBytes,
    required this.totalBytes,
    required this.createdAt,
    required this.errorMessage,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? posterURL;
  final String sourceURL;
  final String fileName;
  final String kind;
  DownloadState state;
  int receivedBytes;
  int totalBytes;
  final DateTime createdAt;
  String? errorMessage;

  /// 0 when the server sends no Content-Length; stays 0% until the end.
  double get progress {
    if (totalBytes <= 0) return 0;
    final value = receivedBytes / totalBytes;
    return value.clamp(0.0, 1.0).toDouble();
  }

  bool fileExistsIn(Directory directory) =>
      File('${directory.path}${Platform.pathSeparator}$fileName').existsSync();

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final state = switch (json['state']) {
      'completed' => DownloadState.completed,
      'failed' => DownloadState.failed,
      _ => DownloadState.downloading,
    };
    return DownloadItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      posterURL: json['posterURL']?.toString(),
      sourceURL: json['sourceURL']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      state: state,
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      errorMessage: json['errorMessage']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'posterURL': posterURL,
    'sourceURL': sourceURL,
    'fileName': fileName,
    'kind': kind,
    'state': state.name,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'errorMessage': errorMessage,
  };
}

/// Persian text for a failed attempt, matching the macOS URLError mapping.
String downloadErrorText(Object error) {
  if (error is TimeoutException) return 'پاسخ سرور دیر رسید.';
  if (error is SocketException) {
    final message = error.message.toLowerCase();
    if (message.contains('failed host lookup') ||
        message.contains('name or service not known')) {
      return 'سرور پیدا نشد.';
    }
    if (message.contains('connection reset') ||
        message.contains('broken pipe') ||
        message.contains('connection closed') ||
        message.contains('connection refused')) {
      return 'اتصال شبکه قطع شد.';
    }
    return 'اینترنت در دسترس نیست.';
  }
  if (error is HttpException) return 'اتصال شبکه قطع شد.';
  return 'دانلود ناموفق بود.';
}

class _DownloadStatusError implements Exception {
  const _DownloadStatusError(this.message);

  final String message;
}

class _DownloadJob {
  bool cancelled = false;
  int received = 0;
  HttpClient? client;
}

class DownloadsStore extends ChangeNotifier {
  DownloadsStore({
    required this.directory,
    required this.metadataFile,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new {
    try {
      directory.createSync(recursive: true);
    } catch (_) {
      // A read-only or missing external volume must not stop the app from
      // starting; downloads then fail with the disk-save message.
    }
    _load();
  }

  /// Resolves the platform destination and loads stored metadata.
  static Future<DownloadsStore> open() async {
    final directory = await _resolveDirectory();
    final base = await getApplicationSupportDirectory();
    final metadataDirectory = Directory(
      '${base.path}${Platform.pathSeparator}CCloudMac',
    );
    try {
      await metadataDirectory.create(recursive: true);
    } catch (_) {}
    return DownloadsStore(
      directory: directory,
      metadataFile: File(
        '${metadataDirectory.path}${Platform.pathSeparator}downloads.json',
      ),
    );
  }

  static Future<Directory> _resolveDirectory() async {
    Directory? base;
    try {
      if (Platform.isAndroid) {
        // App-allowed external storage; no storage permission needed.
        base = await getExternalStorageDirectory();
      } else {
        base = await getDownloadsDirectory();
      }
    } catch (_) {
      base = null;
    }
    base ??= Directory(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}Downloads',
    );
    final directory = Directory('${base.path}${Platform.pathSeparator}CCloud');
    try {
      await directory.create(recursive: true);
    } catch (_) {}
    return directory;
  }

  /// Folder holding saved files (Downloads/CCloud on Windows).
  final Directory directory;
  final File metadataFile;
  final HttpClient Function() _clientFactory;

  /// Called on the UI isolate when a download finishes successfully.
  ValueChanged<DownloadItem>? onCompleted;

  final List<DownloadItem> _items = [];
  final Map<String, _DownloadJob> _jobs = {};
  final Map<String, Timer> _timers = {};

  List<DownloadItem> get items => List.unmodifiable(_items);

  DownloadItem? itemFor(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  File fileFor(DownloadItem item) =>
      File('${directory.path}${Platform.pathSeparator}${item.fileName}');

  // MARK: Public actions

  DownloadStartResult start({
    required String title,
    String? subtitle,
    String? posterURL,
    required MediaSource source,
  }) {
    final uri = Uri.tryParse(source.url);
    if (!source.isFileDownloadable ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return DownloadStartResult.unsupported;
    }
    if (_items.any(
      (item) =>
          item.sourceURL == source.url &&
          item.state == DownloadState.downloading,
    )) {
      return DownloadStartResult.duplicate;
    }
    final extensionName = source.downloadFileExtension;
    startDownload(
      title: title,
      subtitle: subtitle,
      posterURL: posterURL,
      url: uri,
      fileName: fileNameFor(
        title: title,
        quality: source.qualityLabel,
        extensionName: extensionName,
      ),
      kind: extensionName,
    );
    return DownloadStartResult.started;
  }

  void retry(String id) {
    final item = itemFor(id);
    if (item == null) return;
    final uri = Uri.tryParse(item.sourceURL);
    if (uri == null) return;
    startDownload(
      title: item.title,
      subtitle: item.subtitle,
      posterURL: item.posterURL,
      url: uri,
      fileName: item.fileName,
      kind: item.kind,
      reuseID: item.id,
    );
  }

  /// Cancels the transfer, drops the record and deletes the partial/final file.
  void cancel(String id) {
    final job = _jobs.remove(id);
    job?.cancelled = true;
    job?.client?.close(force: true);
    _timers.remove(id)?.cancel();

    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _items.removeAt(index);
    _deleteQuietly(fileFor(item));
    _deleteQuietly(_temporaryFile(id));
    _save();
    notifyListeners();
  }

  /// Removes the record; a finished file stays on disk.
  void remove(String id) {
    final item = itemFor(id);
    if (item == null) return;
    if (item.state == DownloadState.downloading) {
      cancel(id);
      return;
    }
    _items.removeWhere((entry) => entry.id == id);
    _save();
    notifyListeners();
  }

  /// Drops finished/failed records; downloaded files stay on disk.
  void clearFinished() {
    _items.removeWhere((item) => item.state != DownloadState.downloading);
    _save();
    notifyListeners();
  }

  /// Opens the file in the platform file manager. Returns false on Android,
  /// where there is no file-manager hook: the caller shows/copies the path.
  Future<bool> reveal(String id) async {
    final item = itemFor(id);
    if (item == null) return false;
    if (!fileFor(item).existsSync()) return revealFolder();
    if (Platform.isWindows) {
      await _launch('explorer', ['/select,${fileFor(item).path}']);
      return true;
    }
    if (Platform.isMacOS) {
      await _launch('open', ['-R', fileFor(item).path]);
      return true;
    }
    if (Platform.isLinux) {
      await _launch('xdg-open', [directory.path]);
      return true;
    }
    return false;
  }

  /// Opens the downloads folder. Returns false on Android.
  Future<bool> revealFolder() async {
    if (Platform.isWindows) {
      await _launch('explorer', [directory.path]);
      return true;
    }
    if (Platform.isMacOS) {
      await _launch('open', [directory.path]);
      return true;
    }
    if (Platform.isLinux) {
      await _launch('xdg-open', [directory.path]);
      return true;
    }
    return false;
  }

  // MARK: Download lifecycle

  void startDownload({
    required String title,
    required String? subtitle,
    required String? posterURL,
    required Uri url,
    required String fileName,
    required String kind,
    String? reuseID,
  }) {
    final id = reuseID ?? _newID();
    final item = DownloadItem(
      id: id,
      title: title,
      subtitle: subtitle,
      posterURL: posterURL,
      sourceURL: url.toString(),
      fileName: fileName,
      kind: kind,
      state: DownloadState.downloading,
      receivedBytes: 0,
      totalBytes: 0,
      createdAt: DateTime.now(),
      errorMessage: null,
    );
    final index = _items.indexWhere((entry) => entry.id == id);
    if (index >= 0) {
      _items[index] = item;
    } else {
      _items.insert(0, item);
    }
    _save();
    notifyListeners();
    _timers.remove(id)?.cancel();
    _startMonitor(id);
    unawaited(_run(item, url));
  }

  Future<void> _run(DownloadItem item, Uri url) async {
    // A cancel may land before the first await resumes; nothing to do then.
    if (!_hasItem(item.id)) return;
    final job = _DownloadJob();
    _jobs[item.id] = job;
    final temp = _temporaryFile(item.id);
    _deleteQuietly(temp);

    final client = _clientFactory();
    job.client = client;
    IOSink? sink;
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, ApiClient.userAgent);
      final response = await request.close();
      final status = response.statusCode;
      if (status < 200 || status >= 300) {
        throw _DownloadStatusError('سرور با کد $status پاسخ داد.');
      }
      final total = response.contentLength;
      if (total > 0) _updateTotal(item.id, total);

      sink = temp.openWrite();
      await for (final chunk in response) {
        if (job.cancelled) return;
        sink.add(chunk);
        job.received += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (job.cancelled) return;
      await _finish(item.id, temp);
    } on _DownloadStatusError catch (error) {
      if (!job.cancelled) _fail(item.id, error.message);
    } catch (error) {
      if (!job.cancelled) _fail(item.id, downloadErrorText(error));
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      client.close(force: true);
      _jobs.remove(item.id);
      _timers.remove(item.id)?.cancel();
      if (job.cancelled || !_hasItem(item.id)) {
        _deleteQuietly(temp);
      }
    }
  }

  void _startMonitor(String id) {
    _timers[id] = Timer.periodic(const Duration(milliseconds: 350), (_) {
      final job = _jobs[id];
      if (job == null) return;
      final index = _items.indexWhere((item) => item.id == id);
      if (index < 0) return;
      if (_items[index].receivedBytes == job.received) return;
      _items[index].receivedBytes = job.received;
      notifyListeners();
    });
  }

  void _updateTotal(String id, int total) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    if (_items[index].totalBytes == total) return;
    _items[index].totalBytes = total;
    notifyListeners();
  }

  Future<void> _finish(String id, File temp) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) {
      _deleteQuietly(temp);
      return;
    }
    final item = _items[index];
    final target = fileFor(item);
    try {
      if (target.existsSync()) target.deleteSync();
      try {
        await temp.rename(target.path);
      } catch (_) {
        await temp.copy(target.path);
        _deleteQuietly(temp);
      }
      final size = await target.length();
      item.state = DownloadState.completed;
      item.receivedBytes = size;
      item.totalBytes = size;
      item.errorMessage = null;
      _save();
      notifyListeners();
      onCompleted?.call(item);
    } on FileSystemException catch (error) {
      _fail(id, 'ذخیرهٔ فایل ممکن نشد: ${error.message}');
    } catch (error) {
      _fail(id, 'ذخیرهٔ فایل ممکن نشد: $error');
    }
  }

  void _fail(String id, String message) {
    final item = itemFor(id);
    if (item == null) return;
    item.state = DownloadState.failed;
    item.errorMessage = message;
    _deleteQuietly(_temporaryFile(id));
    _save();
    notifyListeners();
  }

  File _temporaryFile(String id) =>
      File('${directory.path}${Platform.pathSeparator}.$id.part');

  bool _hasItem(String id) => _items.any((item) => item.id == id);

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static Future<void> _launch(String executable, List<String> arguments) async {
    try {
      await Process.run(executable, arguments);
    } catch (_) {}
  }

  // MARK: Persistence

  void _load() {
    if (!metadataFile.existsSync()) return;
    try {
      final decoded = jsonDecode(metadataFile.readAsStringSync());
      if (decoded is! List) return;
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final item = DownloadItem.fromJson(raw.cast<String, dynamic>());
        switch (item.state) {
          case DownloadState.downloading:
            item.state = DownloadState.failed;
            item.errorMessage = 'دانلود پیش از پایان قطع شد.';
          case DownloadState.completed:
            if (!item.fileExistsIn(directory)) {
              item.state = DownloadState.failed;
              item.errorMessage = 'فایل از پوشهٔ دانلودها حذف شده است.';
            }
          case DownloadState.failed:
            break;
        }
        _items.add(item);
      }
    } catch (_) {}
  }

  void _save() {
    try {
      final data = jsonEncode(_items.map((item) => item.toJson()).toList());
      metadataFile.writeAsStringSync(data, flush: true);
    } catch (_) {}
  }

  // MARK: Helpers

  /// `"<title> <qualityLabel>.<ext>"`, with `/` and `:` folded to `-`, an
  /// empty title replaced by `CCloud`, and the base name capped at 90 chars.
  static String fileNameFor({
    required String title,
    required String quality,
    required String extensionName,
  }) {
    var base = title.replaceAll('/', '-').replaceAll(':', '-').trim();
    if (base.isEmpty) base = 'CCloud';
    if (base.length > 90) base = base.substring(0, 90);
    return '$base $quality.$extensionName';
  }

  static String _newID() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    for (final job in _jobs.values) {
      job.cancelled = true;
      job.client?.close(force: true);
    }
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _jobs.clear();
    _timers.clear();
    super.dispose();
  }
}
