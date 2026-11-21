import 'models.dart';

/// Movie/series discriminator used by the shared filters.
enum MediaKind { movie, series }

/// One removable criterion in the active-filter chip row.
enum MediaFilterFacet { kind, year, imdb }

/// The backend has no year/IMDb parameters, so filters run over loaded pages.
/// These limits mirror the macOS `scanFeed` / `scanFeedForMore` helpers.
const int filterScanMinimumMatches = 12;
const int filterScanMaxPages = 10;
const int filterScanMoreMaxPages = 4;

/// The catalogue rounds IMDb ratings down; a 7.0 title still matches a 7+ chip.
const double filterImdbTolerance = 0.049;

/// Multi-criteria filters from `Sources/UI/Browse/MediaFilters.swift`.
class MediaFilters {
  const MediaFilters({this.kind, this.yearFrom, this.yearTo, this.minIMDb});

  final MediaKind? kind;
  final int? yearFrom;
  final int? yearTo;
  final double? minIMDb;

  bool get isActive =>
      kind != null || yearFrom != null || yearTo != null || minIMDb != null;

  /// The year range counts as one active criterion, like the macOS badge.
  int get activeCount {
    var count = 0;
    if (kind != null) count += 1;
    if (yearFrom != null || yearTo != null) count += 1;
    if (minIMDb != null) count += 1;
    return count;
  }

  bool matches(MediaItem item) =>
      matchesValues(year: item.year, imdb: item.imdb, isSeries: item.isSeries);

  /// Truth table shared with the macOS `matches(year:imdb:isSeries:)`:
  /// * a set kind must equal the item kind,
  /// * a year range rejects unknown years (`year <= 0`) and is inclusive,
  /// * a minimum IMDb rejects unrated titles (`imdb <= 0`) and keeps the
  ///   0.049 tolerance so 7.0 satisfies the 7+ chip.
  bool matchesValues({
    required int year,
    required double imdb,
    required bool isSeries,
  }) {
    if (kind != null) {
      final itemKind = isSeries ? MediaKind.series : MediaKind.movie;
      if (itemKind != kind) return false;
    }
    if (yearFrom != null || yearTo != null) {
      if (year <= 0) return false;
      if (yearFrom != null && year < yearFrom!) return false;
      if (yearTo != null && year > yearTo!) return false;
    }
    if (minIMDb != null) {
      if (imdb <= 0) return false;
      if (imdb + filterImdbTolerance < minIMDb!) return false;
    }
    return true;
  }

  MediaFilters withYearFrom(int? value) {
    var nextTo = yearTo;
    if (value != null && nextTo != null && nextTo < value) {
      nextTo = value;
    }
    return MediaFilters(
      kind: kind,
      yearFrom: value,
      yearTo: nextTo,
      minIMDb: minIMDb,
    );
  }

  MediaFilters withYearTo(int? value) {
    var nextFrom = yearFrom;
    if (value != null && nextFrom != null && nextFrom > value) {
      nextFrom = value;
    }
    return MediaFilters(
      kind: kind,
      yearFrom: nextFrom,
      yearTo: value,
      minIMDb: minIMDb,
    );
  }

  MediaFilters withKind(MediaKind? value) => MediaFilters(
    kind: value,
    yearFrom: yearFrom,
    yearTo: yearTo,
    minIMDb: minIMDb,
  );

  MediaFilters withMinImdb(double? value) => MediaFilters(
    kind: kind,
    yearFrom: yearFrom,
    yearTo: yearTo,
    minIMDb: value,
  );

  /// Removes one facet; the year facet clears both ends together.
  MediaFilters without(MediaFilterFacet facet) => switch (facet) {
    MediaFilterFacet.kind => withKind(null),
    MediaFilterFacet.year => MediaFilters(kind: kind, minIMDb: minIMDb),
    MediaFilterFacet.imdb => withMinImdb(null),
  };

  /// Label shown on the removable chip, or null when the facet is inactive.
  String? facetLabel(MediaFilterFacet facet) => switch (facet) {
    MediaFilterFacet.kind => switch (kind) {
      MediaKind.movie => 'فیلم',
      MediaKind.series => 'سریال',
      null => null,
    },
    MediaFilterFacet.year => switch ((yearFrom, yearTo)) {
      (final from?, final to?) => from == to ? 'سال $from' : '$from تا $to',
      (final from?, null) => 'از $from',
      (null, final to?) => 'تا $to',
      _ => null,
    },
    MediaFilterFacet.imdb =>
      minIMDb == null ? null : 'IMDb ${formatImdbThreshold(minIMDb!)}+',
  };

  @override
  bool operator ==(Object other) =>
      other is MediaFilters &&
      other.kind == kind &&
      other.yearFrom == yearFrom &&
      other.yearTo == yearTo &&
      other.minIMDb == minIMDb;

  @override
  int get hashCode => Object.hash(kind, yearFrom, yearTo, minIMDb);
}

/// `String(format: "%g+")` equivalent: 6.0 → "6", 7.5 → "7.5".
String formatImdbThreshold(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  final text = value.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Years offered by the «از»/«تا» menus: next year down to 1950.
List<int> filterYearChoices({int? currentYear}) {
  final current = currentYear ?? DateTime.now().year;
  return [for (var year = current + 1; year >= 1950; year--) year];
}

/// Keeps pulling pages until at least [minimumMatches] visible titles exist,
/// the feed ends, or [maxPages] extra pages were read.
bool shouldContinueFilterScan({
  required int matches,
  required int pagesScanned,
  required bool hasMore,
  int minimumMatches = filterScanMinimumMatches,
  int maxPages = filterScanMaxPages,
}) => hasMore && pagesScanned < maxPages && matches < minimumMatches;

/// «بررسی عناوین بیشتر» stops at the first page that adds a new match.
bool shouldContinueScanMore({
  required int newMatches,
  required int pagesScanned,
  required bool hasMore,
  int maxPages = filterScanMoreMaxPages,
}) => hasMore && pagesScanned < maxPages && newMatches == 0;
