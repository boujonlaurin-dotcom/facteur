# Bug — "Prendre du recul" sélectionne une actu du jour, pas une analyse de fond

**Date** : 2026-04-22
**Branche** : `claude/fix-digest-viewpoints-9QcL6`
**Sévérité** : P1 — décrédibilise la promesse "Pas de recul / Prendre du recul"
**Statut** : Plan validé — Axes 1 et 3 implémentés dans ce PR, Axe 2 reporté (voir §6)

---

## 1. Reproduction (capture 3)

Digest du 2026-04-22, sujet #4 "Société" — _Le Texas autorisé à imposer l'affichage des Dix commandements dans les éco…_ (France Info, 4 h).

- Bloc "Prendre du recul" : _"États-Unis : le Texas autorisé à imposer l'affichage des Dix co…"_ (La Croix — Analyses).
- Les deux titres couvrent **le même évènement, au même moment, avec le même cadrage**. La Croix n'apporte ici aucune mise en perspective systémique/structurelle/historique — c'est une dépêche parallèle.
- Critères attendus du bloc (cf. prompt `deep_matching`) : "éclairage systémique, structurel ou historique", "complémentarité avec l'actualité chaude (perspective différente)". Pas respecté.

---

## 2. Flux actuel & points de friction

`editorial/deep_matcher.py::match_for_topics` :

1. `_load_deep_articles` : tous les contenus des sources `source_tier = "deep"` non payants, triés par `published_at desc`, **cap 3000**, **aucun filtre temporel**.
2. `_prefilter` : Jaccard entre tokens (`topic.label + topic.deep_angle`) et (`article.title + topics + description[:200]`), seuil `deep_jaccard_threshold = 0.08`, bonus entités +0.15 max.
3. `_llm_evaluate` : le LLM choisit un index ou renvoie `null`.

### Causes racines

| # | Cause | Détail |
|---|-------|--------|
| A | **Pas de time-gate** dans `_load_deep_articles`. Un article "deep" publié 30 min après l'actu principale reste éligible. | Le candidat La Croix du matin 2026-04-22 est aligné temporellement sur la France Info → ce n'est structurellement pas un "pas de recul". |
| B | Au sein d'une source `source_tier = "deep"`, tous les flux sont agrégés sans distinction : un feed "La Croix — Analyses" peut contenir à la fois des décryptages et des reprises de dépêches. Le tier source ne garantit pas la nature du contenu. | Le mot-clé "Analyses" dans le nom de la rubrique n'est jamais lu. |
| C | Le pré-filtre Jaccard récompense la **similarité lexicale brute** : un article quasi-doublon du titre de l'actu obtient un score très haut et remonte en tête de candidats. Le LLM se contente de valider ce top-1 (biais d'ancrage + `deep_angle` générique produit par `curation`). | Sur un sujet "Texas Dix commandements", les 6-8 mots-clés du titre se retrouvent quasi identiques des deux côtés → Jaccard ≥ 0.5, arbitre LLM peu sollicité. |
| D | Le prompt `deep_matching.system` ne dit pas explicitement : *"REFUSE si le candidat est la même dépêche que l'actu, même publiée par une source deep."* | Cas de rejet manquant. |

La cause **A** suffit à bloquer ~90 % des cas observés : si on impose qu'un "pas de recul" ait au moins `N` heures de recul sur les articles chauds, cet article-ci est automatiquement exclu.

---

## 3. Plan d'implémentation — scope retenu pour ce PR

Axes 1 + 3 implémentés dans ce PR. Axe 2 reporté (voir §6).

### Axe 1 — Time-gate dans le pool deep (fix A) — ✅ DANS CE PR

`editorial/deep_matcher.py::_load_deep_articles` :

- Ajouter un paramètre de configuration `deep_min_age_hours` (défaut **24 h**, valeur sûre choisie pour capital confiance utilisateurs).
- Requête : `Content.published_at <= now - deep_min_age_hours`.
- Exposer la valeur dans `config/editorial_config.yaml` pour réglage opérateur.
- Garder la limite haute à 3000 sans filtre d'ancienneté supérieure (des analyses de fond peuvent être pertinentes plusieurs mois après).

Trade-off assumé : on perd la fenêtre "décryptage du jour même" d'une source deep qui publierait très vite après un évènement. Conforme à la promesse produit ("prendre du recul" ≠ "autre dépêche sur le même évènement").

### Axe 3 — Renforcement du prompt LLM (fix D) — ✅ DANS CE PR

`config/editorial_prompts.yaml::deep_matching.system` : ajouter une règle de rejet explicite :

> REFUSE (`selected_index: null`) si :
> - Le candidat est **une actualité du même évènement** (même fait, même jour, mêmes protagonistes, même cadrage), même publiée par une source de fond.
> - Le candidat n'apporte **aucun éclairage supplémentaire** au-delà du compte-rendu factuel — il doit proposer une mise en contexte historique, structurelle, comparatiste ou analytique.

Pas de changement de température / modèle.

---

## 4. Fichiers modifiés (pour référence)

- `packages/api/app/services/editorial/deep_matcher.py` (Axe 1 — time-gate)
- `packages/api/app/services/editorial/config.py` (Axe 1 — nouveau champ `deep_min_age_hours`)
- `packages/api/config/editorial_config.yaml` (Axe 1 — valeur par défaut)
- `packages/api/config/editorial_prompts.yaml` (Axe 3 — prompt deep_matching)
- `packages/api/tests/editorial/test_deep_matcher.py` (couverture time-gate)

---

## 5. Décisions actées

- **`deep_min_age_hours = 24`** choisi (vs 12 h) : priorité capital confiance utilisateurs. On préfère moins de "Pas de recul" affichés mais de qualité irréprochable.
- **1 seul PR combiné** avec Bug #1 Axe 2 (cf. `bug-digest-perspective-undercount.md`).

---

## 6. Reporté au post-merge (follow-up)

### Follow-up PR (après merge des deux PR en parallèle — la nôtre et celle "Post-filtre de cohérence sujet + masquage UI" de l'agent parallèle)

- **Axe 2 — Rejet Jaccard des quasi-doublons** (`deep_matcher.py::_prefilter`) :
  - Exclure les candidats dont le Jaccard de titre vs les titres du `cluster.contents` dépasse `DEEP_TITLE_SIMILARITY_MAX = 0.6`.
  - Réutiliser `services/text_similarity.py` (extrait par la PR in-reader) pour ne pas dupliquer Jaccard/normalize_title.
  - Harmoniser avec les constantes `PERSPECTIVE_*` pour cohérence digest ↔ in-reader.
  - À évaluer après observabilité : si le time-gate 24 h + prompt strict suffisent en prod (taux de quasi-doublons proche de zéro), l'Axe 2 peut rester optionnel.

- **Axe 4 — Signal `source_subtier = "analysis"`** (hors scope long terme) :
  - Marquer un sous-ensemble de flux comme "analyse pure" (La Croix — Analyses, The Conversation, Alternatives Économiques, etc.).
  - Migration DB + audit des sources requis. Chantier dédié, pas prioritaire tant que Axes 1 + 3 donnent satisfaction.

- **Surveillance post-merge** : observer `deep_matcher.llm_rejections` (taux de rejet doit augmenter avec le prompt durci) et ajouter un log `deep_matcher.time_gate_excluded` pour mesurer combien de candidats sont écartés par la règle d'ancienneté.
