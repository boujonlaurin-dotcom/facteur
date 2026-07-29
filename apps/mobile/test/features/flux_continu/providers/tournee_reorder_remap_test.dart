import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart';
import 'package:facteur/features/flux_continu/providers/tournee_reorder_persistence.dart';

/// Rangée type de la Tournée : héros figé, puis sections réordonnables, avec la
/// Grille épinglée au milieu, et Citation / Fin de tournée figées en queue.
const _row = <String?>[
  null, // essentiel_v3 (héros)
  'essentiel', // Actus du jour
  null, // grille (Mot du jour)
  'theme:tech',
  'source:42',
  'bonnes',
  null, // citation
  null, // fin de tournée
];

void main() {
  group('isTourneeReorderableKey', () {
    test('accepte les sections réellement déplaçables', () {
      expect(isTourneeReorderableKey(kTourneeActusKey), isTrue);
      expect(isTourneeReorderableKey(kTourneeBonnesKey), isTrue);
      expect(isTourneeReorderableKey(kTourneeVeilleKey), isTrue);
      expect(isTourneeReorderableKey(tourneeThemeKey('tech')), isTrue);
      expect(isTourneeReorderableKey(tourneeSourceKey('42')), isTrue);
    });

    test('refuse héros, Grille, alertes et sujets Flâner', () {
      expect(isTourneeReorderableKey('essentiel_v3'), isFalse);
      expect(isTourneeReorderableKey(kTourneeGrilleKey), isFalse);
      expect(isTourneeReorderableKey('alerts'), isFalse);
      expect(isTourneeReorderableKey('topic:abc'), isFalse);
    });
  });

  group('reorderTourneeTabKeys', () {
    test('déplace une section vers la gauche', () {
      // 'bonnes' (index 5) déposé juste avant 'theme:tech' (insertion à 3).
      expect(
        reorderTourneeTabKeys(_row, 5, 3),
        ['essentiel', 'bonnes', 'theme:tech', 'source:42'],
      );
    });

    test('déplace une section vers la droite (espace d\'insertion)', () {
      // 'essentiel' (index 1) déposé après 'source:42' (insertion à 5).
      expect(
        reorderTourneeTabKeys(_row, 1, 5),
        ['theme:tech', 'source:42', 'essentiel', 'bonnes'],
      );
    });

    test('clampe un drop au-delà du héros au premier slot réordonnable', () {
      expect(
        reorderTourneeTabKeys(_row, 3, 0),
        ['theme:tech', 'essentiel', 'source:42', 'bonnes'],
      );
    });

    test('clampe un drop au-delà de la queue figée au dernier slot', () {
      expect(
        reorderTourneeTabKeys(_row, 1, 8),
        ['theme:tech', 'source:42', 'bonnes', 'essentiel'],
      );
    });

    test('refuse la saisie d\'un onglet figé', () {
      expect(reorderTourneeTabKeys(_row, 0, 4), isNull);
      expect(reorderTourneeTabKeys(_row, 2, 5), isNull);
    });

    test('no-op si la position ne change pas ou si l\'index est hors bornes',
        () {
      expect(reorderTourneeTabKeys(_row, 3, 3), isNull);
      expect(reorderTourneeTabKeys(_row, 42, 1), isNull);
      expect(reorderTourneeTabKeys(_row, -1, 1), isNull);
    });

    test('no-op avec un seul onglet déplaçable', () {
      expect(reorderTourneeTabKeys(const [null, 'essentiel', null], 1, 3),
          isNull);
    });
  });
}
