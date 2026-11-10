import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum AppAppearance {
  system('هماهنگ با سیستم'),
  dark('تیره'),
  light('روشن');

  const AppAppearance(this.title);

  final String title;
}

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs) {
    final rawAppearance = _prefs.getString('ccloud.appearance');
    appearance = AppAppearance.values.firstWhere(
      (value) => value.name == rawAppearance,
      orElse: () => AppAppearance.dark,
    );
    fontScale = (_prefs.getDouble('ccloud.fontScale') ?? 1.0).clamp(0.85, 1.3);
    preferredQuality = _prefs.getString('ccloud.preferredQuality') ?? 'auto';
    autoPlayBest = _prefs.getBool('ccloud.autoPlayBest') ?? true;
    autoPlayNextEpisode = _prefs.getBool('ccloud.autoPlayNextEpisode') ?? true;
    hideRegionalOrigins = _prefs.getBool('ccloud.hideRegionalOrigins') ?? false;
    hideAnime = _prefs.getBool('ccloud.hideAnime') ?? false;
  }

  final SharedPreferences _prefs;

  late AppAppearance appearance;
  late double fontScale;
  late String preferredQuality;
  late bool autoPlayBest;
  late bool autoPlayNextEpisode;
  late bool hideRegionalOrigins;
  late bool hideAnime;

  Future<void> setAppearance(AppAppearance value) async {
    appearance = value;
    notifyListeners();
    await _prefs.setString('ccloud.appearance', value.name);
  }

  Future<void> setFontScale(double value) async {
    fontScale = value.clamp(0.85, 1.3);
    notifyListeners();
    await _prefs.setDouble('ccloud.fontScale', fontScale);
  }

  Future<void> setPreferredQuality(String value) async {
    preferredQuality = value;
    notifyListeners();
    await _prefs.setString('ccloud.preferredQuality', value);
  }

  Future<void> setAutoPlayBest(bool value) async {
    autoPlayBest = value;
    notifyListeners();
    await _prefs.setBool('ccloud.autoPlayBest', value);
  }

  Future<void> setAutoPlayNextEpisode(bool value) async {
    autoPlayNextEpisode = value;
    notifyListeners();
    await _prefs.setBool('ccloud.autoPlayNextEpisode', value);
  }

  Future<void> setHideRegionalOrigins(bool value) async {
    hideRegionalOrigins = value;
    notifyListeners();
    await _prefs.setBool('ccloud.hideRegionalOrigins', value);
  }

  Future<void> setHideAnime(bool value) async {
    hideAnime = value;
    notifyListeners();
    await _prefs.setBool('ccloud.hideAnime', value);
  }

  Future<void> reset() async {
    appearance = AppAppearance.dark;
    fontScale = 1.0;
    preferredQuality = 'auto';
    autoPlayBest = true;
    autoPlayNextEpisode = true;
    hideRegionalOrigins = false;
    hideAnime = false;
    notifyListeners();
    await Future.wait([
      _prefs.setString('ccloud.appearance', appearance.name),
      _prefs.setDouble('ccloud.fontScale', fontScale),
      _prefs.setString('ccloud.preferredQuality', preferredQuality),
      _prefs.setBool('ccloud.autoPlayBest', autoPlayBest),
      _prefs.setBool('ccloud.autoPlayNextEpisode', autoPlayNextEpisode),
      _prefs.setBool('ccloud.hideRegionalOrigins', hideRegionalOrigins),
      _prefs.setBool('ccloud.hideAnime', hideAnime),
    ]);
  }

  static const qualityOptions = [
    ('auto', 'خودکار (بهترین)'),
    ('1080', '۱۰۸۰p'),
    ('720', '۷۲۰p'),
    ('480', '۴۸۰p'),
  ];
}

class FavoriteEntry {
  FavoriteEntry({required this.item, required this.addedAt});

  final MediaItem item;
  final DateTime addedAt;

  bool get isSeries => item.isSeries;

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) => FavoriteEntry(
    item: MediaItem.fromJson((json['item'] as Map).cast<String, dynamic>()),
    addedAt:
        DateTime.tryParse(json['addedAt']?.toString() ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'addedAt': addedAt.toIso8601String(),
  };
}

class FavoritesStore extends ChangeNotifier {
  FavoritesStore(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;
  final List<FavoriteEntry> _entries = [];

  List<FavoriteEntry> get entries => List.unmodifiable(_entries);
  List<FavoriteEntry> get movies => _entries.where((e) => !e.isSeries).toList();
  List<FavoriteEntry> get series => _entries.where((e) => e.isSeries).toList();

  bool isFavorite(MediaItem item) => _entries.any(
    (entry) => entry.item.id == item.id && entry.item.isSeries == item.isSeries,
  );

  /// Returns true when the item was added.
  Future<bool> toggle(MediaItem item) async {
    final index = _entries.indexWhere(
      (entry) =>
          entry.item.id == item.id && entry.item.isSeries == item.isSeries,
    );
    final added = index < 0;
    if (added) {
      _entries.insert(0, FavoriteEntry(item: item, addedAt: DateTime.now()));
    } else {
      _entries.removeAt(index);
    }
    notifyListeners();
    await _save();
    return added;
  }

  Future<void> remove(MediaItem item) async {
    _entries.removeWhere(
      (entry) =>
          entry.item.id == item.id && entry.item.isSeries == item.isSeries,
    );
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _save();
  }

  void _load() {
    final raw = _prefs.getStringList('ccloud.favorites') ?? const [];
    for (final line in raw) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          _entries.add(FavoriteEntry.fromJson(decoded.cast<String, dynamic>()));
        }
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    await _prefs.setStringList(
      'ccloud.favorites',
      _entries.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }
}

class WatchedEpisode {
  const WatchedEpisode({
    required this.id,
    required this.seasonTitle,
    required this.label,
    required this.watchedAt,
    required this.progress,
  });

