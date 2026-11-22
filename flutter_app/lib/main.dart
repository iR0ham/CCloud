import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/api_cache.dart';
import 'core/api_client.dart';
import 'core/startup_bootstrap.dart';
import 'core/stores.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (_) {
    // A player that cannot initialise must not take the whole app down.
  }

  // Every plugin lookup below is time-boxed and isolated: a locked-down or
  // broken Windows profile must still reach runApp with a visible message.
  final startup = await loadStartup();
  if (!startup.ready) {
    runApp(StartupFailureApp(failure: startup.failure));
    return;
  }

  final downloads = startup.downloads;
  downloads.onCompleted = (item) {
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text('دانلود «${item.title}» کامل شد')),
    );
  };
  try {
    AppServices.init(startup.preferences!, downloads: downloads);
  } catch (error, stack) {
    // A corrupt settings file can make the stores throw while they load; show
    // the same visible failure screen instead of leaving the window empty.
    await recordStartupError(error, stack);
    runApp(StartupFailureApp(failure: error));
    return;
  }
  try {
    ApiClient.instance.attachOfflineCache(
      await OfflineCache.open().timeout(const Duration(seconds: 5)),
    );
  } catch (_) {
    // Without the disk fallback the app still works online; a broken app-data
    // directory must not block startup.
  }
  runApp(const CCloudApp());
}

/// Shown when the settings store itself is unavailable.
///
/// The native Windows runner already logs startup failures to
/// `%LOCALAPPDATA%\CCloud\startup.log`; this screen makes a Dart-side failure
/// visible as well instead of leaving an empty window.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, this.failure});

  final Object? failure;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCloud',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.dark(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'راه‌اندازی CCloud ممکن نشد',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'محل ذخیرهٔ تنظیمات در دسترس نیست. برنامه را ببندید و '
                    'دوباره باز کنید؛ اگر مشکل تکرار شد، فایل '
                    'startup.log را از پوشهٔ دادهٔ برنامه بفرستید.',
                    textAlign: TextAlign.center,
                  ),
                  if (failure != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '$failure',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
