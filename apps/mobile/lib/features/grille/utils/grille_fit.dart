/// Pure, unit-testable tile-size estimator — dérive la taille de tuile
/// [MotGrid] qui fait tenir `essaisMax` lignes dans la hauteur disponible.
/// Calqué sur `section_fit.dart` : arithmétique seule, aucun binding Flutter.
library;

import '../grille_constants.dart';

/// Taille de tuile (px) qui tient [essaisMax] lignes dans [availableHeight],
/// plafonnée à la taille design ([GrilleConstants.tileSize], rendu inchangé
/// quand la place suffit) et plancher à [GrilleConstants.tileSizeFitFloor]
/// (lisibilité) — évite que la grille (hauteur sinon fixe) chevauche le bloc
/// CTA/nudge/clavier du bas quand celui-ci grandit (ex. nudge affiché après 2
/// essais) ou sur petit écran.
double fittedTileSize(double availableHeight, int essaisMax) {
  const gap = GrilleConstants.tileGap;
  const maxSize = GrilleConstants.tileSize;
  const minSize = GrilleConstants.tileSizeFitFloor;
  if (essaisMax <= 0 || !availableHeight.isFinite) return maxSize;
  final raw = (availableHeight - gap * (essaisMax - 1)) / essaisMax;
  return raw.clamp(minSize, maxSize);
}