  final int id;
  final String seasonTitle;
  final String label;
  final DateTime watchedAt;
  final double progress;

  factory WatchedEpisode.fromJson(Map<String, dynamic> json) => WatchedEpisode(
    id: (json['id'] as num?)?.toInt() ?? 0,
    seasonTitle: json['seasonTitle']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    watchedAt:
        DateTime.tryParse(json['watchedAt']?.toString() ?? '') ??
        DateTime.now(),
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'seasonTitle': seasonTitle,
    'label': label,
    'watchedAt': watchedAt.toIso8601String(),
    'progress': progress,
  };
}

class HistoryEntry {
  HistoryEntry({
    required this.item,
    required this.lastWatchedAt,
    required this.progress,
    required this.episodes,
  });

  final MediaItem item;
  DateTime lastWatchedAt;
  double progress;
  final List<WatchedEpisode> episodes;

  WatchedEpisode? get lastEpisode {
    if (episodes.isEmpty) return null;
    return episodes.reduce((a, b) => a.watchedAt.isAfter(b.watchedAt) ? a : b);
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    item: MediaItem.fromJson((json['item'] as Map).cast<String, dynamic>()),
    lastWatchedAt:
        DateTime.tryParse(json['lastWatchedAt']?.toString() ?? '') ??
        DateTime.now(),
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    episodes: (json['episodes'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => WatchedEpisode.fromJson(e.cast<String, dynamic>()))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'lastWatchedAt': lastWatchedAt.toIso8601String(),
    'progress': progress,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
}

class HistoryStore extends ChangeNotifier {
  HistoryStore(this._prefs) {
    _load();
  }

  static const int maxEntries = 80;

  final SharedPreferences _prefs;
  final List<HistoryEntry> _entries = [];

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> record(
    MediaItem item, {
    double? progress,
    int? episodeId,
    String? seasonTitle,
    String? episodeLabel,
  }) async {
    if (item.id == 0) return;
    final now = DateTime.now();
    final index = _entries.indexWhere(
      (entry) =>
          entry.item.id == item.id && entry.item.isSeries == item.isSeries,
    );
    if (index >= 0) {
      final entry = _entries[index];
      entry.lastWatchedAt = now;
      if (progress != null) entry.progress = progress.clamp(0, 1);
      if (item.isSeries && episodeId != null) {
        final epIndex = entry.episodes.indexWhere((ep) => ep.id == episodeId);
        if (epIndex >= 0) {
          final old = entry.episodes[epIndex];
          entry.episodes[epIndex] = WatchedEpisode(
            id: old.id,
            seasonTitle: seasonTitle ?? old.seasonTitle,
            label: episodeLabel ?? old.label,
            watchedAt: now,
            progress: progress?.clamp(0, 1) ?? old.progress,
          );
        } else {
          entry.episodes.add(
            WatchedEpisode(
              id: episodeId,
              seasonTitle: seasonTitle ?? '',
              label: episodeLabel ?? '',
              watchedAt: now,
              progress: progress?.clamp(0, 1) ?? 0,
            ),
          );
        }
      }
      _entries.removeAt(index);
      _entries.insert(0, entry);
    } else {
      _entries.insert(
        0,
        HistoryEntry(
          item: item,
          lastWatchedAt: now,
          progress: progress?.clamp(0, 1) ?? 0,
          episodes: item.isSeries && episodeId != null
              ? [
                  WatchedEpisode(
                    id: episodeId,
                    seasonTitle: seasonTitle ?? '',
                    label: episodeLabel ?? '',
                    watchedAt: now,
                    progress: progress?.clamp(0, 1) ?? 0,
                  ),
                ]
              : [],
        ),
      );
    }
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    await _save();
  }

  HistoryEntry? entryFor(MediaItem item) {
    for (final entry in _entries) {
      if (entry.item.id == item.id && entry.item.isSeries == item.isSeries) {
        return entry;
      }
    }
    return null;
  }

  Set<int> watchedEpisodeIds(int seriesId) {
    for (final entry in _entries) {
      if (entry.item.isSeries && entry.item.id == seriesId) {
        return entry.episodes.map((e) => e.id).toSet();
      }
    }
    return const {};
  }

  Future<void> remove(MediaItem item) async {
    _entries.removeWhere(
      (entry) =>
          entry.item.id == item.id && entry.item.isSeries == item.isSeries,
    );
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _save();
  }

  void _load() {
    final raw = _prefs.getStringList('ccloud.history') ?? const [];
    for (final line in raw) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          _entries.add(HistoryEntry.fromJson(decoded.cast<String, dynamic>()));
        }
      } catch (_) {}
    }
    _entries.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
  }

  Future<void> _save() async {
    await _prefs.setStringList(
      'ccloud.history',
      _entries.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }
}

/// Global service locator, initialised in `main()`.
class AppServices {
  static late final AppServices instance;

  final AppSettings settings;
  final FavoritesStore favorites;
  final HistoryStore history;

  AppServices._create(this.settings, this.favorites, this.history);

  static void init(SharedPreferences prefs) {
    instance = AppServices._create(
      AppSettings(prefs),
      FavoritesStore(prefs),
      HistoryStore(prefs),
    );
  }
}
