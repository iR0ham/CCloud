import 'package:ccloud/core/search_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('search result state', () {
    SearchResultState state({
      bool hasSearched = true,
      int total = 5,
      int visible = 5,
      bool filters = false,
      bool hiding = false,
    }) => searchResultState(
      hasSearched: hasSearched,
      totalResults: total,
      visibleResults: visible,
      filtersActive: filters,
      hidingActive: hiding,
    );

    test('visible rows always render the grid', () {
      expect(state(), SearchResultState.results);
      expect(state(filters: true, hiding: true), SearchResultState.results);
    });

    test('before a query the idle view shows', () {
      expect(state(hasSearched: false, visible: 0), SearchResultState.idle);
    });

    test('a genuinely empty response is not-found even with filters', () {
      expect(
        state(total: 0, visible: 0, filters: true),
        SearchResultState.notFound,
      );
      expect(
        state(total: 0, visible: 0, hiding: true),
        SearchResultState.notFound,
      );
    });

    test('filters explain an emptied list before hiding does', () {
      expect(
        state(total: 5, visible: 0, filters: true),
        SearchResultState.filteredEmpty,
      );
      expect(
        state(total: 5, visible: 0, filters: true, hiding: true),
        SearchResultState.filteredEmpty,
      );
      expect(
        state(total: 5, visible: 0, hiding: true),
        SearchResultState.hiddenEmpty,
      );
    });
  });

  group('search copy', () {
    test('caption counts visible against total in Persian digits', () {
      expect(
        searchResultsCaption(
          visible: 3,
          total: 12,
          query: 'دزدان',
          postFiltering: true,
        ),
        '۳ از ۱۲ نتیجه برای «دزدان» • فیلترشده',
      );
      expect(
        searchResultsCaption(
          visible: 3,
          total: 3,
          query: 'دزدان',
          postFiltering: false,
        ),
        'نتایج برای «دزدان»',
      );
    });

    test('hiding and not-found messages quote the query', () {
      expect(
        searchHidingMessage('دزدان'),
        'برای «دزدان» نتیجه‌ای هست، اما همه در تنظیمات پنهان شده‌اند. '
        'برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.',
      );
      expect(
        searchNotFoundMessage('دزدان'),
        'برای «دزدان» چیزی پیدا نشد. عبارت دیگری را امتحان کنید.',
      );
    });
  });
}
