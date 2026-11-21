import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api_cache.dart';
import 'core/api_client.dart';
import 'core/downloads_store.dart';
import 'core/platform_identity.dart';
import 'core/platform_info.dart';
import 'core/stores.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await PlatformInfo.detect();
  await PlatformIdentity.load();
  final prefs = await SharedPreferences.getInstance();
  final downloads = await DownloadsStore.open();
  downloads.onCompleted = (item) {
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text('دانلود «${item.title}» کامل شد')),
    );
  };
  AppServices.init(prefs, downloads: downloads);
  try {
    ApiClient.instance.attachOfflineCache(await OfflineCache.open());
  } catch (_) {
    // Without the disk fallback the app still works online; a broken app-data
    // directory must not block startup.
  }
  runApp(const CCloudApp());
}
