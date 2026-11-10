import 'package:flutter/services.dart';

/// Whether the app is running on Android TV (leanback / no touchscreen).
class PlatformInfo {
  static bool isTv = false;

  static Future<void> detect() async {
    try {
      final result = await const MethodChannel('ccloud/platform')
          .invokeMethod<bool>('isTv');
      isTv = result ?? false;
    } catch (_) {
      isTv = false;
    }
  }
}
