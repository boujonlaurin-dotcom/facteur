# Bug — le nudge « Indice : le mot est dans l'actu » se superpose parfois à la grille

- **Signalé par** : PO, 2026-07-27
- **Impact utilisateur** : chevauchement visuel grille/texte d'instruction sur petit écran
- **Statut** : corrigé

## Symptôme

Le petit texte d'instruction (« Indice : le mot est dans l'actu du jour — aller lire »),
affiché juste au-dessus du clavier virtuel et en dessous de la grille, se superpose parfois
avec la grille elle-même.

## Cause racine

`MotGrid` (`apps/mobile/lib/features/grille/widgets/mot_grid.dart`) rend `essaisMax` lignes
à une taille de tuile **fixe** (`GrilleConstants.tileSize = 50px`), posée dans
`Expanded > Center > Padding` (`grille_screen.dart`, `_buildJeu`) — sans
`SingleChildScrollView` de secours.

Le bloc du bas (statut, CTA, nudge, clavier `AzertyKeyboard`) a lui une hauteur
**variable** : `_buildActusHint` (le nudge) ne s'affiche qu'après le 2e essai raté
(`today.nbEssais >= 2`), ce qui réduit l'espace `Expanded` restant en cours de partie.

Comme la grille ne s'adapte jamais à l'espace réellement disponible et qu'il n'y a pas de
scroll de secours, tout espace insuffisant (petit écran, ou apparition du nudge) se traduit
par un chevauchement visuel plutôt qu'un rétrécissement ou un scroll.

## Correctif

`MotGrid` accepte désormais un `tileSizeOverride` optionnel. `grille_screen.dart` enveloppe
la zone de la grille dans un `LayoutBuilder` et appelle la nouvelle fonction pure
`fittedTileSize` (`apps/mobile/lib/features/grille/utils/grille_fit.dart`, calquée sur le
pattern `section_fit.dart` : arithmétique seule, testable sans bootstrap Flutter), qui
calcule la taille de tuile faisant tenir `essaisMax` lignes dans `constraints.maxHeight`,
plafonnée à la taille design (`GrilleConstants.tileSize` = 50px, rendu inchangé quand la
place suffit) et plancher à `GrilleConstants.tileSizeFitFloor` (34px, lisibilité).

La grille rétrécit désormais avec l'espace disponible plutôt que de déborder par-dessus le
bloc du bas, que ce soit à cause d'un petit écran ou de l'apparition dynamique du nudge.

Note : ce mécanisme (tuile dimensionnée via `LayoutBuilder`, plafond/plancher) est le même
chantier que prévoyait PR1 du plan `mot-du-jour-leaderboard` pour la largeur (longueur de
mot variable 4-8) — il est donc réutilisable tel quel pour la dimension largeur quand cette
PR sera implémentée.

## Tests

`flutter analyze lib/features/grille test/features/grille` : clean. Suite
`flutter test test/features/grille` : 51 tests, tous passants (dont 5 nouveaux tests unitaires
sur `fittedTileSize` — taille design inchangée si la place suffit, rétrécissement borné,
plancher lisible, garde-fous hauteur infinie / `essaisMax=0` — et aucune régression sur les
widgets `MotGrid` existants, qui restent à leur taille design par défaut quand
`tileSizeOverride` est omis).
