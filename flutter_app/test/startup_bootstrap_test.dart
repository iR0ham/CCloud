import 'dart:async';

import 'package:ccloud/core/downloads_store.dart';
import 'package:ccloud/core/startup_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'throwing and hanging storage still produces a runnable state',
    () async {
      final errors = <Object>[];
      final state = await loadStartup(
        timeout: const Duration(milliseconds: 50),
        loadPreferences: () => Future.error(StateError('no settings folder')),
        openDownloads: () => Future.error(StateError('no app-data folder')),
        detectPlatform: () => Completer<void>().future,
        loadIdentity: () => Completer<void>().future,
        reportError: (error, stack) async => errors.add(error),
      );

      expect(state.ready, isFalse);
      expect(state.failure, isNotNull);
      expect(state.downloads, isA<DownloadsStore>());
      // The two throwing steps are reported; the two hanging ones time out and
      // are reported as TimeoutException.
      expect(errors, hasLength(4));
    },
  );

  test('working settings stay usable when the downloads store fails', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final errors = <Object>[];
    final state = await loadStartup(
      loadPreferences: SharedPreferences.getInstance,
      openDownloads: () => Future.error(StateError('no downloads folder')),
      detectPlatform: () => Future.value(),
      loadIdentity: () => Future.value(),
      reportError: (error, stack) async => errors.add(error),
    );

    expect(state.ready, isTrue);
    expect(state.preferences, isNotNull);
    expect(state.downloads, isA<DownloadsStore>());
    expect(errors, hasLength(1));
  });
}
