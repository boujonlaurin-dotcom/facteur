import 'package:facteur/core/version/semver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareSemver', () {
    test('compare numériquement (pas lexicographiquement)', () {
      expect(compareSemver('1.10.0', '1.9.0'), 1);
      expect(compareSemver('1.9.0', '1.10.0'), -1);
      expect(compareSemver('2.0.0', '1.99.99'), 1);
    });

    test('égalité', () {
      expect(compareSemver('1.2.3', '1.2.3'), 0);
    });

    test('composants manquants traités comme 0', () {
      expect(compareSemver('1.2', '1.2.0'), 0);
      expect(compareSemver('1', '1.0.0'), 0);
      expect(compareSemver('1.2', '1.2.1'), -1);
    });

    test('suffixe build (+) ignoré', () {
      expect(compareSemver('1.2.0+8', '1.2.0+99'), 0);
      expect(compareSemver('1.2.0+8', '1.2.0'), 0);
      expect(compareSemver('1.3.0+1', '1.2.0+999'), 1);
    });

    test('suffixe pré-release (-) ignoré', () {
      expect(compareSemver('1.2.0-rc1', '1.2.0'), 0);
    });

    test('entrée malformée renvoie null', () {
      expect(compareSemver('abc', '1.0.0'), isNull);
      expect(compareSemver('1.0.0', ''), isNull);
      expect(compareSemver('1.x.0', '1.0.0'), isNull);
      expect(compareSemver('  ', '1.0.0'), isNull);
    });
  });
}
