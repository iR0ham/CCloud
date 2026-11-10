import 'package:ccloud/core/api_client.dart';
import 'package:ccloud/core/description_text.dart';
import 'package:ccloud/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('faDigits converts latin digits', () {
    expect(faDigits(85), '۸۵');
    expect(faDigits('S01E04'), 'S۰۱E۰۴');
  });

  test('normalizeSearchQuery maps Arabic letters and strips bidi marks', () {
    expect(ApiClient.normalizeSearchQuery('ياسمين'), 'یاسمین');
    expect(ApiClient.normalizeSearchQuery('كيمی'), 'کیمی');
    expect(ApiClient.normalizeSearchQuery('\u200Fاکشن/درام'), 'اکشن درام');
  });

  test('normalizeSearchQuery collapses whitespace', () {
    expect(ApiClient.normalizeSearchQuery('  war   of  '), 'war of');
  });

  test('plotFromDescription extracts the story after its heading', () {
    const text = 'نام اصلی: Whalefall\nسال ساخت: 2026\n'
        'خلاصه داستان: یک غواص برای یافتن پیکر پدرش به دریا می‌رود.\n'
        'زیرنویس: فارسی';
    expect(
      plotFromDescription(text),
      'یک غواص برای یافتن پیکر پدرش به دریا می‌رود.',
    );
  });

  test('plotFromDescription ignores metadata-only sheets', () {
    expect(plotFromDescription('نام اصلی: X\nژانر: درام'), isNull);
    expect(plotFromDescription('   '), isNull);
  });

  test('ageRatingFromDescription reads the embedded rating', () {
    expect(ageRatingFromDescription('رده سنی: 16'), 'رده سنی ۱۶+');
    expect(ageRatingFromDescription('خلاصه داستان: بدون رده'), isNull);
  });
}
