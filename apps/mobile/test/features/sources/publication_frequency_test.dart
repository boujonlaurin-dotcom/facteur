import 'package:facteur/features/sources/utils/publication_frequency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 26, 12);

  group('humanizeFrequency', () {
    test('source sans article = peu actif', () {
      expect(humanizeFrequency(0, null, now: now), 'peu actif');
    });

    test('gros volume = moyenne arrondie', () {
      expect(
        humanizeFrequency(600, now.subtract(const Duration(days: 30)),
            now: now),
        '20 articles par jour en moyenne',
      );
    });

    test('source mensuelle', () {
      expect(
        humanizeFrequency(1, now.subtract(const Duration(days: 30)), now: now),
        'quelques articles par mois',
      );
    });
  });

  group('isRareSource', () {
    test('mensuelle = rare', () {
      expect(
        isRareSource(1, now.subtract(const Duration(days: 30)), now: now),
        isTrue,
      );
    });

    test('hebdomadaire = pas rare', () {
      expect(
        isRareSource(5, now.subtract(const Duration(days: 30)), now: now),
        isFalse,
      );
    });

    test('quotidienne = pas rare', () {
      expect(
        isRareSource(30, now.subtract(const Duration(days: 30)), now: now),
        isFalse,
      );
    });

    test('source fraîche non sous-estimée par le clamp', () {
      // 3 articles en 2 jours : sans le clamp, la fenêtre de 30 j diluerait
      // le volume et la source passerait pour rare.
      expect(
        isRareSource(3, now.subtract(const Duration(days: 2)), now: now),
        isFalse,
      );
    });

    test('zéro article = jamais éligible', () {
      expect(
        isRareSource(0, now.subtract(const Duration(days: 90)), now: now),
        isFalse,
      );
      expect(isRareSource(0, null, now: now), isFalse);
    });

    test('sans historique connu, fenêtre pleine de 30 j', () {
      expect(isRareSource(1, null, now: now), isTrue);
      expect(isRareSource(20, null, now: now), isFalse);
    });
  });

  group('rarityPhrase', () {
    test('null si la source n\'est pas rare', () {
      expect(
        rarityPhrase(30, now.subtract(const Duration(days: 30)), now: now),
        isNull,
      );
    });

    test('mensuelle', () {
      expect(
        rarityPhrase(1, now.subtract(const Duration(days: 30)), now: now),
        'environ une fois par mois',
      );
    });

    test('bimensuelle', () {
      expect(
        rarityPhrase(3, now.subtract(const Duration(days: 30)), now: now),
        'environ une fois toutes les deux semaines',
      );
    });

    test('ne promet jamais plus que ce que les chiffres soutiennent', () {
      // Toute source éligible publie moins d'une fois par semaine : aucune
      // phrase ne doit parler de « semaine » au singulier.
      for (final articles in [1, 2, 3, 4]) {
        final phrase = rarityPhrase(
          articles,
          now.subtract(const Duration(days: 30)),
          now: now,
        );
        if (phrase != null) {
          expect(phrase, isNot(contains('par semaine')));
        }
      }
    });
  });
}
