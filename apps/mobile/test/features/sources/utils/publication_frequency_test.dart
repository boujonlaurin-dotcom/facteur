import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/sources/utils/publication_frequency.dart';

void main() {
  group('humanizeFrequency — buckets', () {
    test('0 (ou négatif) article → peu actif', () {
      expect(humanizeFrequency(0, null), 'peu actif');
      expect(humanizeFrequency(-3, null), 'peu actif');
    });

    test('gros volume → ~N/jour arrondi joli', () {
      expect(humanizeFrequency(3000, null), '~100/jour'); // 100/jour pile
      expect(humanizeFrequency(2850, null), '~100/jour'); // 95 → 100 (dizaine)
      expect(humanizeFrequency(870, null), '~30/jour'); // 29 → 30 (dizaine)
      expect(humanizeFrequency(360, null), '~12/jour'); // 12 exact (<20)
    });

    test('volume moyen → quelques-uns/jour (perDay ≥ 1.5)', () {
      expect(humanizeFrequency(60, null), 'quelques-uns/jour'); // 2/jour
      expect(humanizeFrequency(45, null), 'quelques-uns/jour'); // 1.5 borne
    });

    test('volume faible → quelques-uns/semaine', () {
      expect(humanizeFrequency(10, null), 'quelques-uns/semaine'); // ~0.33/jour
    });

    test('très faible → quelques-uns/mois', () {
      expect(humanizeFrequency(3, null), 'quelques-uns/mois');
      expect(humanizeFrequency(1, null), 'quelques-uns/mois');
    });
  });

  group('humanizeFrequency — clamp source fraîche', () {
    test('fenêtre clampée à l\'âge réel (évite la sous-estimation)', () {
      final now = DateTime(2026, 6, 15);
      final oldest = DateTime(2026, 6, 13); // 2 jours d'historique
      // 8 articles en 2 j → 4/jour. Sans clamp : 8/30 ≈ 0.27 → /semaine.
      expect(humanizeFrequency(8, oldest, now: now), 'quelques-uns/jour');
    });

    test('âge < 1 jour → fenêtre clampée à 1 (pas de division par 0)', () {
      final now = DateTime(2026, 6, 15, 12);
      final oldest = DateTime(2026, 6, 15, 6); // même jour → inDays 0
      expect(humanizeFrequency(5, oldest, now: now), 'quelques-uns/jour');
    });

    test('âge ≥ 30 jours → fenêtre plafonnée à 30', () {
      final now = DateTime(2026, 6, 15);
      final oldest = DateTime(2026, 1, 1); // bien > 30 j
      // 60 articles sur 30 j → 2/jour.
      expect(humanizeFrequency(60, oldest, now: now), 'quelques-uns/jour');
    });
  });
}
