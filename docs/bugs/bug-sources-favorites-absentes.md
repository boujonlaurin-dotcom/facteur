# Bug — « Sources favorites » absentes de l'Essentiel (+ attente muette des sections)

> Statut : **PR 1 implémentée** (100 % mobile, aucune migration).
> Périmètre : PR 1 du plan « Accélérer et fiabiliser l'écran Essentiel ».

## Symptômes

1. La section **Sources favorites** n'apparaît régulièrement pas dans la Tournée
   du jour (constaté sur main/staging), alors que la source est bien favorite et
   bien placée en mode « Essentiel ».
2. Les sections **Thèmes / Sources** arrivent bien après le haut de page, et
   **rien ne signale** l'attente : coquilles grises statiques, sans animation ni
   libellé — elles se lisent comme un état vide définitif.

## Diagnostic

La garde `TourneeOrderState.sourceIsEssentiel` est **correcte** (modèle exclusif
Story 10.2) : le bug ne vient pas d'elle mais de **deux races** au bootstrap de
`FluxContinuNotifier`.

### Race 1 — l'hydratation du placement est avalée par `_bootstrapping`

`build()` lance `reconcileEssentielPlacement(ref)` en `unawaited` puis enchaîne
le fan-out ; `_bootstrapping` ne repasse à `false` qu'**après** tout le fan-out.
Or la réconciliation (2 GETs) se résout presque toujours *pendant* ce fan-out :
son écriture de prefs (hydratation DB → local, celle qui **restaure**
l'appartenance Essentiel après réinstallation / nouveau device) tombe alors dans
le `if (_bootstrapping) return;` du listener `tourneeOrderPrefsProvider`. Le
placement restauré n'est donc jamais rendu — la section reste absente jusqu'au
**cold boot suivant**.

### Race 2 — catalogue de sources lazy ⇒ favori droppé pour tout le cycle

`_shellSourceSections` et `_fanOutSectionsProgressive` font `if (src == null)
continue` quand le catalogue `userSourcesProvider` (lazy) n'est pas encore
résolu. Aucun listener ne surveille sa résolution seule ⇒ **drop silencieux** de
la section pour tout le cycle.

## Correctifs (PR 1)

| # | Fichier | Fix |
|---|---------|-----|
| 1 | `flux_continu_provider.dart` | `_reconcilePlacementThenSync()` : le résultat de la réconciliation est **chaîné explicitement** (comparaison avant/après des sources Essentiel et des clés thème Flâner) → `_refetchSourcesOnly` / recompose, sans dépendre des listeners ni de `_bootstrapping`. La réconciliation reste **non awaitée** avant `_fetchAll` (sinon +2 RTT sur tous les cold boots). Idempotent : si elle se résout après le bootstrap, le listener a déjà agi ⇒ no-op. |
| 2 | `flux_continu_provider.dart` | `_ensureSourceCatalog()` : force la résolution du catalogue (best-effort, borné à 2 s, erreur avalée) quand des favoris source doivent être rendus, puis re-seed les coquilles. Appelé **après** l'émission Phase 1 (haut de page non retardé) et en tête de `_refetchSourcesOnly`. No-op dans le cas nominal. |
| 3 | `section_block.dart` | `SectionSkeletonCard` **shimmer** (package `shimmer`, calqué sur `_MetaShimmer`) + libellé d'attente unique « Ta tournée se prépare… » rendu **dans** la 1ʳᵉ carte squelette non résolue (zéro hauteur propre ⇒ géométrie stable préservée). |
| 4 | `flux_continu_screen.dart` | Câble `showPreparingLabel` sur la 1ʳᵉ coquille (`firstPreparingIndex`) et sur la 1ʳᵉ section du cold-skeleton. |

Garde-fou ajouté : `_disposed` (posé par `ref.onDispose`, Riverpod 2 n'expose pas
`ref.mounted`) protège les continuations asynchrones lancées depuis `build`.

## Tests

- `test/features/flux_continu/providers/flux_continu_sources_races_test.dart`
  - race 1 : placement DB `essentiel_mode=true` + `tournee_order_v1` vide
    (réinstallation) → la section apparaît **dans le cycle courant** et les prefs
    sont hydratées ;
  - race 2 : catalogue résolu via `Completer` **après** le début du bootstrap →
    la section n'est pas droppée et se remplit.
  - Les deux échouent sans les correctifs (vérifié en revertant chaque fix).
- `test/features/flux_continu/widgets/section_block_test.dart` : coquille →
  N cartes shimmer, libellé présent uniquement si `showPreparingLabel`.

## Hors périmètre (PR 2 / PR 3 du plan)

- Invalidation ciblée + TTL du cache backend `feed_cache.py` (PR 2).
- SWR client par section (snapshot Hive étendu) (PR 3).
