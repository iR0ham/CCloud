import 'models.dart';

/// Regional visibility rules from the macOS app. Applied to the Movies and Series
/// feeds only; every other screen keeps showing everything.
class OriginFilter {
  static const Set<String> _countryTitles = {
    'چین', 'کره جنوبی', 'ترکیه', 'هند', 'تایلند', 'ژاپن', 'پاکستان',
    'مصر', 'اردن', 'امارات', 'تونس', 'سوریه', 'عراق', 'عربستان',
    'قطر', 'کویت', 'لبنان', 'مراکش',
  };

  static const Set<String> _genreTitles = {
    'چینی', 'کره ای', 'ترکی', 'هندی', 'ژاپنی', 'چینی ژاپنی',
  };

  static bool hides(MediaItem item) =>
      item.countries.any((country) => _countryTitles.contains(_normalize(country.title))) ||
      item.genres.any((genre) => _genreTitles.contains(_normalize(genre.title)));

  static bool hidesAnime(MediaItem item) {
    final isJapanese = item.countries.any((c) => _normalize(c.title) == 'ژاپن');
    if (!isJapanese) return false;
    return item.genres.any((g) => _normalize(g.title).contains('انیمه'));
  }

  static String _normalize(String title) => title
      .replaceAll('\u200C', ' ')
      .replaceAll('\u200E', '')
      .replaceAll('\u200F', '')
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .join(' ');
}
