import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/grille/grille_constants.dart';
import 'package:facteur/features/grille/utils/grille_fit.dart';

void main() {
  group('fittedTileSize', () {
    test('taille design inchangée quand la place suffit', () {
      expect(fittedTileSize(400, 6), GrilleConstants.tileSize);
    });

    test('rétrécit pour tenir essaisMax lignes dans la hauteur restante', () {
      final size = fittedTileSize(250, 6);
      const gap = GrilleConstants.tileGap;
      expect(size * 6 + gap * 5, closeTo(250, 0.01));
      expect(size, lessThan(GrilleConstants.tileSize));
      expect(size, greaterThan(GrilleConstants.tileSizeFitFloor));
    });

    test('plancher lisible sur très petit écran', () {
      expect(fittedTileSize(10, 6), GrilleConstants.tileSizeFitFloor);
    });

    test('hauteur infinie (pas de contrainte) → taille design', () {
      expect(fittedTileSize(double.infinity, 6), GrilleConstants.tileSize);
    });

    test('essaisMax nul → taille design (garde-fou division)', () {
      expect(fittedTileSize(200, 0), GrilleConstants.tileSize);
    });
  });
}
