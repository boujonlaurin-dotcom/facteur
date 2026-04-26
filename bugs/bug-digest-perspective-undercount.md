# Bug — Perspectives manquantes sur des sujets multi-sources du digest

**Date** : 2026-04-22
**Branche** : `claude/fix-digest-viewpoints-9QcL6`
**Sévérité** : P1 — dégrade la promesse produit ("comparaison de points de vue")
**Statut** : Plan validé — scope réduit pour éviter conflit avec la PR in-reader en parallèle (voir §6)

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

## 3. Plan d'implémentation — scope retenu pour ce PR

**Un seul axe est implémenté dans ce PR** : Axe 2 (filet de sécurité). Les Axes 1 et 3 sont reportés (voir §6).

### Axe 2 — Filet de sécurité `perspective_count` (fix D) — ✅ DANS CE PR

`editorial/pipeline.py::_process_perspectives` :

- Si `known_perspectives` finit vide **mais** `cluster.source_ids` a ≥ 1 élément, garder au moins la source représentative dans `perspective_articles` (avec `bias_stance = "unknown"`) et fixer `perspective_count = len(cluster.source_ids)`.
- `divergence_analysis` reste `None` (le plancher `>= 3 merged_perspectives` est maintenu — pas de texte LLM quand on n'a pas la matière).
- Côté mobile, `DivergenceAnalysisBlock` reste masqué tant que `divergence_analysis` est `null`, mais le compteur de sources du footer card reflète correctement le cluster réel au lieu de tomber à 1 quand la source principale est `bias = unknown`.

Choix motivé : option "honnête" (on ne ment pas sur le nombre de sources) plutôt que de forcer une analyse de biais sur un échantillon de 2.

---

## 4. Fichiers modifiés dans ce PR

- `packages/api/app/services/editorial/pipeline.py` (Axe 2)
- `packages/api/tests/editorial/test_pipeline.py` (couverture filet de sécurité)

---

## 5. Décisions actées

- **Option retenue pour Axe 2** : garder la source du cluster avec `bias_stance = "unknown"` quand aucun biais n'est connu. Pas de bascule du plancher `analyze_divergences` à `>= 2` (l'analyse LLM reste réservée aux sujets avec ≥ 3 sources à biais connu).
- **1 seul PR combiné** avec Bug #2 (cf. `bug-digest-pas-de-recul-same-event.md`).

---

## 6. Reporté au post-merge (follow-up)

Ces deux axes sont volontairement écartés de ce PR pour éviter une dette de maintenance avec la PR **"Post-filtre de cohérence sujet + masquage UI"** (agent parallèle) qui :
- Extrait `normalize_title` + `jaccard_similarity` dans `services/text_similarity.py`.
- Ajoute un post-filtre `is_topically_coherent` dans `perspective_service.get_perspectives_hybrid`.
- Introduit `should_display` et constantes `PERSPECTIVE_TITLE_JACCARD_MIN=0.30`, `PERSPECTIVE_MIN_VALID_RESULTS=2`, `PERSPECTIVE_MIN_BIAS_GROUPS=2`.
- Touche `routers/contents.py:626-638` (en conflit direct avec notre Axe 3).

### Follow-up PR (après merge des deux PR)

- **Axe 1 — Boost clustering via entités nommées** (`briefing/importance_detector.py::build_topic_clusters`) :
  - Réutiliser `services/text_similarity.py` (extrait par l'autre PR) au lieu de ré-implémenter Jaccard/normalize_title.
  - Harmoniser les constantes de seuil avec `PERSPECTIVE_TITLE_JACCARD_MIN` pour que clustering digest et post-filtre in-reader parlent le même langage.
  - Règle : fusion additive si ≥ 2 entités `PERSON`/`ORG`/`EVENT` partagées ET Jaccard titre ≥ 0.25.
  - Garde le seuil 0.4 sur la voie "titre seul" pour ne pas régresser sur les sujets sans entités.

- **Axe 3 — Re-enrichissement paresseux côté endpoint** (`routers/contents.py::_load_stored_perspectives_for_representative`) :
  - Réévaluer après merge : si le post-filtre + `should_display` de l'autre PR gèrent déjà correctement l'UX (bottom-sheet vide proprement quand couverture insuffisante), l'Axe 3 devient largement redondant.
  - Décision à trancher à ce moment-là : garder uniquement la bascule live quand `len(stored) < 3`, **ou** supprimer complètement (si `should_display` suffit).

- **Surveillance post-merge** : log `topic_clustering_complete.total_contents` et `editorial_pipeline.perspectives_composition` pour identifier si le pool `_get_global_candidates = 200` est devenu trop étroit. Si oui, ticket dédié pour passer à 500.
