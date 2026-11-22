import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'downloads_store.dart';
import 'platform_identity.dart';
import 'platform_info.dart';

/// How long one bootstrap step may take before the app starts without it.
///
/// The Windows runner warns after 15 seconds without a first frame, so the
/// whole pre-runApp phase must finish well before that.
const Duration startupStepTimeout = Duration(seconds: 8);

/// Everything `runApp` needs, resolved without letting one broken location
/// kill startup. `ready` is false only when the settings store is unavailable.
class StartupState {
  const StartupState({
    required this.preferences,
    required this.downloads,
    this.failure,
  });

  final SharedPreferences? preferences;
  final DownloadsStore downloads;

  /// The error that prevented the settings store from opening, if any.
  final Object? failure;

  bool get ready => preferences != null;
}

/// Resolves platform info, settings and the downloads store before `runApp`.
///
/// Every step is time-boxed and isolated: a throwing or hanging plugin (for
/// example a disk-permission failure on a locked-down Windows machine) must
/// not leave the process alive with no window and no message. The steps run
/// concurrently, so the worst case is one [timeout], not four.
Future<StartupState> loadStartup({
  Duration timeout = startupStepTimeout,
  Future<SharedPreferences> Function() loadPreferences =
      SharedPreferences.getInstance,
  Future<DownloadsStore> Function() openDownloads = DownloadsStore.open,
  Future<void> Function() detectPlatform = PlatformInfo.detect,
  Future<void> Function() loadIdentity = PlatformIdentity.load,
  Future<void> Function(Object error, StackTrace stack) reportError =
      recordStartupError,
}) async {
  Future<T?> guard<T>(Future<T> Function() task) async {
    try {
      return await task().timeout(timeout);
    } catch (error, stack) {
      try {
        await reportError(error, stack);
      } catch (_) {
        // Diagnostics are best effort; they never change startup behaviour.
      }
      return null;
    }
  }

  final detect = guard(detectPlatform);
  final identity = guard(loadIdentity);
  final preferences = guard(loadPreferences);
  final downloads = guard(openDownloads);

  final prefs = await preferences;
  final store = await downloads ?? DownloadsStore.degraded();
  await detect;
  await identity;

  return StartupState(
    preferences: prefs,
    downloads: store,
    failure: prefs == null ? 'settings storage unavailable' : null,
  );
}

/// Appends one line to the startup log. Silently does nothing when the folder
/// cannot be resolved, and the whole write is capped at two seconds so a slow
/// disk can never push diagnostics past the native watchdog window.
Future<void> recordStartupError(Object error, StackTrace stack) async {
  try {
    await _writeStartupError(error, stack).timeout(const Duration(seconds: 2));
  } catch (_) {
    // A broken app-data folder must not become a second startup failure.
  }
}

Future<void> _writeStartupError(Object error, StackTrace stack) async {
  final Directory directory;
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (Platform.isWindows && localAppData != null && localAppData.isNotEmpty) {
    // The native runner writes %LOCALAPPDATA%\CCloud\startup.log; keep the Dart
    // diagnostics in the same file so the user has one log, not two folders.
    directory = Directory('$localAppData${Platform.pathSeparator}CCloud');
  } else {
    final base = await getApplicationSupportDirectory().timeout(
      const Duration(seconds: 2),
    );
    directory = Directory('${base.path}${Platform.pathSeparator}CCloudMac');
  }
  await directory.create(recursive: true);
  final log = File('${directory.path}${Platform.pathSeparator}startup.log');
  final entry =
      '${DateTime.now().toUtc().toIso8601String()} '
      '${error.toString()}\n$stack\n';
  await log.writeAsString(entry, mode: FileMode.append, flush: true);
}
