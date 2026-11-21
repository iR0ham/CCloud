import 'package:ccloud/core/recent_searches.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit terms are trimmed, newest first', () {
    expect(addRecentSearch(const [], '  matrix '), ['matrix']);
    expect(addRecentSearch(const ['alien'], 'matrix'), ['matrix', 'alien']);
  });

  test('blank terms are ignored and the input is not mutated', () {
    const current = ['alien'];
    expect(addRecentSearch(current, '   '), ['alien']);
    expect(current, ['alien']);
  });

  test('case-insensitive duplicates move to the front with the new casing', () {
    const current = ['Matrix', 'Alien'];
    expect(addRecentSearch(current, 'mATRIX'), ['mATRIX', 'Alien']);
  });

  test('the list is capped at eight entries, dropping the oldest', () {
    var terms = <String>[];
    for (var i = 1; i <= 9; i++) {
      terms = addRecentSearch(terms, 'q$i');
    }
    expect(terms.length, maxRecentSearches);
    expect(terms.first, 'q9');
    expect(terms.last, 'q2');
    expect(terms.contains('q1'), isFalse);
  });

  test('store loads, records under the macOS key and clears it', () async {
    SharedPreferences.setMockInitialValues({
      recentSearchesKey: ['alien', 'matrix'],
    });
    final prefs = await SharedPreferences.getInstance();
    final store = RecentSearchesStore(prefs);
    expect(store.terms, ['alien', 'matrix']);

    var notifications = 0;
    store.addListener(() => notifications++);
    await store.record('dune');
    expect(store.terms, ['dune', 'alien', 'matrix']);
    expect(prefs.getStringList(recentSearchesKey), ['dune', 'alien', 'matrix']);
    expect(notifications, 1);

    await store.record('DUNE');
    expect(store.terms, ['DUNE', 'alien', 'matrix']);
    expect(notifications, 2);

    await store.record('   ');
    expect(notifications, 2);

    await store.clear();
    expect(store.terms, isEmpty);
    expect(prefs.containsKey(recentSearchesKey), isFalse);
    expect(notifications, 3);
  });
}
