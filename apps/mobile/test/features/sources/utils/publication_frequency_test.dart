import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/sources/utils/publication_frequency.dart';

void main() {
  group('humanizeFrequency — buckets', () {
    test('0 (ou négatif) article → peu actif', () {
      expect(humanizeFrequency(0, null), 'peu actif');
      expect(humanizeFrequency(-3, null), 'peu actif');
    });

    test('gros volume → phrase explicite par jour', () {
      expect(humanizeFrequency(2100, null), '70 articles par jour en moyenne');
      expect(humanizeFrequency(3000, null), '100 articles par jour en moyenne');
      expect(humanizeFrequency(2850, null), '100 articles par jour en moyenne');
      expect(humanizeFrequency(870, null), '30 articles par jour en moyenne');
      expect(humanizeFrequency(360, null), '12 articles par jour en moyenne');
    });

    test('volume moyen → quelques articles par jour (perDay ≥ 1.5)', () {
      expect(humanizeFrequency(60, null), 'quelques articles par jour');
      expect(humanizeFrequency(45, null), 'quelques articles par jour');
    });

    test('volume faible → quelques articles par semaine', () {
      expect(humanizeFrequency(10, null), 'quelques articles par semaine');
    });

    test('très faible → quelques articles par mois', () {
      expect(humanizeFrequency(3, null), 'quelques articles par mois');
      expect(humanizeFrequency(1, null), 'quelques articles par mois');
    });
  });

  group('humanizeFrequency — clamp source fraîche', () {
    test('fenêtre clampée à l\'âge réel (évite la sous-estimation)', () {
      final now = DateTime(2026, 6, 15);
      final oldest = DateTime(2026, 6, 13); // 2 jours d'historique
      // 8 articles en 2 j → 4/jour. Sans clamp : 8/30 ≈ 0.27 → /semaine.
      expect(
        humanizeFrequency(8, oldest, now: now),
        'quelques articles par jour',
      );
    });

    test('âge < 1 jour → fenêtre clampée à 1 (pas de division par 0)', () {
      final now = DateTime(2026, 6, 15, 12);
      final oldest = DateTime(2026, 6, 15, 6); // même jour → inDays 0
      expect(
        humanizeFrequency(5, oldest, now: now),
        'quelques articles par jour',
      );
    });

    test('âge ≥ 30 jours → fenêtre plafonnée à 30', () {
      final now = DateTime(2026, 6, 15);
      final oldest = DateTime(2026, 1, 1); // bien > 30 j
      // 60 articles sur 30 j → 2/jour.
      expect(
        humanizeFrequency(60, oldest, now: now),
        'quelques articles par jour',
      );
    });
  });
}
