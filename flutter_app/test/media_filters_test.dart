import 'package:ccloud/core/media_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaFilters matching', () {
    test('inactive filters match everything, including unknown values', () {
      const filters = MediaFilters();
      expect(filters.isActive, isFalse);
      expect(filters.activeCount, 0);
      expect(filters.matchesValues(year: 0, imdb: 0, isSeries: false), isTrue);
      expect(filters.matchesValues(year: 0, imdb: 0, isSeries: true), isTrue);
    });

    test('kind must equal the item kind', () {
      const movies = MediaFilters(kind: MediaKind.movie);
      const series = MediaFilters(kind: MediaKind.series);
      expect(
        movies.matchesValues(year: 2020, imdb: 7, isSeries: false),
        isTrue,
      );
      expect(
        movies.matchesValues(year: 2020, imdb: 7, isSeries: true),
        isFalse,
      );
      expect(series.matchesValues(year: 2020, imdb: 7, isSeries: true), isTrue);
      expect(
        series.matchesValues(year: 2020, imdb: 7, isSeries: false),
        isFalse,
      );
    });

    test('year range is inclusive and rejects unknown years', () {
      const filters = MediaFilters(yearFrom: 2010, yearTo: 2020);
      expect(
        filters.matchesValues(year: 2010, imdb: 7, isSeries: false),
        isTrue,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 7, isSeries: false),
        isTrue,
      );
      expect(
        filters.matchesValues(year: 2009, imdb: 7, isSeries: false),
        isFalse,
      );
      expect(
        filters.matchesValues(year: 2021, imdb: 7, isSeries: false),
        isFalse,
      );
      expect(filters.matchesValues(year: 0, imdb: 7, isSeries: false), isFalse);
    });

    test('one-sided year bounds work on their own', () {
      const from = MediaFilters(yearFrom: 2015);
      const to = MediaFilters(yearTo: 2000);
      expect(from.matchesValues(year: 2024, imdb: 7, isSeries: false), isTrue);
      expect(from.matchesValues(year: 2014, imdb: 7, isSeries: false), isFalse);
      expect(to.matchesValues(year: 1999, imdb: 7, isSeries: false), isTrue);
      expect(to.matchesValues(year: 2000, imdb: 7, isSeries: false), isTrue);
      expect(to.matchesValues(year: 2001, imdb: 7, isSeries: false), isFalse);
      expect(to.matchesValues(year: 0, imdb: 7, isSeries: false), isFalse);
    });

    test('IMDb keeps the 0.049 rounding tolerance', () {
      const filters = MediaFilters(minIMDb: 7);
      // The catalogue rounds down, so a 7.0 title satisfies a 7+ chip.
      expect(
        filters.matchesValues(year: 2020, imdb: 7.0, isSeries: false),
        isTrue,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 7.049, isSeries: false),
        isTrue,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 6.951, isSeries: false),
        isTrue,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 6.95, isSeries: false),
        isFalse,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 6.9, isSeries: false),
        isFalse,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 0, isSeries: false),
        isFalse,
      );
    });

    test('criteria combine with AND', () {
      const filters = MediaFilters(
        kind: MediaKind.series,
        yearFrom: 2018,
        minIMDb: 8,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 8.2, isSeries: true),
        isTrue,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 8.2, isSeries: false),
        isFalse,
      );
      expect(
        filters.matchesValues(year: 2016, imdb: 8.2, isSeries: true),
        isFalse,
      );
      expect(
        filters.matchesValues(year: 2020, imdb: 7.5, isSeries: true),
        isFalse,
      );
    });

    test('active count treats the year range as one criterion', () {
      expect(const MediaFilters().activeCount, 0);
      expect(const MediaFilters(kind: MediaKind.movie).activeCount, 1);
      expect(const MediaFilters(yearFrom: 2000, yearTo: 2010).activeCount, 1);
      expect(
        const MediaFilters(
          kind: MediaKind.movie,
          yearFrom: 2000,
          yearTo: 2010,
          minIMDb: 6,
        ).activeCount,
        3,
      );
    });
  });

  group('MediaFilters value helpers', () {
    test('withYearFrom raises a lower yearTo so the range stays valid', () {
      const filters = MediaFilters(yearTo: 2010);
      final raised = filters.withYearFrom(2015);
      expect(raised.yearFrom, 2015);
      expect(raised.yearTo, 2015);
      expect(filters.withYearFrom(2000).yearTo, 2010);
      expect(filters.withYearFrom(null).yearFrom, isNull);
      expect(filters.withYearFrom(null).yearTo, 2010);
    });

    test('withYearTo lowers a higher yearFrom', () {
      const filters = MediaFilters(yearFrom: 2015);
      final lowered = filters.withYearTo(2010);
      expect(lowered.yearFrom, 2010);
      expect(lowered.yearTo, 2010);
      expect(filters.withYearTo(2020).yearFrom, 2015);
      expect(filters.withYearTo(null).yearTo, isNull);
    });

    test('without clears only the requested facet', () {
      const all = MediaFilters(
        kind: MediaKind.movie,
        yearFrom: 2000,
        yearTo: 2010,
        minIMDb: 7,
      );
      expect(all.without(MediaFilterFacet.kind).kind, isNull);
      expect(all.without(MediaFilterFacet.kind).yearFrom, 2000);
      final noYear = all.without(MediaFilterFacet.year);
      expect(noYear.yearFrom, isNull);
      expect(noYear.yearTo, isNull);
      expect(noYear.kind, MediaKind.movie);
      expect(noYear.minIMDb, 7);
      expect(all.without(MediaFilterFacet.imdb).minIMDb, isNull);
      expect(all.without(MediaFilterFacet.imdb).kind, MediaKind.movie);
    });

    test('facet labels mirror the macOS chips', () {
      expect(
        const MediaFilters(kind: MediaKind.movie)
            .facetLabel(MediaFilterFacet.kind),
        'فیلم',
      );
      expect(
        const MediaFilters(kind: MediaKind.series)
            .facetLabel(MediaFilterFacet.kind),
        'سریال',
      );
      expect(
        const MediaFilters(
          yearFrom: 2020,
          yearTo: 2020,
        ).facetLabel(MediaFilterFacet.year),
        'سال 2020',
      );
      expect(
        const MediaFilters(
          yearFrom: 2010,
          yearTo: 2020,
        ).facetLabel(MediaFilterFacet.year),
        '2010 تا 2020',
      );
      expect(
        const MediaFilters(yearFrom: 2010).facetLabel(MediaFilterFacet.year),
        'از 2010',
      );
      expect(
        const MediaFilters(yearTo: 2020).facetLabel(MediaFilterFacet.year),
        'تا 2020',
      );
      expect(
        const MediaFilters(minIMDb: 7).facetLabel(MediaFilterFacet.imdb),
        'IMDb 7+',
      );
      expect(
        const MediaFilters(minIMDb: 7.5).facetLabel(MediaFilterFacet.imdb),
        'IMDb 7.5+',
      );
      expect(const MediaFilters().facetLabel(MediaFilterFacet.kind), isNull);
      expect(const MediaFilters().facetLabel(MediaFilterFacet.year), isNull);
      expect(const MediaFilters().facetLabel(MediaFilterFacet.imdb), isNull);
    });

    test('value equality compares every facet', () {
      const a = MediaFilters(
        kind: MediaKind.series,
        yearFrom: 2000,
        yearTo: 2010,
        minIMDb: 6,
      );
      const b = MediaFilters(
        kind: MediaKind.series,
        yearFrom: 2000,
        yearTo: 2010,
        minIMDb: 6,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == const MediaFilters(kind: MediaKind.series), isFalse);
    });
  });

  group('filter helpers', () {
    test('formatImdbThreshold prints %g-style labels', () {
      expect(formatImdbThreshold(6), '6');
      expect(formatImdbThreshold(7.0), '7');
      expect(formatImdbThreshold(7.5), '7.5');
    });

    test('year choices start at next year and end at 1950', () {
      final years = filterYearChoices(currentYear: 2024);
      expect(years.first, 2025);
      expect(years.last, 1950);
      expect(years.length, 76);
      expect(years[1], 2024);
    });

    test('scan stops at 12 matches, 10 pages, or the feed end', () {
      expect(
        shouldContinueFilterScan(matches: 0, pagesScanned: 0, hasMore: true),
        isTrue,
      );
      expect(
        shouldContinueFilterScan(matches: 11, pagesScanned: 9, hasMore: true),
        isTrue,
      );
      expect(
        shouldContinueFilterScan(matches: 12, pagesScanned: 1, hasMore: true),
        isFalse,
      );
      expect(
        shouldContinueFilterScan(matches: 5, pagesScanned: 10, hasMore: true),
        isFalse,
      );
      expect(
        shouldContinueFilterScan(matches: 0, pagesScanned: 0, hasMore: false),
        isFalse,
      );
    });

    test('scan-more stops at the first page with a new match', () {
      expect(
        shouldContinueScanMore(newMatches: 0, pagesScanned: 0, hasMore: true),
        isTrue,
      );
      expect(
        shouldContinueScanMore(newMatches: 1, pagesScanned: 0, hasMore: true),
        isFalse,
      );
      expect(
        shouldContinueScanMore(newMatches: 0, pagesScanned: 4, hasMore: true),
        isFalse,
      );
      expect(
        shouldContinueScanMore(newMatches: 0, pagesScanned: 0, hasMore: false),
        isFalse,
      );
    });
  });
}
