import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

/// `splitAnalysisSections` découpe le texte d'analyse en deux blocs sur le
/// PREMIER `\n\n` : avant = « l'essentiel partagé », après = « là où ça
/// diverge ». Sans séparateur, tout va dans `divergent` et `essentiel` est vide.
void main() {
  group('splitAnalysisSections', () {
    test('split sur le premier \\n\\n', () {
      final r = splitAnalysisSections('Essentiel partagé.\n\nLes médias divergent.');
      expect(r.essentiel, 'Essentiel partagé.');
      expect(r.divergent, 'Les médias divergent.');
    });

    test('ne split que sur le PREMIER \\n\\n (le reste va dans divergent)', () {
      final r = splitAnalysisSections('A\n\nB\n\nC');
      expect(r.essentiel, 'A');
      expect(r.divergent, 'B\n\nC');
    });

    test('sans séparateur → essentiel vide, tout sous divergent', () {
      final r = splitAnalysisSections('Un seul paragraphe sans rupture.');
      expect(r.essentiel, '');
      expect(r.divergent, 'Un seul paragraphe sans rupture.');
    });

    test('trim les deux sections', () {
      final r = splitAnalysisSections('   Essentiel   \n\n   Divergent   ');
      expect(r.essentiel, 'Essentiel');
      expect(r.divergent, 'Divergent');
    });

    test('chaîne vide → deux sections vides', () {
      final r = splitAnalysisSections('');
      expect(r.essentiel, '');
      expect(r.divergent, '');
    });
  });
}
