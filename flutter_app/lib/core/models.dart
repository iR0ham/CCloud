import 'dart:math' as math;

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String _asString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

String? _asNullableString(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
    return trimmed;
  }
  return value.toString();
}

class Genre {
  const Genre({required this.id, required this.title});

  final int id;
  final String title;

  factory Genre.fromJson(Map<String, dynamic> json) =>
      Genre(id: _asInt(json['id']), title: _asString(json['title']));

  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}

class Country {
  const Country({required this.id, required this.title, required this.image});

  final int id;
  final String title;
  final String image;

  factory Country.fromJson(Map<String, dynamic> json) => Country(
        id: _asInt(json['id']),
        title: _asString(json['title']),
        image: _asString(json['image']),
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'image': image};
}

class MediaSource {
  const MediaSource({
    required this.id,
    required this.quality,
    required this.type,
    required this.url,
  });

  final int id;
  final String? quality;
  final String type;
  final String url;

  /// Normalised type: mkv, hls, dash, mp4 …
  String get kind {
    final t = type.toLowerCase();
    if (t.contains('mkv') || t.contains('matroska')) return 'mkv';
    if (t.contains('m3u8') || t.contains('hls')) return 'hls';
    if (t.contains('mpd') || t.contains('dash')) return 'dash';
    if (t.contains('mp4') || t.contains('m4v')) return 'mp4';
    return t;
  }

  bool get isTrailer => qualityLabel.contains('تیزر');

  String get qualityLabel {
    final q = quality?.trim();
    if (q != null && q.isNotEmpty && q != 'null') return q;
    return kindLabel;
  }

  String get kindLabel {
    switch (kind) {
      case 'mkv':
        return 'MKV';
      case 'mp4':
        return 'MP4';
      case 'hls':
        return 'HLS';
      case 'dash':
        return 'DASH';
      default:
        return kind.toUpperCase();
    }
  }

  /// "720p" out of "720 زیرنویس".
  String? get resolutionLabel {
    final q = quality;
    if (q == null) return null;
    final match = RegExp(r'[0-9]{3,4}').firstMatch(q);
    if (match == null) return null;
    final digits = match.group(0)!;
    if (digits.length == 3) return '${digits}p';
    return '${digits.substring(0, 3)}p';
  }

