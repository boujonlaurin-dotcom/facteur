# Maintenance — Diversité source + dédup cluster dans Flâner (et durcissement Essentiel)

> Type : Maintenance (tuning curation, backend-only, 100 % runtime, aucune
> migration Alembic). Plan de référence : `.context/attachments/3zHeEv/plan.md`.

## Problème

Dans « Flâner » (`GET /api/feed/`, mode par défaut / chronologique) :

1. **Répétition de source** — le pipeline n'espaçait que les runs de **3+
   consécutifs** (`_apply_source_interleaving` testait `i-1` ET `i-2`). On peut
   donc voir 2 articles de la même source **collés**.
2. **Doublons de cluster** — le scroll linéaire ne dédupliquait pas par sujet.
   Le même événement couvert par plusieurs sources apparaissait plusieurs fois
   (les regroupements entité/mot-clé ratent les doublons narratifs à titres
   proches mais entités différentes). `Content.cluster_id` persisté est dormant
   (~1,3 % des articles récents) → inutilisable.
3. **Essentiel** — cap **2 articles/source** jugé trop permissif par le PO.

## Décisions PO

1. Espacement local : jamais 2 articles même source collés (réordonne
   seulement, ne retire aucun article ; best-effort si la fin est mono-source).
2. Masquer les doublons de cluster dans le flux (garder le 1er = plus récent),
   **sans casser le carrousel « Actu chaude »** qui doit toujours voir la
   couverture multi-sources complète.
3. Durcir l'Essentiel : cap source **2 → 1**, avec fallback anti-régression.

## Changements

### 1. `recommendation_service.py :: _apply_source_interleaving`
Resserré : boucle `range(1, n)`, teste uniquement `result[i] == result[i-1]`,
swap avec le prochain article d'une **autre** source. Best-effort (aucune
exception, aucun retrait si la queue est mono-source). Le safety-net
3-consécutifs (`_apply_source_safety_net`) reste en place, désormais rarement
déclenché.

### 2. `recommendation_service.py :: _apply_cluster_dedup` (nouveau)
Appelé dans `get_feed()` (chemin chronologique) **juste après** le snapshot
`pre_regroup_map` et **avant** l'entity regroupement. Recalcule les clusters à
la volée via `ImportanceDetector().build_topic_clusters` (Jaccard 0.4, même algo
qu'« Actu chaude »), puis `diversify(max_per_key=1, fallback_ok=False)` garde le
1er article par cluster.

> **Invariant clé** : `_apply_cluster_dedup` ne **mute pas** sa liste d'entrée.
> `pre_regroup_map` étant capturé AVANT l'appel, le carrousel « Actu chaude »
> (`_build_carousels` → `find_hot_cluster`, qui consomme `pre_regroup_map`)
> conserve la couverture complète. Le sujet apparaît une fois dans le flux +
> éventuellement comme carrousel de couverture. Le buffer `phase1_limit =
> limit * 3` garantit assez d'articles après masquage.

### 3. `essentiel_service.py :: ESSENTIEL_MAX_PER_SOURCE 2 → 1` + fallback
- Constante `ESSENTIEL_MAX_PER_SOURCE = 1`, nouveau `_MAX_PER_SOURCE_FALLBACK = 2`.
- `_pick_transversal_articles` (digest anchor) : cap porté par une variable
  `max_per_source` lue par `_try_pick`. Après la 1re passe cap 1, si les 5 slots
  ne sont pas remplis (trop peu de sources distinctes), 2e passe à cap 2.
- `_fetch_live_supplements` (blend live) : sélection refactorée en `_fill(cap)`
  ré-exécutée à cap 2 si le pool cap 1 n'atteint pas `limit`.
- Rationale : cap 1 maximise la diversité source ; le fallback cap 2 évite une
  carte pauvre / un `202 preparing` sous `ESSENTIEL_MIN_ARTICLES`. Même logique
  que `DigestSelector._select_with_diversity` (fallback source si trop peu de
  sources). La 2e passe est idempotente (articles déjà pris re-rejetés) et ne
  relâche QUE la diversité source — la diversité de **sujet** reste garantie par
  `_is_duplicate_subject`/`used_topics`.

## Réutilisation (aucun nouveau code de clustering/dédup)
`ImportanceDetector.build_topic_clusters`, `diversify`, pattern fallback de
`digest_selector`.

## Tests
- `tests/test_feed_diversity_dedup.py` (nouveau) — interleaving (zéro paire
  adjacente + best-effort mono-source), dédup cluster (masquage + **non-mutation
  de l'entrée** = couverture carrousel préservée).
- `tests/test_essentiel_endpoint.py` — cap 1/source respecté (≥5 sources) ;
  fallback cap 2 quand sources rares (pas de régression `202`).
- `tests/test_essentiel_supplements.py` — cap 1 dans le blend live (pool
  diversifié) ; l'ancien `test_max_two_articles_per_source` reste vert (plafond
  dur 2 via fallback).

## Alembic
Aucune migration. `alembic heads` reste à 1 head (inchangé).
