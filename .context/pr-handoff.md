# L'Essentiel : cartes qui ne dépassent jamais l'écran (+ footer auto-hide)

## Résumé

Dans **Flux Continu / L'Essentiel**, une carte plus haute que l'écran gagnait une
« free-read interior » qui se battait avec le snap inter-sections. Cette PR
garantit qu'**aucune carte ne dépasse la hauteur utile de l'écran** (bouton
« Lire plus » inclus) → `_tallSections` vide → 1 point de snap par section, feel
cohérent page par page. **1 seule PR** (validée PO).

## Décision d'architecture — « estimer pour contrôler, mesurer pour vérifier »

Le « combien d'articles tiennent » est décidé **côté provider** par une estimation
de hauteur **conservatrice** (titre à son `maxLines` max), pas de mesure runtime
qui pilote le rendu. La mesure post-frame (`_recomputeSnapAnchors` /
`_tallSections`) sert de **filet QA**. Budget **identique au snap** :
`usableHeight = scrollViewportHeight − safeAreaBottom − _kStickyBarHeight`.

« Le héros qui ne tient pas sort du pool et réapparaît ailleurs » est gratuit :
trimmer la liste du héros **avant** le dédup inter-sections relâche les articles
éjectés vers les sections aval qui portent le même `contentId`.

## Changements

- **A. Footer auto-hide app-wide** : `footerVisibleProvider` + `AnimatedSlide`/
  `IgnorePointer` sur `MainBottomNav` ; `_onScroll` (Essentiel + Flâner) ;
  re-visible au changement d'onglet / scroll-to-top.
- **B. Compaction légère** : héros `maxLines 5→4` (lead) / `4→3` (medium) + paddings
  resserrés (pastille date/météo conservée) ; sticky `48→44` + `_kStickyBarHeight
  54→50`.
- **C. Fit dynamique** : `utils/section_fit.dart` (pur) ; `usableViewportHeightProvider`
  écrit par l'écran (anti-boucle) ; `_compose` trim héros + cap sections aval
  (`min(défaut, fit)`, plancher 1) ; `FeedThemeSection.copyWith` +param
  `coreVisibleCount`.
- **D. Filet** : `assert` debug dans `_recomputeSnapAnchors` qui logge toute
  section multi-articles restée « tall ».

## Tests
- `section_fit_test.dart` (12) : bornes `fitVisibleCount`/`fitHeroCount` (3/2/1,
  jamais 0 ; héros garde le lead).
- `flux_continu_provider_test.dart` (+4) : trim héros, réapparition aval de l'id
  éjecté, cap aval ≤ défaut & ≥ 1, `+N` correct, cap survit au dismiss, copyWith
  préserve `coreVisibleCount`.
- `section_block_test.dart` : `+N` à `coreVisibleCount` réduit (+ correction des
  lambdas `onTapArticle` héritées de #787 → fichier re-compilable, net positif).
- `flutter analyze` : 0 issue sur les fichiers touchés.
- ⚠️ Échec pré-existant non lié : `essentiel_hi_fi_card_test` « flips to the
  weather badge » (échoue déjà sur `main`).

## QA visuelle
Voir `.context/qa-handoff.md` — Chrome/Playwright **390×844** ET **360×640**
(cartes ≤ écran, footer slide, snap+haptique non régressés).

## Hors périmètre
Grille / Citation / carte « Pour toi » / closing card (slivers virtuels) ; cartes
article standard inchangées (choix PO « héros uniquement »).