  factory MediaSource.fromJson(Map<String, dynamic> json) => MediaSource(
        id: _asInt(json['id']),
        quality: _asNullableString(json['quality']),
        type: _asString(json['type']),
        url: _asString(json['url']),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'quality': quality, 'type': type, 'url': url};
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.year,
    required this.imdb,
    required this.rating,
    required this.duration,
    required this.image,
    required this.cover,
    required this.genres,
    required this.sources,
    required this.countries,
  });

  final int id;
  final String type;
  final String title;
  final String description;
  final int year;
  final double imdb;
  final double rating;
  final String? duration;
  final String image;
  final String cover;
  final List<Genre> genres;
  final List<MediaSource> sources;
  final List<Country> countries;

  bool get isSeries {
    final t = type.toLowerCase();
    return t == 'serie' || t == 'series';
  }

  String get yearText => year > 0 ? '$year' : '';

  String get imdbText => imdb > 0 ? imdb.toStringAsFixed(1) : '';

  String? get durationText {
    final d = duration;
    if (d == null || d.isEmpty) return null;
    return d;
  }

  String get genreText => genres.map((g) => g.title).join(' • ');

  List<MediaSource> get playableSources =>
      sources.where((s) => s.url.isNotEmpty && !s.isTrailer).toList();

  bool get hasOnlyTrailer =>
      sources.isNotEmpty && sources.every((s) => s.isTrailer);

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final genresJson = json['genres'];
    final sourcesJson = json['sources'];
    final countriesJson = json['country'] ?? json['countries'];
    return MediaItem(
      id: _asInt(json['id']),
      type: _asString(json['type']).isEmpty ? 'movie' : _asString(json['type']),
      title: _asString(json['title']),
      description: _asString(json['description']),
      year: _asInt(json['year']),
      imdb: _asDouble(json['imdb']),
      rating: _asDouble(json['rating']),
      duration: _asNullableString(json['duration']),
      image: _asString(json['image']),
      cover: _asString(json['cover']),
      genres: genresJson is List
          ? genresJson
              .whereType<Map>()
              .map((e) => Genre.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      sources: sourcesJson is List
          ? sourcesJson
              .whereType<Map>()
              .map((e) => MediaSource.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      countries: countriesJson is List
          ? countriesJson
              .whereType<Map>()
              .map((e) => Country.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'description': description,
        'year': year,
        'imdb': imdb,
        'rating': rating,
        'duration': duration,
        'image': image,
        'cover': cover,
        'genres': genres.map((g) => g.toJson()).toList(),
        'sources': sources.map((s) => s.toJson()).toList(),
        'country': countries.map((c) => c.toJson()).toList(),
      };
}

class Season {
  const Season({required this.id, required this.title, required this.episodes});

  final int id;
  final String title;
  final List<Episode> episodes;

  factory Season.fromJson(Map<String, dynamic> json) {
    final raw = json['episodes'];
    return Season(
      id: _asInt(json['id']),
      title: _asString(json['title']),
      episodes: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Episode.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.description,
    required this.duration,
    required this.image,
    required this.sources,
  });

  final int id;
  final String title;
  final String? description;
  final String? duration;
  final String? image;
  final List<MediaSource> sources;

  int? get episodeNumber {
    final digits = title.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  List<MediaSource> get playableSources =>
      sources.where((s) => s.url.isNotEmpty && !s.isTrailer).toList();

  factory Episode.fromJson(Map<String, dynamic> json) {
    final raw = json['sources'];
    return Episode(
      id: _asInt(json['id']),
      title: _asString(json['title']),
      description: _asNullableString(json['description']),
      duration: _asNullableString(json['duration']),
      image: _asNullableString(json['image']),
      sources: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => MediaSource.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

enum SortOption {
  newest('created', 'جدیدترین'),
  year('year', 'سال ساخت'),
  imdb('imdb', 'امتیاز IMDb');

  const SortOption(this.apiPath, this.title);

  final String apiPath;
  final String title;
}

// MARK: - Live TV dataset

class LiveTvCountry {
  const LiveTvCountry({
    required this.code,
    required this.englishName,
    required this.channelCount,
  });

  final String code;
  final String englishName;
  final int channelCount;

  String get persianName => persianLiveCountryNames[code] ?? englishName;

  String get flag {
    const aliases = {'UK': 'GB', 'EL': 'GR'};
    final normalized = aliases[code.toUpperCase()] ?? code.toUpperCase();
    if (normalized.length != 2) return '🏳️';
    final base = 0x1F1E6;
    final buffer = StringBuffer();
    for (final unit in normalized.codeUnits) {
      if (unit < 65 || unit > 90) return '🏳️';
      buffer.writeCharCode(base + unit - 65);
    }
    return buffer.toString();
  }
}

class LiveTvChannel {
  const LiveTvChannel({
    required this.nanoid,
    required this.name,
    required this.streams,
    required this.languages,
    required this.country,
    required this.isGeoBlocked,
  });

  final String nanoid;
  final String name;
  final List<String> streams;
  final List<String> languages;
  final String country;
  final bool isGeoBlocked;

  String get stringId => nanoid.isNotEmpty ? nanoid : '$name-$country';

  String get primaryStream {
    for (final url in streams) {
      if (url.toLowerCase().contains('.m3u8')) return url;
    }
    return streams.isEmpty ? '' : streams.first;
  }

  String get languageLabel {
    final names =
        languages.map(persianLiveLanguage).where((e) => e.isNotEmpty).toList();
    return names.isEmpty ? 'نامشخص' : names.join('، ');
  }

  factory LiveTvChannel.fromJson(Map<String, dynamic> json) {
    final sources = json['sources'];
    var urls = <String>[];
    if (sources is Map && sources['streams'] is List) {
      urls = (sources['streams'] as List)
          .map((e) => _asString(e).trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final languages = json['languages'];
    return LiveTvChannel(
      nanoid: _asString(json['nanoid']),
      name: _asString(json['name']),
      streams: urls,
      languages: languages is List
          ? languages.map((e) => _asString(e)).toList()
          : const [],
      country: _asString(json['country']),
      isGeoBlocked: json['isGeoBlocked'] == true,
    );
  }
}

String persianLiveLanguage(String code) {
  switch (code.toLowerCase()) {
    case 'fas':
    case 'fa':
      return 'فارسی';
    case 'kur':
    case 'ckb':
      return 'کردی';
    case 'ara':
    case 'ar':
      return 'عربی';
    case 'eng':
    case 'en':
      return 'انگلیسی';
    case 'tur':
    case 'tr':
      return 'ترکی';
    case 'aze':
    case 'az':
      return 'آذری';
    case 'pus':
    case 'ps':
      return 'پشتو';
    case 'urd':
    case 'ur':
      return 'اردو';
    case 'rus':
    case 'ru':
      return 'روسی';
    case 'deu':
    case 'ger':
    case 'de':
      return 'آلمانی';
    case 'fra':
    case 'fre':
    case 'fr':
      return 'فرانسوی';
    case 'spa':
    case 'es':
      return 'اسپانیایی';
    case 'ita':
    case 'it':
      return 'ایتالیایی';
    case 'por':
    case 'pt':
      return 'پرتغالی';
    case 'hin':
    case 'hi':
      return 'هندی';
    case 'zho':
    case 'chi':
    case 'zh':
      return 'چینی';
    case 'jpn':
    case 'ja':
      return 'ژاپنی';
    case 'kor':
    case 'ko':
      return 'کره‌ای';
    case 'ben':
    case 'bn':
      return 'بنگالی';
    case 'heb':
    case 'he':
      return 'عبری';
    default:
      return code;
  }
}

const Map<String, String> persianLiveCountryNames = {
  'IR': 'ایران', 'AF': 'افغانستان', 'TJ': 'تاجیکستان', 'US': 'امریکا',
  'GB': 'انگلستان', 'UK': 'انگلستان', 'DE': 'آلمان', 'TR': 'ترکیه',
  'IQ': 'عراق', 'AE': 'امارات', 'SA': 'عربستان', 'QA': 'قطر', 'KW': 'کویت',
  'OM': 'عمان', 'BH': 'بحرین', 'YE': 'یمن', 'SY': 'سوریه', 'LB': 'لبنان',
  'JO': 'اردن', 'PS': 'فلسطین', 'EG': 'مصر', 'LY': 'لیبی', 'TN': 'تونس',
  'DZ': 'الجزایر', 'MA': 'مراکش', 'SD': 'سودان', 'SO': 'سومالی',
  'IN': 'هند', 'PK': 'پاکستان', 'BD': 'بنگلادش', 'LK': 'سریلانکا',
  'NP': 'نپال', 'CN': 'چین', 'JP': 'ژاپن', 'KR': 'کره جنوبی',
  'KP': 'کره شمالی', 'TW': 'تایوان', 'HK': 'هنگ‌کنگ', 'TH': 'تایلند',
  'VN': 'ویتنام', 'ID': 'اندونزی', 'MY': 'مالزی', 'SG': 'سنگاپور',
  'PH': 'فیلیپین', 'MM': 'میانمار', 'KH': 'کامبوج', 'LA': 'لائوس',
  'MN': 'مغولستان', 'KZ': 'قزاقستان', 'UZ': 'ازبکستان', 'TM': 'ترکمنستان',
  'KG': 'قرقیزستان', 'AZ': 'آذربایجان', 'AM': 'ارمنستان', 'GE': 'گرجستان',
  'RU': 'روسیه', 'UA': 'اوکراین', 'BY': 'بلاروس', 'PL': 'لهستان',
  'CZ': 'چک', 'SK': 'اسلواکی', 'HU': 'مجارستان', 'RO': 'رومانی',
  'BG': 'بلغارستان', 'RS': 'صربستان', 'HR': 'کرواسی', 'SI': 'اسلوونی',
  'BA': 'بوسنی', 'ME': 'مونته‌نگرو', 'MK': 'مقدونیه', 'AL': 'آلبانی',
  'GR': 'یونان', 'IT': 'ایتالیا', 'ES': 'اسپانیا', 'PT': 'پرتغال',
  'FR': 'فرانسه', 'BE': 'بلژیک', 'NL': 'هلند', 'LU': 'لوکزامبورگ',
  'CH': 'سوئیس', 'AT': 'اتریش', 'DK': 'دانمارک', 'SE': 'سوئد',
  'NO': 'نروژ', 'FI': 'فنلاند', 'IS': 'ایسلند', 'IE': 'ایرلند',
  'EE': 'استونی', 'LV': 'لتونی', 'LT': 'لیتوانی', 'MD': 'مولداوی',
  'CA': 'کانادا', 'MX': 'مکزیک', 'BR': 'برزیل', 'AR': 'آرژانتین',
  'CL': 'شیلی', 'PE': 'پرو', 'CO': 'کلمبیا', 'VE': 'ونزوئلا',
  'EC': 'اکوادور', 'BO': 'بولیوی', 'PY': 'پاراگوئه', 'UY': 'اروگوئه',
  'CR': 'کاستاریکا', 'PA': 'پاناما', 'GT': 'گواتمالا', 'HN': 'هندوراس',
  'SV': 'السالوادور', 'NI': 'نیکاراگوئه', 'CU': 'کوبا', 'DO': 'دومینیکن',
  'HT': 'هائیتی', 'JM': 'جامائیکا', 'AU': 'استرالیا', 'NZ': 'نیوزیلند',
  'ZA': 'آفریقای جنوبی', 'NG': 'نیجریه', 'KE': 'کنیا', 'ET': 'اتیوپی',
  'GH': 'غنا', 'SN': 'سنگال', 'CI': 'ساحل عاج', 'CM': 'کامرون',
  'UG': 'اوگاندا', 'TZ': 'تانزانیا', 'MZ': 'موزامبیک', 'ZW': 'زیمبابوه',
  'AO': 'آنگولا', 'ZM': 'زامبیا', 'BW': 'بوتسوانا', 'MU': 'موریس',
  'ML': 'مالی', 'BF': 'بورکینافاسو', 'NE': 'نیجر', 'TD': 'چاد',
  'MR': 'موریتانی', 'GM': 'گامبیا', 'GN': 'گینه', 'BJ': 'بنین',
  'TG': 'توگو', 'SL': 'سیرالئون', 'LR': 'لیبریا', 'RW': 'رواندا',
  'BI': 'بوروندی', 'MG': 'ماداگاسکار', 'MW': 'مالاوی', 'NA': 'نامیبیا',
  'LS': 'لسوتو', 'SZ': 'اسواتینی', 'CD': 'کنگو', 'CG': 'کنگو برازاویل',
  'GA': 'گابن', 'GQ': 'گینه استوایی', 'CF': 'آفریقای مرکزی', 'SS': 'سودان جنوبی',
};

/// Persian digits for counts and numbers.
String faDigits(Object value) {
  const digits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  return value.toString().split('').map((ch) {
    final index = int.tryParse(ch);
    return index == null ? ch : digits[index];
  }).join();
}

/// Same ordering as the macOS app: Iran first, then neighbours, then by channel count.
List<LiveTvCountry> sortLiveCountries(List<LiveTvCountry> items) {
  int rank(String code) {
    switch (code) {
      case 'IR':
        return 0;
      case 'AF':
        return 1;
      case 'TJ':
        return 2;
      default:
        return 3;
    }
  }

  final sorted = List<LiveTvCountry>.of(items);
  sorted.sort((a, b) {
    final l = rank(a.code), r = rank(b.code);
    if (l != r) return l.compareTo(r);
    if (a.channelCount != b.channelCount) {
      return b.channelCount.compareTo(a.channelCount);
    }
    return a.persianName.compareTo(b.persianName);
  });
  return sorted;
}

/// Best source for the quality preference (auto → 1080 → 720 → 480 → first).
MediaSource? preferredSource(List<MediaSource> sources, String preference) {
  final list = sources.where((s) => s.url.isNotEmpty && !s.isTrailer).toList();
  if (list.isEmpty) return null;
  final pref = preference == 'auto' ? '' : preference;
  if (pref.isNotEmpty) {
    for (final source in list) {
      if ((source.resolutionLabel ?? '').startsWith(pref)) return source;
    }
  }
  for (final want in ['1080p', '720p', '480p']) {
    for (final source in list) {
      if (source.resolutionLabel == want) return source;
    }
  }
  return list.first;
}

/// Stable mix of movies/series for the home hero (alternating, max 6).
List<MediaItem> mixHeroSlides(List<MediaItem> movies, List<MediaItem> series) {
  final m = movies.take(3).toList();
  final s = series.take(3).toList();
  final mixed = <MediaItem>[];
  for (var i = 0; i < math.max(m.length, s.length); i++) {
    if (i < m.length) mixed.add(m[i]);
    if (i < s.length) mixed.add(s[i]);
  }
  return mixed.take(6).toList();
}
