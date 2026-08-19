# Maintenance : SWR in-day — les articles de la Tournée en cache local

**Date :** 2026-08-19
**Classification :** MAINTENANCE
**Branche :** `boujonlaurin-dotcom/cold-start-load-order`
**Suite de :** [#1099](maintenance-cold-start-load-order.md) (cold start « héros
d'abord »), et réalise le **périmètre PR 3** annoncé dans
[`maintenance-essentiel-loading-speed.md`](maintenance-essentiel-loading-speed.md)
(§ « Suite : périmètre réel de PR 3 »).

---

## Demande PO

> « Un vrai caching sur les articles pendant la journée. »

### Où en est le lot cold start

| Étape du plan `cold-start-load-order` | État |
|---|---|
| 1 — instrumentation `[PERF]` + doc | livrée (#1099) |
| 2 — B0+C1 (héros peint dans le squelette, squelette scrollable) | livrée (#1099) |
| 3 — B1+B2 (3 vagues, fin des inits furtives) | livrée (#1099) |
| **4 — B3 (fan-out dans l'ordre d'affichage + cap suggestions)** | **livrée (#1099)** — #1098 avait mergé à temps |
| 5 — C2 (cache local des **noms** de coquilles) | droppée |

L'étape 5 telle qu'écrite ne met en cache **que les libellés** des coquilles
(`{sectionKey, label, accent, logoUrl, kind}`), explicitement « affichage
seulement ». Elle ne cache **aucun article** : à une réouverture dans la
journée, l'utilisateur verrait ses sections avec leur vrai nom… et toujours
vides. Ce document remplace donc l'étape 5 par le vrai périmètre demandé, dont
elle devient un sous-produit (l'en-tête minimal est persisté **à côté** des
articles).

---

## Ce qui se passe aujourd'hui à une réouverture in-day (vérifié dans le code)

`flux_continu_provider.dart` `build()` (`:358-382`) lit le snapshot Hive
`flux_continu_cache`. Snapshot du jour + même mode serein ⇒
`_buildStateFromPayload(fetchThemes: false)` (`:753`).

Ce chemin peint **instantanément** :

- la carte héros « Ton Essentiel » (`essentiel_articles` du snapshot) ;
- « Actus du jour » et « Bonnes Nouvelles » (`dual` du snapshot) ;
- la citation du jour.

…et **rien d'autre** : `_themes = _shellThemeSections(...)` et
`_sources = _shellSourceSections(...)` (`:831-832`) produisent des **coquilles
`items: []`**. Les ~10 sections de la Tournée restent vides jusqu'à la fin du
fan-out complet relancé par `_fetchAll()` — soit, sous l'unique worker uvicorn,
plusieurs secondes après le gate JWT, section par section.

Le snapshot ne porte donc **que les 3 blocs éditoriaux**
(`flux_continu_cache_service.dart:102-125` : `dual`, `top_themes`,
`essentiel_articles`). Le contenu de `GET /api/feed` n'est persisté nulle part.

### Les 3 bloquants, re-vérifiés sur `main` (c6221cfc)

Ce sont ceux annoncés dans `maintenance-essentiel-loading-speed.md` ; ils sont
toujours exacts après #1099.

- **B-a — le reseed de revalidation détruirait l'hydratation, visiblement.**
  `_buildStateFromPayload(fetchThemes: true)` réécrit `_themes`/`_sources` en
  coquilles vides et fait `_resolvedSectionKeys.clear()` (`:831-844`), puis
  `sectionTask` appelle `emit()` **inconditionnellement** (`:2725`), hors de la
  garde `emitProgressive`. Inoffensif aujourd'hui (coquilles → coquilles) ; avec
  l'hydratation, la 1ʳᵉ section revalidée publierait un état où **toutes les
  autres sont redevenues vides** ⇒ flash contenu → vide → contenu sur toute la
  page. Le commentaire en place (`:858-862`, « pas de blink des sections
  thèmes/sources ») promet déjà l'inverse de ce que le code fait.
- **B-b — les sections source ne s'hydrateraient pas.** Le chemin
  `fetchThemes: false` retourne (`:853-856`) **avant** `_ensureSourceCatalog`
  (`:885`), et `_shellSourceSections` (`:1076-1098`) lit le catalogue via
  `_peekValue(userSourcesProvider)` — qui, par construction B2, **n'initialise
  pas** le provider ⇒ `null` au boot ⇒ `if (src == null) continue` : chaque
  favori source est droppé. Idem pour la veille (`_skeletonVeilleSection :1031`
  renvoie `null` sans `veilleActiveConfigProvider` résolu) et pour le label des
  sujets custom. ⇒ il faut persister **l'en-tête minimal à côté du raw** (c'est
  là que l'étape 5 est absorbée).
- **B-c — un article balayé réapparaîtrait.** `_dismissedIds` (`:195`) est en
  mémoire seule. Invisible aujourd'hui (rien à réafficher) ; avec
  l'hydratation, c'est le pire ressenti possible.

### Pièges déjà épinglés — à ne pas redécouvrir

- ne **pas** hydrater `_resolvedSectionKeys` (pilote `demote`/`underfilled` ⇒
  saut d'ordre des sections au boot) ;
- ne **pas** hydrater les coquilles « Choisie pour vous » (`onEmpty` retire la
  coquille ⇒ disparition sous le doigt) ;
- `getVeilleFeedItems` (`flux_continu_repository.dart`) **avale les
  DioException** et renvoie un feed vide ⇒ ne jamais persister une section
  **vide** comme légitime (fail-closed) ;
- ne **pas** grossir le snapshot `flux_continu_cache` (~80 KB → ~600 KB) :
  `patchContentConsumed` en fait decode + walk + encode **entier, sur le thread
  UI, au retour de WebView** (`read_sync_service.dart:425`). ⇒ une **entrée Hive
  par section**.

---

## Ce qu'on livre

Un **stale-while-revalidate par section**, borné à la journée :

- à une réouverture in-day, la Tournée est peinte **complète** (articles
  compris) depuis le cache local, sans un seul appel réseau ;
- la revalidation part derrière (les 3 vagues de #1099, inchangées) et remplace
  chaque section **en place**, sans flash ;
- au lendemain (`day_key` différent), le cache est ignoré puis purgé : on
  retombe exactement sur le cold start « héros d'abord » d'aujourd'hui.

### Réutilisation : `FeedCacheService`, pas un nouveau design

`feed_cache_service.dart` fait déjà exactement ça pour la vue Flâner (box Hive
`feed_cache`, valeur `{saved_at, data: <raw API>}`, `patchContentStatus`,
`clearForUser`), et pour la bonne raison : **les modèles feed n'ont pas de
`toJson`** — on persiste le JSON brut et on le repasse dans le parseur existant.
`FeedRepository.getFeedWithRaw` (`:126`) expose déjà ce brut. On étend ce
service à un namespace de clés section plutôt que d'en écrire un second.

---

## Découpage (4 commits, 1 PR, mobile only — aucune migration, aucun backend)

### Commit 1 — le reseed de revalidation préserve le contenu monté (bloquant B-a)

Pré-requis de tout le reste, et **correction utile en soi** : c'est aussi le
comportement attendu du pull-to-refresh.

Dans `_buildStateFromPayload`, quand l'état monté porte déjà du contenu
(`mounted != null && !mounted.isSkeleton`) : reseeder via `_reseedShells`
(`:886` — déjà utilisé pour le re-seed post-catalogue) au lieu d'écraser par
`_shellThemeSections`/`_shellSourceSections`. Les sections dont la clé a disparu
des favoris sortent ; les autres **gardent leurs items** jusqu'à leur
remplacement par `_upsertByKey`. `_resolvedSectionKeys.clear()` est conservé
(on ne réhydrate jamais la classification maigre/riche).

Test : « une revalidation ne publie jamais un état où une section déjà hydratée
est repassée à `items: []` ».

### Commit 2 — persistance + hydratation des sections (le cœur)

**Écriture** — dans `_fanOutSectionsProgressive`, chaque `sectionTask` résolu
**non vide** persiste `{day_key, saved_at, header, data: raw}` :

- `_fetchOneTheme`/`_fetchOneSource` passent à `getFeedWithRaw` (le brut
  remonte jusqu'au `sectionTask`, le parsé reste inchangé) ;
- `header` = `{kind, label, accent, sourceId, sourceLogoUrl, themeSlug,
  customTopicId}` — de quoi reconstruire l'en-tête **sans** `userSourcesProvider`
  ni `veilleActiveConfigProvider` (bloquant B-b, et absorption de l'étape 5) ;
- **jamais d'entrée vide** (fail-closed sur le piège `getVeilleFeedItems`) ;
- clé `tournee:{userId}:{variant}:{sectionKey}` dans la box `feed_cache`
  existante ; `variant` = normal/serein (le contenu est mode-dépendant, comme le
  snapshot Flux).

**Lecture** — dans `_buildStateFromPayload(fetchThemes: false)` uniquement :
pour chaque coquille seedée, si une entrée du jour existe, la remplacer par la
section construite avec les **builders existants**
(`_buildFavoriteThemeSection`/`_buildSourceSection` sur
`FeedRepository.parseFeedData(raw)`). Les entrées orphelines (favori retiré)
sont ignorées ; les clés absentes du seed restent des coquilles. Les sections
source/veille manquantes au seed (B-b) sont **reconstruites depuis le `header`
persisté**. `_resolvedSectionKeys` et les suggestions restent intouchés.

**Cohérence lecture** — `read_sync_service._propagateLocal` (`:394-426`) patche
aussi les entrées section. Pré-filtre sur la **chaîne encodée** (`contains(id)`)
avant tout `jsonDecode` : même stratégie que l'invalidation content-scoped du
backend (`feed_cache.py`), coût nul sur les entrées qui ne portent pas
l'article.

**Purge** — entrées d'un autre `day_key` supprimées au boot (à côté de
`_purgeOldPrefsKeys`) ; `clearForUser` balaie le préfixe `tournee:{userId}:` au
logout.

Instrumentation : `[PERF] fluxContinu.sections_hydrated_ms=<ms> n=<k>/<total>`.

### Commit 3 — `_dismissedIds` persistés par jour (bloquant B-c)

`TourneeProgressService` (déjà porteur des prefs datées : closing dismissed,
score order, `purgeDatedPrefsKeys`) reçoit
`loadDismissedIdsForToday` / `addDismissedIdToday`. Chargés dans
`_buildStateFromPayload` avant le premier `_compose`, purgés avec les autres
clés datées.

### Commit 4 — doc « après » + chiffres mesurés

Diagramme in-day (même métaphore bureau de poste) + mesures.

---

## Tests

- Nouveaux : `tournee_section_cache_service_test.dart` (write/read/day mismatch/
  variant serein/patch par contains/purge préfixe) ; « réouverture in-day : les
  sections sont peintes avec leurs articles **avant** tout appel réseau » ;
  « une section vide n'est jamais persistée » ; « header persisté ⇒ section
  source rendue sans `userSourcesProvider` » ; « revalidation sans flash » ;
  « article balayé toujours absent après réouverture ».
- Doivent rester verts intouchés : `flux_continu_cold_start_waves_test.dart`,
  `flux_continu_block_score_order_test.dart`,
  `flux_continu_progressive_fanout_test.dart`,
  `essentiel_placement_sync_test.dart`.
- Baseline mobile : ~27-33 échecs pré-existants sur `main` (hors périmètre).

## Vérification

1. `cd apps/mobile && flutter analyze && flutter test` (comparé à la baseline
   `main`).
2. QA web Playwright (compte QA staging) : ouvrir la Tournée, laisser le fan-out
   finir, recharger → sections peintes pleines immédiatement ; balayer un
   article puis recharger → il ne revient pas ; pull-to-refresh → aucun blink.
3. Logs `[PERF]` : `sections_hydrated_ms` ≪ `fanout_done_ms`.
4. `/go` en fin de lot (PR base `main`).

## Risques

- **Fraîcheur** : une section cachée à 9 h reste affichée à 18 h jusqu'à la fin
  de la revalidation (quelques secondes). C'est le contrat SWR assumé ; borné
  par la journée.
- **Taille** : ~10 entrées × 30-60 KB. Entrées séparées ⇒ aucun decode global
  sur le thread UI (contrairement au snapshot Flux).
- **Commit 1 touche le chemin pull-to-refresh** (même fonction) : couvert par
  test, et QA manuelle du refresh.
</content>
</invoke>
