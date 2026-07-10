# Maintenance — Tournée du jour : chargement smooth, fin de tournée, carte veille

> Type : **Maintenance** (polish UX multi-points). Pas de migration, pas de
> changement backend. Cible : `main` (staging continu).

## Contexte

Trois irritants sur la **Tournée du jour** (feature `flux_continu`, app mobile) :

1. **Chargement en 2 salves pas smooth.** L'utilisateur scrolle sur les sections
   prêtes (Essentiel, Actus, Bonnes Nouvelles) puis voit « pop » de nouvelles
   sections et la Tournée se réorganise.
2. **Fin de Tournée — 3 activités → 1 seule, tournante.**
3. **Carte de veille mal dimensionnée** : son titre long (`Ma veille — {config}`)
   wrappe sur 2 lignes, la bannière dépasse le budget de hauteur supposé par le
   snap/fit (`kBannerHeightWithBlurb = 82`) → désalignement du snap.

## Décisions PO (validées)

- **#1 → Squelette stable** : les coquilles réservent la hauteur finale (N cartes
  squelette) + seed des sections « Choisie pour vous » → remplissage **sur place**,
  zéro décalage, zéro section neuve. Ouverture rapide conservée (fan-out borné
  inchangé).
- **#2 → une seule activité** tournante (rotation `dayOfYear` existante).
- **#3 → garder le blurb veille**, mais **tronquer le titre sur 1 ligne** pour ne
  jamais dépasser 82px.

## Implémentation

### Issue #2 — une seule activité tournante
- `utils/closing_activity.dart` : `kClosingActivityCount = 3` → **`1`**. La rotation
  déterministe par `dayOfYear` donne automatiquement une activité différente chaque
  jour. Tests (`closing_activity_test.dart`, `closing_card_v18_test.dart`) déjà
  assis sur la constante → s'adaptent (libellés ajustés).

### Issue #3 — carte veille (titre 1 ligne)
- `widgets/section_banner.dart`, `Text.rich` du titre : `maxLines: large ? 2 : 1`
  + `overflow: TextOverflow.ellipsis`. Les bannières inline (dont veille) tiennent
  sur 1 ligne ; le hero page Flâner (`large`) garde 2 lignes.
- Défensif (même budget 82px) : `maxLines: large ? 3 : 2` + ellipsis sur le `Text`
  du blurb. Pas de changement de `section_fit.dart`.

### Issue #1 — squelette stable (réserver la hauteur + seed des suggérées)
- **A.** `models/flux_continu_models.dart` : champ `bool isPlaceholder` (défaut
  `false`) sur `FeedThemeSection` + `copyWith` (préserve la valeur courante).
- **B.** `widgets/section_block.dart` : branche placeholder dans `_buildCards()`
  **avant** les empty-states → rend `coreVisibleCount` cartes squelette
  (`SectionSkeletonCard`, ≈146px chacune = la hauteur finale). Les empty-states
  restent pour les sections **résolues** vides (`isPlaceholder == false &&
  items.isEmpty`).
- **C.** `providers/flux_continu_provider.dart`, `_capSectionToFit` : early-return
  sur les placeholders (`totalCount == 0` rabattrait sinon la réserve à 1 carte).
- **D.** Seed des sections « Choisie pour vous » : `_shellSuggestedSections`
  produit une coquille placeholder par suggestion utilisable (mêmes
  label/accent/reason/clé que `_buildSuggestedSection`) ; le fan-out fait un
  `_upsertByKey` (au lieu d'append) et `_removeByKey` si la suggestion résout
  vide. Les coquilles sont ordonnées dès la Phase 1 (`_tourneeSectionByKey`).
- **E.** Polish cold-start : `screens/flux_continu_screen.dart`,
  `_FluxContinuSkeleton` rend `coreVisibleCount` `SectionSkeletonCard` par section
  (au lieu d'un seul `ExploreDiscoverySkeleton`) → hauteur stable cold-skeleton →
  Phase 1 → Phase 2.

## Fichiers touchés

- `apps/mobile/lib/features/flux_continu/utils/closing_activity.dart`
- `apps/mobile/lib/features/flux_continu/widgets/section_banner.dart`
- `apps/mobile/lib/features/flux_continu/models/flux_continu_models.dart`
- `apps/mobile/lib/features/flux_continu/widgets/section_block.dart`
- `apps/mobile/lib/features/flux_continu/providers/flux_continu_provider.dart`
- `apps/mobile/lib/features/flux_continu/screens/flux_continu_screen.dart`
- Tests : `closing_activity_test.dart`, `closing_card_v18_test.dart`,
  `flux_continu_provider_test.dart` (test de cap stale 10→13, aligné sur
  `kTourneeVisibleCap`).

## Vérification

- `flutter analyze lib/features/flux_continu/` → No issues found.
- `flutter test test/features/flux_continu/` → 282 passed.
- Résidu accepté (#1.C) : une coquille réserve `coreVisibleCount` (3) vs un fit
  résolu parfois 4-5 → écart ≤ 1 carte (contre 0→N aujourd'hui).
