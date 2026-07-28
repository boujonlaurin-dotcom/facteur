# fix(essentiel): sources favorites toujours rendues + attente lisible (PR 1)

## Résumé

PR 1 du plan « Accélérer et fiabiliser l'écran Essentiel » : fiabilise la section
**Sources favorites** (elle disparaissait régulièrement de la Tournée) et rend
l'attente des sections **lisible** (shimmer + libellé unique). 100 % mobile,
**aucune migration**, aucun changement backend.

Doc : `docs/bugs/bug-sources-favorites-absentes.md`

## Le bug (2 races au bootstrap de `FluxContinuNotifier`)

La garde `sourceIsEssentiel` (modèle exclusif Story 10.2) est correcte — le bug
vit ailleurs :

1. **Hydratation avalée** : `reconcileEssentielPlacement` (DB → prefs, ce qui
   *restaure* le placement Essentiel après réinstall / nouveau device) se résout
   presque toujours **pendant** le fan-out, fenêtre où `_bootstrapping` rend les
   listeners de prefs muets ⇒ la section n'apparaissait qu'au **cold boot
   suivant**.
2. **Catalogue lazy** : `userSourcesProvider` non résolu ⇒ `if (src == null)
   continue` dans le seed des coquilles **et** dans le fan-out ⇒ drop silencieux
   du favori pour tout le cycle, sans listener pour le rattraper.

## Changements

- `flux_continu_provider.dart`
  - `_reconcilePlacementThenSync()` : chaîne explicitement le résultat de la
    réconciliation (diff avant/après des sources Essentiel + des clés thème
    Flâner) → `_refetchSourcesOnly` / recompose, sans dépendre des listeners.
    La réconciliation reste non-awaitée avant `_fetchAll` (pas de +2 RTT au cold
    boot) ; idempotent si le listener a déjà agi.
  - `_ensureSourceCatalog()` : résolution best-effort du catalogue (borné 2 s,
    erreur avalée) + re-seed des coquilles, **après** l'émission Phase 1 pour ne
    pas retarder le haut de page. Également appelé en tête de
    `_refetchSourcesOnly`. No-op dans le cas nominal.
  - `_disposed` (via `ref.onDispose`) : garde les continuations async lancées
    depuis `build` (Riverpod 2 n'expose pas `ref.mounted`).
- `section_block.dart` : `SectionSkeletonCard` **shimmer** (mêmes teintes que
  `_MetaShimmer`) + libellé unique « Ta tournée se prépare… » rendu **dans** la
  1ʳᵉ carte squelette (hors ShaderMask, zéro hauteur propre ⇒ géométrie stable
  préservée).
- `flux_continu_screen.dart` : câble `showPreparingLabel` sur la 1ʳᵉ coquille non
  résolue (liste live) et sur la 1ʳᵉ section du cold-skeleton.
- `assets/changelog.json` : entrée « Ma Tournée » (unreleased).

## Tests

- Nouveau `flux_continu_sources_races_test.dart` : une race par test, **les deux
  échouent sans les correctifs** (vérifié en revertant chaque fix).
- `section_block_test.dart` : coquille → N cartes shimmer, libellé seulement si
  `showPreparingLabel`.
- `flutter test` complet + `flutter analyze`.

## Hors périmètre

PR 2 (invalidation ciblée + TTL `feed_cache.py`) et PR 3 (SWR client par section)
du même plan.
