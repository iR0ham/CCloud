import 'package:flutter/foundation.dart';

/// Cross-screen signals, the Flutter counterpart of the macOS `AppState`
/// `refreshTick` / `searchFocusTick` counters.
class AppEvents {
  AppEvents._();

  /// Bumped by the desktop refresh shortcut; data-driven screens reload.
  static final ValueNotifier<int> refreshTick = ValueNotifier<int>(0);

  /// Bumped when the search screen must focus its field.
  static final ValueNotifier<int> searchFocusTick = ValueNotifier<int>(0);

  static void requestRefresh() => refreshTick.value += 1;

  static void focusSearch() => searchFocusTick.value += 1;
}
