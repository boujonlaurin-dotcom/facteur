feat(flaner): onglets épinglés fiabilisés (cap 10, fix « disparus ») + modal 2 onglets

Itération v2 de la modal d'épinglage Flâner (suite #748) : 1 bug + 3 évolutions UX
+ réduction des boutons filtre/recherche. **Mobile/UX only — aucune modif backend.**

## Pourquoi
Quand sources **et** sujets sont épinglés ensemble, des onglets « disparaissent ».
Cause racine (`favorite_topic_tabs.dart`) : tous les onglets étaient triés par `count`
(non-lus) décroissant, or les sources ont `count: 0` codé en dur → toute source passait
derrière tout sujet ayant des non-lus, atterrissait en fin de `ListView` horizontal et
restait cachée derrière le fade `ShaderMask` (pas de cap, pas d'auto-scroll).

## Quoi
- **Chantier 1 — Cap 10 + fix « disparus »** (`favorite_topic_tabs.dart`) :
  `kMaxFavoriteTabs = 10`, **suppression du tri par count** (ordre = insertion puis
  `applyOrder`, aligné sur la modal), cap appliqué après `applyOrder` avec log du surplus
  (pas de troncature silencieuse) + log diagnostic des favoris orphelins (desync).
- **Chantier 2 — Suppression de l'onglet « Tous »** : membre d'enum conservé en no-op.
  Taper l'onglet actif **vide toute la sélection** (`feed_filter_bar.dart`,
  `setTopic/Theme/Entity/Source(null)` — corrige l'oubli historique de `setSource(null)`).
  Suppression de `onTapActiveTabRefresh` + branche `count >= 3`.
- **Chantier 3 — `+` → engrenage si > 4 onglets** : `_AddFavoritePill` reçoit `showGear`,
  action inchangée (ouvre la modal).
- **Chantier 4 — Modal : 2 onglets listes suivies** (`pin_subjects_sheet.dart`) : section
  ÉPINGLÉS (drag interleaved) **inchangée** ; les listes suivies fusionnent en une zone
  « SUIVIS » à 2 onglets (`SegmentedButton`). Sujets en **liste à plat** triée alpha (emoji
  par ligne). Suppression de `_groupByTheme` / `_ThemeGroupHeader` / `pinnableGroups`.
  Placeholder muet si l'onglet actif est vide.
- **Point 4 — Boutons filtre + recherche réduits** : `_SearchTrigger` et le bouton filtre
  (`filter_collapsible_panel.dart`) passent de 38 à 34 px (icônes 16). L'espace horizontal
  libéré profite à la `ListView` des onglets.

## Tests
- `favorite_topic_tabs_test.dart` : assertions « Tous » retirées ; ajout cap-10,
  intercalage sujets/sources, sélection vide → aucun onglet actif.
- `pin_subjects_sheet_test.dart` : liste à plat (en-têtes thème `findsNothing`), 2 segments
  Sources/Sujets, épinglage 1-tap après bascule.
- **26/26 tests verts** sur les 3 fichiers ciblés ; `flutter analyze` 0 nouvelle issue.
- Suite feed : seules régressions = 5 échecs pré-existants `DioException` dans
  `feed_sources_test.dart` (réseau non mocké, hors scope ; CI = backend only).

Story : `docs/stories/core/10.1.sujets-epingles-flaner.md` (section « Itération v2 »).
