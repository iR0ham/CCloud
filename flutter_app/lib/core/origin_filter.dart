import 'models.dart';

/// Regional visibility rules from the macOS app (`Sources/UI/Browse/MediaFilters.swift`).
///
/// The catalogue files a title under both a country and a dedicated genre, so a
/// title is hidden when either list matches. The same rules drive the country
/// and category grids — except Live TV, which is deliberately outside them.
class OriginFilter {
  static const Set<String> countryTitles = {
    'چین',
    'کره جنوبی',
    'ترکیه',
    'هند',
    'تایلند',
    'ژاپن',
    'پاکستان',
    'افغانستان',
    'مصر',
    'اردن',
    'امارات',
    'تونس',
    'سوریه',
    'عراق',
    'عربستان',
    'قطر',
    'کویت',
    'لبنان',
    'مراکش',
  };

  static const Set<String> genreTitles = {
    'چینی',
    'کره ای',
    'ترکی',
    'هندی',
    'ژاپنی',
    'چینی ژاپنی',
  };

  static bool hides(MediaItem item) =>
      hidesCountries(item.countries) ||
      item.genres.any((genre) => hidesGenre(genre.title));

  static bool hidesCountries(List<Country> countries) =>
      countries.any(hidesCountry);

  static bool hidesCountry(Country country) =>
      countryTitles.contains(normalize(country.title));

  static bool hidesGenre(String title) =>
      genreTitles.contains(normalize(title));

  /// Anime is Japanese animation. The combined «انیمیشن + انیمه» genre also
  /// covers Western cartoons, so the country check keeps those visible.
  static bool hidesAnime(MediaItem item) =>
      hidesAnimeValues(countries: item.countries, genres: item.genres);

  static bool hidesAnimeValues({
    required List<Country> countries,
    required List<Genre> genres,
  }) {
    final isJapanese = countries.any(
      (country) => normalize(country.title) == 'ژاپن',
    );
    if (!isJapanese) return false;
    return genres.any((genre) => normalize(genre.title).contains('انیمه'));
  }

  /// Country and genre titles arrive with either a space or a ZWNJ between the
  /// words; bidi marks can also precede them.
  static String normalize(String title) => title
      .replaceAll('\u200C', ' ')
      .replaceAll('\u200E', '')
      .replaceAll('\u200F', '')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
}

/// Combines the two Settings toggles into one predicate, the Flutter
/// counterpart of the macOS `ContentHiding` model.
class ContentHiding {
  const ContentHiding({this.origins = false, this.anime = false});

  final bool origins;
  final bool anime;

  bool get isActive => origins || anime;

  bool isHidden(MediaItem item) =>
      (origins && OriginFilter.hides(item)) ||
      (anime && OriginFilter.hidesAnime(item));

  bool hidesCountry(Country country) =>
      origins && OriginFilter.hidesCountry(country);

  bool hidesGenre(String title) => origins && OriginFilter.hidesGenre(title);
}
