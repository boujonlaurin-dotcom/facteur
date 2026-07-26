import 'package:facteur/features/feed/utils/empty_search_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmptySearchReporter', () {
    late EmptySearchReporter reporter;

    setUp(() => reporter = EmptySearchReporter());

    bool report({int? items = 0, String? keyword = 'retraites', bool broadened = false}) =>
        reporter.shouldReport(
          itemCount: items,
          keyword: keyword,
          broadened: broadened,
        );

    test('une recherche bredouille est remontée une seule fois', () {
      expect(report(), isTrue);
      // Pull-to-refresh, reprise d'app, réémission du provider…
      expect(report(), isFalse);
      expect(report(), isFalse);
    });

    test('élargir la même requête compte comme une nouvelle recherche', () {
      expect(report(), isTrue);
      expect(report(broadened: true), isTrue);
    });

    test('changer de mot-clé compte comme une nouvelle recherche', () {
      expect(report(), isTrue);
      expect(report(keyword: 'climat'), isTrue);
    });

    test('un feed non résolu ne conclut rien', () {
      expect(report(items: null), isFalse);
      expect(report(), isTrue);
    });

    test('sans mot-clé actif, rien n\'est remonté', () {
      expect(report(keyword: null), isFalse);
      expect(report(keyword: '  '), isFalse);
    });

    test('un feed reparti réarme la même requête', () {
      expect(report(), isTrue);
      expect(report(items: 3), isFalse);
      // Même mot-clé, mais l'utilisateur a bien relancé une recherche depuis.
      expect(report(), isTrue);
    });
  });
}
