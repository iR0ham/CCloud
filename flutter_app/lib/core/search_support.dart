import 'models.dart';

/// Which body the search screen shows once the request settles.
///
/// Mirrors `SearchView.swift`: a result list wins; a genuinely empty response
/// is «not found»; otherwise the active filters explain the empty list before
/// content hiding does (both can be on at once).
enum SearchResultState { results, filteredEmpty, hiddenEmpty, notFound, idle }

SearchResultState searchResultState({
  required bool hasSearched,
  required int totalResults,
  required int visibleResults,
  required bool filtersActive,
  required bool hidingActive,
}) {
  if (visibleResults > 0) return SearchResultState.results;
  if (!hasSearched) return SearchResultState.idle;
  if (totalResults == 0) return SearchResultState.notFound;
  if (filtersActive) return SearchResultState.filteredEmpty;
  if (hidingActive) return SearchResultState.hiddenEmpty;
  return SearchResultState.notFound;
}

/// Caption above the result grid; `SearchView.resultsCaption`.
String searchResultsCaption({
  required int visible,
  required int total,
  required String query,
  required bool postFiltering,
}) => postFiltering
    ? '${faDigits(visible)} از ${faDigits(total)} نتیجه برای «$query» • فیلترشده'
    : 'نتایج برای «$query»';

/// `SearchView.swift` hiding empty state, with its Settings guidance.
String searchHidingMessage(String query) =>
    'برای «$query» نتیجه‌ای هست، اما همه در تنظیمات پنهان شده‌اند. '
    'برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.';

/// `SearchView.swift` not-found message.
String searchNotFoundMessage(String query) =>
    'برای «$query» چیزی پیدا نشد. عبارت دیگری را امتحان کنید.';
