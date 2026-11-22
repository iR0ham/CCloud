import 'package:ccloud/core/shortcut_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop shortcuts only act while the shell owns the screen', () {
    expect(
      desktopShortcutAllowed(desktopPlatform: true, shellRouteCurrent: true),
      isTrue,
    );
    expect(
      desktopShortcutAllowed(desktopPlatform: true, shellRouteCurrent: false),
      isFalse,
    );
    expect(
      desktopShortcutAllowed(desktopPlatform: false, shellRouteCurrent: true),
      isFalse,
    );
    expect(
      desktopShortcutAllowed(desktopPlatform: false, shellRouteCurrent: false),
      isFalse,
    );
  });
}
