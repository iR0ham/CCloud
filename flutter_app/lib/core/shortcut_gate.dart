/// Desktop shortcuts must not fire while another route owns the screen.
///
/// A dialog, a bottom sheet or the pushed player route makes the shell route
/// non-current; the shell's global keys then stay out of the way.
bool desktopShortcutAllowed({
  required bool desktopPlatform,
  required bool shellRouteCurrent,
}) => desktopPlatform && shellRouteCurrent;
