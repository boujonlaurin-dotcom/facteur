# Bug — Sources de la Tournée du Jour qui se perdent / reviennent en Flâner

## Symptôme

Les sources ajoutées à la **Tournée du Jour** (l'Essentiel) ne s'enregistrent pas
durablement : elles « se perdent régulièrement », disparaissent des paramètres et de
la modal « Mes favoris », et **réapparaissent en Flâner** (hors Tournée).

## Racine

L'appartenance d'une source à l'Essentiel = présence de la clé `source:<id>` dans la
liste locale `tournee_order_v1` (`tourneeOrderPrefsProvider`). Le statut « favori » vit
côté serveur. Une source favorite **absente** de `tournee_order_v1` est rendue en
Flâner → d'où la réapparition « hors Tournée » dès que la clé quitte l'ordre.

Chemin destructeur : le réordre dans `manage_favorites_sheet.dart`.

- `onReorder` → `_persistEssentielReorder(reordered)` fait
  `setOrder(ordered.map((e) => e.key))` : **réécrit tout `tournee_order_v1` à partir des
  seules tuiles rendues à cet instant**.
- Une tuile peut ne pas être matérialisée : `final source = sourceById[f.sourceId];
  if (source == null) continue;` — si le catalogue (`userSourcesProvider`) n'a pas encore
  résolu cet id, le favori est **sauté**. Idem pour une clé dans `hiddenKeys`.
- Résultat : un réordre alors que les données ne sont pas pleinement chargées
  **supprime silencieusement** du `tournee_order_v1` les clés non rendues → la source
  cesse d'être Essentiel → repasse en Flâner.

Même défaut en miroir dans `_persistFlanerReorder` sur `tabOrderPrefsProvider`.

Vérifié : aucun autre appelant de `setOrder` n'élague (append-only ou remove d'une seule
clé). Le listener Tournée ne réécrit jamais l'ordre.

## Fix (prefs locales uniquement — aucun changement backend/schéma)

Rendre la persistance du réordre **non destructive** : un réordre ne fait que permuter
les clés effectivement rendues ; toute clé d'ordre préexistante non rendue cette frame
est **préservée**. Seul `_onRemove` retire une clé.

**Bonus alignement de l'ordre** (demande PO) : au lieu d'ajouter les clés préservées
*en queue*, on **préserve leur position absolue** dans l'ordre (on ne permute que les
emplacements occupés par des clés visibles). Ainsi l'ordre rendu de la Tournée reste
aligné sur ce que l'utilisateur a paramétré, sauf dépriorisation « manque de contenu »
(thin demotion, qui ne joue que sur l'ordre par défaut non-customisé — un ordre
customisé est déjà sticky via `applyOrder`).

### Helper partagé : `mergeVisibleReorder` (dans `tab_order_prefs_provider.dart`)

Fonction pure, à côté de `applyOrder` (déjà réexportée par le provider Tournée) :
fusionne le réordre partiel `visibleOrder` dans `prevOrder` sans rien perdre, en gardant
les clés non rendues à leur place. Testable unitairement.

### `manage_favorites_sheet.dart`

- `_persistEssentielReorder` : garde-fou de chargement (interests + sourcesState non
  null) ; `setOrder(mergeVisibleReorder(prevOrder, renderedKeys))` ; le reste inchangé.
- `_persistFlanerReorder` : même pattern contre `tabOrderPrefsProvider`.

### Aucune modification de
- `tournee_order_prefs_provider.dart` — `setOrder` reste un writer « liste entière ».
- `flux_continu_provider.dart` — `_orderedTourneeKeys` honore déjà `order` via
  `applyOrder` (la demotion thin ne touche que l'ordre par défaut).

## Tests (lock de régression)

`apps/mobile/test/features/flux_continu/widgets/manage_favorites_sheet_test.dart` :
1. Réordre avec catalogue partiellement chargé ne perd pas une source Essentiel non
   résolue (clé `source:s2` survit + `sourceIsEssentiel('s2') == true`).
2. Réordre préserve une clé éditoriale masquée (`hiddenKeys`).
3. Symétrie Flâner : clé `source:` non résolue dans `pinned_tabs_order_v1` survit.

Unitaire `mergeVisibleReorder` : préservation de position + pas de perte + clés visibles
nouvelles en queue.

## Vérification

```bash
cd apps/mobile
flutter test test/features/flux_continu/widgets/manage_favorites_sheet_test.dart
flutter test && flutter analyze
```
