import 'package:flutter/foundation.dart';

/// Backend reachability as reported by real requests.
///
/// The offline flag flips only when a failed request is answered from the
/// on-disk copy, exactly like the macOS `APIClient.reportConnectivity`: a
/// fresh network success clears it, while a request that fails with no cached
/// copy shows up as an error ("قطع") and keeps the last failure message.
class ConnectivityState extends ChangeNotifier {
  ConnectivityState(this._host);

  String _host;
  bool _offline = false;
  String? _lastError;

  String get host => _host;

  /// True while the API is serving the on-disk fallback.
  bool get isOffline => _offline;

  /// Last failure that had no cached copy, cleared by the next success.
  String? get lastError => _lastError;

  /// Sidebar dot: gold offline, red after a failed request, green otherwise.
  bool get hasError => !_offline && _lastError != null;

  void updateHost(String host) {
    if (host == _host) return;
    _host = host;
    notifyListeners();
  }

  void markOnline() {
    final changed = _offline || _lastError != null;
    _offline = false;
    _lastError = null;
    if (changed) notifyListeners();
  }

  void markOffline() {
    if (_offline) return;
    _offline = true;
    notifyListeners();
  }

  void markFailure(String message) {
    if (_offline) return;
    if (_lastError == message) return;
    _lastError = message;
    notifyListeners();
  }
}
