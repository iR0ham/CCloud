import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/platform_info.dart';
import 'core/stores.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await PlatformInfo.detect();
  final prefs = await SharedPreferences.getInstance();
  AppServices.init(prefs);
  runApp(const CCloudApp());
}
