# Bug — Perspectives manquantes sur des sujets multi-sources du digest

**Date** : 2026-04-22
**Branche** : `claude/fix-digest-viewpoints-9QcL6`
**Sévérité** : P1 — dégrade la promesse produit ("comparaison de points de vue")
**Statut** : Plan à valider

---

## 1. Reproduction (capture 1)

Digest du 2026-04-22, sujet #2 "Société" — _Fuite ANTS : près de 12 millions de comptes concernés_ (Frandroid, 32 min).

- La carte n'affiche **qu'un seul logo** + "· 32 min" : pas de "+N", pas de `DivergenceAnalysisBlock` ("Voir tous les points de vue", barre Gauche/Centre/Droite).
- Pourtant, en ouvrant le même article et en déroulant "Voir tous les points de vue" (capture 2), la bottom-sheet liste **plusieurs sources** à biais connu (Mediapart, franceinfo, …) sur le même évènement, avec une vraie barre `Gauche · Centre · Droite`.

Autrement dit : **la donnée existe côté DB / Google News, mais la pipeline ne l'a pas incorporée dans `perspective_count` / `perspective_articles` du sujet**, donc le mobile masque le bloc d'analyse de biais.

---

## 2. Flux actuel & points de friction

`editorial/pipeline.py::_process_perspectives` enchaîne :

1. Cluster Jaccard (seuil `0.4`) → `cluster.contents` (articles de **notre DB** sur les 48 h, pool plafonné à **200**).
2. `build_cluster_perspectives(cluster.contents)` — 1 Perspective par `source_id` unique.
3. Augmentation Google News (`get_perspectives_hybrid`) — limitée à `max_results=10`, dépend d'un index Google News au moment T.
4. Merge → filtre `bias_stance != "unknown"` → `perspective_count`, `perspective_articles`, `bias_distribution`.
5. `analyze_divergences` appelé **uniquement si `len(merged_perspectives) >= 3`**.

### Causes racines probables (cumulatives, pas exclusives)

| # | Cause | Impact observé |
|---|-------|----------------|
| A | Seuil Jaccard **0.4** sur titres normalisés : deux titres qui décrivent le même évènement avec un cadrage différent (Frandroid "Fuite ANTS" vs Mediapart "Fuite de données à l'ANTS") peuvent basculer en clusters séparés → le sujet sélectionné hérite d'un cluster singleton. | Cluster sous-dimensionné (1 source), la bottom-sheet live ramasse ensuite la vraie couverture via Google News, d'où l'écart. |
| B | Génération à 08 h Paris = **snapshot figé** : les sources qui publient après 08 h ou ne sont pas encore indexées par Google News à 08 h ne rentrent jamais dans `perspective_articles`. Le store JSONB ne se ré-enrichit pas. | Pour les breaking news matinales, `perspective_count` reste collé à 1-2 tandis que la bottom-sheet live explose à 8-10. |
| C | Pool `_get_global_candidates` limité à **200** articles en 48 h : si le volume RSS dépasse 200, des articles frais peuvent être écartés (ORDER BY `published_at desc` joue en notre faveur mais ne couvre pas les retards d'ingestion). | Cluster partiel à la génération, symptôme indifférenciable de (A). |
| D | `bias_stance` DB/map incomplet sur certaines sources tech (ex : `frandroid.com` absent de `DOMAIN_BIAS_MAP`, bias DB = `unknown`) → la source du sujet elle-même est filtrée hors de `known_perspectives`, `perspective_count` = 0 même quand le cluster a 1-2 sources. | Carte sans barre de biais alors que le cluster n'est pas vide. |

La cause **A** explique le mieux le cas "Fuite ANTS" (les autres sources étaient bien publiées avant 08 h mais avec un autre cadrage). **D** explique pourquoi `perspective_count` peut tomber à 0 même avec un cluster non vide.

---

## 3. Plan d'implémentation (proposé)

Trois axes indépendants, livrables séparément si besoin.

### Axe 1 — Boost clustering via entités nommées (fix A)

`briefing/importance_detector.py::build_topic_clusters` : ajouter un **matching par entités nommées** en complément du Jaccard de titres.

- Pour chaque article, récupérer les entités `PERSON`/`ORG`/`EVENT` (déjà stockées dans `Content.entities`).
- Règle de fusion additive : si deux clusters partagent ≥ 2 entités nommées ET que leur Jaccard titre ≥ 0.25 (seuil dégradé), alors fusionner.
- Conserver le seuil par défaut `0.4` pour la voie "titre seul" (pas de régression sur les sujets sans entités).

Pas de changement de `TOPIC_CLUSTER_MAX_TOKENS`.

### Axe 2 — Filet de sécurité `perspective_count` (fix D)

`editorial/pipeline.py::_process_perspectives` :

- Si `known_perspectives` finit vide **mais** `cluster.source_ids` a ≥ 1 élément, garder au moins la source représentative dans `perspective_articles` (avec `bias_stance = "unknown"`) et fixer `perspective_count = len(cluster.source_ids)`. La barre de biais reste masquée côté mobile quand `bias_distribution` est toute à 0, mais le `DivergenceAnalysisBlock` s'affiche si `divergence_analysis` ou `bias_highlights` est non-nul.
- Alternative moins invasive : baisser le plancher `analyze_divergences` de `>= 3` à `>= 2` pour récupérer les cas "Frandroid + 1 autre". Permet au moins d'afficher un texte de contexte.

À arbitrer ensemble (voir section 5).

### Axe 3 — Re-enrichissement paresseux côté endpoint (fix B)

`routers/contents.py::_load_stored_perspectives_for_representative` : si `len(stored) < 3`, **ignorer le snapshot** et basculer sur le live path (`get_perspectives_hybrid` + merge cluster). Le coût LLM reste nul (l'analyse de divergence n'est pas refaite ici), on consomme uniquement un appel Google News déjà caché en amont par le TTLCache `_perspectives_cache` (2 h).

Cela rend la bottom-sheet cohérente avec ce que l'utilisateur voit **au moment où il clique**, sans refaire la digest. Effet secondaire : le count affiché dans la bottom-sheet peut dépasser le count de la card — assumé, le header card reste le snapshot du matin.

Pool `_get_global_candidates` (cause C) : on ne touche pas dans ce PR, sauf si le volume RSS explose (à surveiller via logs `topic_clustering_complete.total_contents`).

---

## 4. Fichiers modifiés (pour référence)

- `packages/api/app/services/briefing/importance_detector.py` (Axe 1)
- `packages/api/app/services/editorial/pipeline.py` (Axe 2)
- `packages/api/app/routers/contents.py` (Axe 3)
- Tests : `packages/api/tests/briefing/test_importance_detector.py`, `tests/editorial/test_pipeline.py`, `tests/contents/test_perspectives_endpoint.py`

---

## 5. Questions à valider

1. **Axe 1** : ok pour élargir les fusions via entités (peut augmenter légèrement le taux de faux positifs sur des sujets qui partagent "Macron" mais pas l'évènement) ?
2. **Axe 2** : préférence "garder la source seule avec bias unknown" ou "baisser plancher analyse à ≥ 2" ? Impact UX différent.
3. **Axe 3** : ok pour laisser la bottom-sheet diverger du header card quand la couverture évolue entre 08 h et la lecture ?
4. **Périmètre** : 3 axes dans 1 PR, ou séparer Axe 1 (clustering) des Axes 2/3 (affichage) ?
