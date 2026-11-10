import 'models.dart';

/// The backend packs the whole info sheet into `description`: labelled metadata
/// first, then the plot after a «خلاصه داستان/سریال» heading, then release notes.
/// The hero only has room for the plot, so extract that paragraph.
const List<String> _plotHeadings = [
  'خلاصه داستان',
  'خلاصه سریال',
  'خلاصه فیلم',
  'خلاصه برنامه',
  'داستان فیلم',
  'داستان سریال',
  'داستان برنامه',
];

const List<String> _footerHeadings = [
  'زیرنویس',
  'وضعیت',
  'برای تماشای',
  'لینک دانلود',
  'منبع',
  'درباره انیمیشن',
  'درباره فیلم',
  'درباره سریال',
  'نقد و بررسی',
];

const List<String> _metadataLabels = [
  'نام اصلی',
  'نام پارسی',
  'سایر عناوین',
  'امتیاز',
  'ژانر',
  'تاریخ انتشار',
  'سال ساخت',
  'سال تولید',
  'محصول',
  'کشور',
  'زبان',
  'شبکه',
  'پخش از شبکه',
  'روز پخش',
  'روز های پخش',
  'شبکه پخش',
  'رده سنی',
  'کارگردان',
  'نویسنده',
  'ستارگان',
  'بازیگران',
  'با حضور',
  'فرمت',
  'کیفیت',
  'حجم',
  'مدت زمان',
  'تعداد قسمت',
  'قسمت ها',
  'وضعیت',
];

String cleanDescription(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'[ \t]+\n'), '\n')
    .replaceAll(RegExp(r'\n[ \t]*\n+'), '\n')
    .trim();

String? plotFromDescription(String description) {
  final normalized = description.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.trim().isEmpty) return null;

  String? heading;
  var headingIndex = -1;
  for (final candidate in _plotHeadings) {
    final index = normalized.indexOf(candidate);
    if (index >= 0 && (headingIndex < 0 || index < headingIndex)) {
      heading = candidate;
      headingIndex = index;
    }
  }

  String body;
  if (heading != null) {
    body = normalized.substring(headingIndex + heading.length);
  } else {
    // Some entries have no plot at all, just a run of labelled fields. Those
    // must not be printed as if they were a story.
    final storyLines = normalized
        .split('\n')
        .where((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return true;
          return !_metadataLabels.any(trimmed.startsWith) &&
              !_footerHeadings.any(trimmed.startsWith);
        })
        .join('\n');
    if (storyLines.trim().isEmpty) return null;
    final labelHits =
        _metadataLabels.where(storyLines.contains).length;
    if (labelHits >= 2) return null;
    body = storyLines;
  }

  final kept = <String>[];
  for (final line in body.split('\n')) {
    if (_footerHeadings.any(line.trim().startsWith)) break;
    kept.add(line);
  }
  var story = kept.join('\n');
  story = story.replaceFirst(RegExp(r'^[\s:：]+'), '');
  story = story.replaceAll(RegExp(r'\s+'), ' ').trim();
  story = story.replaceFirst(RegExp(r'[:،,]+$'), '').trim();
  return story.isEmpty ? null : story;
}

/// The backend embeds the age rating in the long description ("رده سنی: 16").
String? ageRatingFromDescription(String description) {
  if (description.isEmpty) return null;
  final match = RegExp(
    r'رده\s*سنی\s*:?\s*\+?\s*([0-9۰-۹]{1,2})',
  ).firstMatch(description);
  final digits = match?.group(1);
  if (digits == null || digits.isEmpty) return null;
  return 'رده سنی ${faDigits(digits)}+';
}
