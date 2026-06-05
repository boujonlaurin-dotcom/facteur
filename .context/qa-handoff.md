# QA Handoff — UX Drag & Drop + bouton « Composer ma Tournée »

Branche : `boujonlaurin-dotcom/drag-drop-ux-tournee`

## Écrans impactés
- **Sheet « Mes favoris » / « Composer ma Tournée »** (`manage_favorites_sheet.dart`) — sections Essentiel & Flâner, listes réordonnables.
- **Bouton « Composer ma Tournée »** (`ComposeTourneeButton`) rendu dans `section_block.dart` (carte Essentiel + empty-state), `flux_continu_screen.dart`, `sources_screen.dart`, `my_interests_screen.dart`.

## Changements
1. **Feedback visuel drag** : l'élément glissé est « soulevé » (scale 1.03 + ombre douce progressive). Vibration `mediumImpact` au pickup, `selectionClick` au dépôt.
2. **Hit zone élargie** : toute la zone logo + label de chaque ligne démarre le drag (`ColoredBox` opaque), + poignée points portée à 44×44px. Boutons d'action (retirer/déplacer/veille) restent tappables.
3. **Bouton** : tuile teintée douce (fond `primary` 12%, ombre subtile), plus grande (padding vertical 16, font 15, icône 18), ripple InkWell. Remplace l'ancien contour fin.

## Scénarios de test (viewport 390×844)
- **Happy path** : ouvrir « Composer ma Tournée » → nouveau bouton visible/élégant ; glisser une ligne par sa **zone label** (pas que la poignée) → vibration + élément soulevé + réordonnancement persiste après fermeture/réouverture.
- **Edge** : taper retirer/déplacer/veille sur une ligne → action déclenchée SANS démarrer un drag.
- **Edge** : tester les deux sections (Essentiel ⇄ Flâner), au-delà du cap (divider « Hors Tournée du jour »).
- Console sans erreurs ; aucun 4xx/5xx réseau inattendu sur la persistance d'ordre.

## Critères d'acceptation
- [ ] Drag démarre depuis le corps de la ligne ET depuis la poignée.
- [ ] Retour visuel (soulèvement) + vibration perceptibles.
- [ ] Boutons d'action toujours fonctionnels.
- [ ] Bouton « Composer ma Tournée » nettement plus visible.

## Vérifs auto déjà passées
- `flutter analyze` (2 fichiers) : No issues.
- `flutter test manage_favorites_sheet_test.dart tournee_composer_sheet_test.dart` : 11/11 ✓.
