import 'package:ccloud/core/models.dart';
import 'package:ccloud/core/origin_filter.dart';
import 'package:flutter_test/flutter_test.dart';

MediaItem _item({
  List<String> countries = const [],
  List<String> genres = const [],
}) {
  return MediaItem(
    id: 1,
    type: 'movie',
    title: 'Sample',
    description: '',
    year: 2020,
    imdb: 7,
    rating: 7,
    duration: null,
    image: '',
    cover: '',
    genres: [
      for (var i = 0; i < genres.length; i++) Genre(id: i, title: genres[i]),
    ],
    sources: const [],
    countries: [
      for (var i = 0; i < countries.length; i++)
        Country(id: i, title: countries[i], image: ''),
    ],
  );
}

void main() {
  test('normalize maps ZWNJ to a space and strips bidi marks', () {
    expect(OriginFilter.normalize('کره\u200Cجنوبی'), 'کره جنوبی');
    expect(OriginFilter.normalize('\u200Eچین\u200F'), 'چین');
    expect(OriginFilter.normalize('  کره   جنوبی '), 'کره جنوبی');
  });

  test('the regional country list includes the macOS entries', () {
    expect(OriginFilter.countryTitles.contains('افغانستان'), isTrue);
    expect(OriginFilter.countryTitles.contains('کره جنوبی'), isTrue);
    expect(OriginFilter.countryTitles.contains('عربستان'), isTrue);
    expect(OriginFilter.countryTitles.contains('فرانسه'), isFalse);
    for (final title in OriginFilter.countryTitles) {
      expect(OriginFilter.normalize(title), title);
    }
  });

  test('country matching accepts ZWNJ and bidi-marked titles', () {
    expect(OriginFilter.hidesCountry(_country('کره\u200Cجنوبی')), isTrue);
    expect(OriginFilter.hidesCountry(_country('\u200Fچین')), isTrue);
    expect(OriginFilter.hidesCountry(_country('افغانستان')), isTrue);
    expect(OriginFilter.hidesCountry(_country('آمریکا')), isFalse);
  });

  test('genre matching normalizes the spelled-out variants', () {
    expect(OriginFilter.hidesGenre('کره ای'), isTrue);
    expect(OriginFilter.hidesGenre('کره\u200Cای'), isTrue);
    expect(OriginFilter.hidesGenre('چینی ژاپنی'), isTrue);
    expect(OriginFilter.hidesGenre('درام'), isFalse);
  });

  test('a title is hidden when either its country or genre matches', () {
    expect(OriginFilter.hides(_item(countries: ['ترکیه'])), isTrue);
    expect(OriginFilter.hides(_item(genres: ['هندی'])), isTrue);
    expect(
      OriginFilter.hides(_item(countries: ['آمریکا'], genres: ['درام'])),
      isFalse,
    );
  });

  test('anime needs a Japanese country and an anime genre', () {
    expect(
      OriginFilter.hidesAnime(_item(countries: ['ژاپن'], genres: ['انیمه'])),
      isTrue,
    );
    expect(
      OriginFilter.hidesAnime(
        _item(countries: ['ژاپن'], genres: ['انیمیشن', 'انیمه']),
      ),
      isTrue,
    );
    // Western animation carries the shared genre but is not anime.
    expect(
      OriginFilter.hidesAnime(
        _item(countries: ['آمریکا'], genres: ['انیمیشن', 'انیمه']),
      ),
      isFalse,
    );
    expect(
      OriginFilter.hidesAnime(_item(countries: ['ژاپن'], genres: ['درام'])),
      isFalse,
    );
  });

  test('ContentHiding applies each toggle independently', () {
    const off = ContentHiding();
    expect(off.isActive, isFalse);
    expect(off.isHidden(_item(countries: ['ترکیه'])), isFalse);
    expect(
      off.isHidden(_item(countries: ['ژاپن'], genres: ['انیمه'])),
      isFalse,
    );

    const origins = ContentHiding(origins: true);
    expect(origins.isActive, isTrue);
    expect(origins.isHidden(_item(countries: ['ترکیه'])), isTrue);
    // Japan is also on the regional list, so origins-only hides anime too.
    expect(
      origins.isHidden(_item(countries: ['ژاپن'], genres: ['انیمه'])),
      isTrue,
    );
    expect(origins.hidesCountry(_country('هند')), isTrue);
    expect(origins.hidesGenre('کره ای'), isTrue);

    const anime = ContentHiding(anime: true);
    expect(anime.isHidden(_item(countries: ['ترکیه'])), isFalse);
    expect(
      anime.isHidden(_item(countries: ['ژاپن'], genres: ['انیمه'])),
      isTrue,
    );
    expect(anime.hidesCountry(_country('هند')), isFalse);
    expect(anime.hidesGenre('هندی'), isFalse);
  });
}

Country _country(String title) => Country(id: 1, title: title, image: '');
