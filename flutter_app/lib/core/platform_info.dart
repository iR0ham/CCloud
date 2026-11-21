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

/// Whether the player root should let a key through untouched.
///
/// On TV the D-pad has to move focus between the visible controls, so while a
/// descendant owns focus the root handler yields and Flutter's focus traversal
/// runs. With nothing focused (controls hidden) the root keeps seeking and
/// changing volume, which is the pre-existing remote behaviour.
bool playerYieldsKeysToFocusedChild({
  required bool isTv,
  required bool hasPrimaryFocus,
  required bool rootHasPrimaryFocus,
}) => isTv && hasPrimaryFocus && !rootHasPrimaryFocus;
