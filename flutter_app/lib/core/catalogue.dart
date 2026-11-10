import 'api_client.dart';
import 'models.dart';

/// Small in-memory cache for the genre list (used by home, browse and categories).
class Catalogue {
  static List<Genre>? _genres;
  static Future<List<Genre>>? _inFlight;

  static List<Genre>? get cachedGenres => _genres;

  static Future<List<Genre>> genres() {
    final cached = _genres;
    if (cached != null && cached.isNotEmpty) return Future.value(cached);
    final running = _inFlight;
    if (running != null) return running;
    final future = ApiClient.instance.genres();
    _inFlight = future;
    return future.then((items) {
      if (items.isNotEmpty) _genres = items;
      _inFlight = null;
      return items;
    }).catchError((Object error) {
      _inFlight = null;
      throw error;
    });
  }

  static void invalidate() {
    _genres = null;
    _inFlight = null;
  }
}
