import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key used by the macOS app (`SearchView`/`SearchModel`).
const String recentSearchesKey = 'ccloud.recentSearchQueries';

/// The macOS app keeps the eight most recent explicit searches.
const int maxRecentSearches = 8;

/// Insert [term] at the front, dropping a case-insensitive duplicate and
/// truncating to [maxRecentSearches]. Blank terms are ignored.
List<String> addRecentSearch(List<String> current, String term) {
  final trimmed = term.trim();
  if (trimmed.isEmpty) return List<String>.of(current);
  final lowered = trimmed.toLowerCase();
  final updated = <String>[
    trimmed,
    ...current.where((entry) => entry.trim().toLowerCase() != lowered),
  ];
  if (updated.length > maxRecentSearches) {
    return updated.sublist(0, maxRecentSearches);
  }
  return updated;
}

/// Persists the recent-query chips. Only deliberate searches (Enter, the
/// search glyph, or a recent chip) call [record]; the debounced auto-search
/// must not fill this list.
class RecentSearchesStore extends ChangeNotifier {
  RecentSearchesStore(this._prefs)
    : _terms = List<String>.of(
        _prefs.getStringList(recentSearchesKey) ?? const [],
      );

  final SharedPreferences _prefs;
  List<String> _terms;

  List<String> get terms => List.unmodifiable(_terms);

  Future<void> record(String term) async {
    final updated = addRecentSearch(_terms, term);
    if (listEquals(updated, _terms)) return;
    _terms = updated;
    notifyListeners();
    await _prefs.setStringList(recentSearchesKey, _terms);
  }

  Future<void> clear() async {
    if (_terms.isEmpty) return;
    _terms = const [];
    notifyListeners();
    await _prefs.remove(recentSearchesKey);
  }
}
