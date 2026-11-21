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

/// Whether returning to the app should offer the next episode again.
///
/// The countdown is cancelled whenever the app goes to the background. On
/// resume it restarts only if the item is still sitting at its end, nothing is
/// counting down, and the viewer did not tap «لغو» — an explicit dismissal must
/// not be undone by a later resume.
bool shouldOfferAutoNextOnResume({
  required bool completed,
  required int countdown,
  required bool dismissed,
  required bool hasUpcoming,
  required bool autoPlayNextEpisode,
}) =>
    completed &&
    countdown == 0 &&
    !dismissed &&
    hasUpcoming &&
    autoPlayNextEpisode;
