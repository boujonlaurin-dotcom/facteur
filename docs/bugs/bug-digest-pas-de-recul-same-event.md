# Bug — "Prendre du recul" sélectionne une actu du jour, pas une analyse de fond

**Date** : 2026-04-22
**Branche** : `claude/fix-digest-viewpoints-9QcL6`
**Sévérité** : P1 — décrédibilise la promesse "Pas de recul / Prendre du recul"
**Statut** : Plan à valider

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

## 3. Plan d'implémentation (proposé)

Trois axes, livrables indépendants, priorités dans l'ordre (A seul résout la plupart des cas).

### Axe 1 — Time-gate dans le pool deep (fix A)

`editorial/deep_matcher.py::_load_deep_articles` :

- Ajouter un paramètre `min_age_hours` (par défaut dans `EditorialConfig.pipeline.deep_min_age_hours = 24`).
- Requête : `Content.published_at <= now - min_age_hours`.
- Exposer la valeur dans `config/editorial_config.yaml` pour réglage opérateur.
- Garder la limite haute à 3000 sans filtre d'ancienneté supérieure (des analyses de fond peuvent être pertinentes plusieurs mois après).

Trade-off : on perd la fenêtre "décryptage du jour même" d'une source deep qui publie très vite après un évènement. C'est acceptable et conforme à la promesse produit ("prendre du recul" ≠ "autre dépêche sur le même évènement").

### Axe 2 — Rejet des quasi-doublons (fix C)

`editorial/deep_matcher.py::_prefilter` :

- Après scoring, **exclure** tout candidat dont le Jaccard de titre (pas label+angle, uniquement `article.title` vs les titres du `cluster.contents`) dépasse `DEEP_TITLE_SIMILARITY_MAX = 0.6`.
- Fournir `cluster_titles` via `match_for_topics` (en sus de `cluster_entities`).
- Logger `deep_matcher.near_duplicate_rejected` pour surveillance.

### Axe 3 — Renforcement du prompt LLM (fix D)

`config/editorial_prompts.yaml::deep_matching.system` : ajouter une règle de rejet explicite :

> REFUSE (`selected_index: null`) si :
> - Le candidat est **une actualité du même évènement** (même fait, même jour, mêmes protagonistes, même cadrage), même publiée par une source de fond.
> - Le candidat n'apporte **aucun éclairage supplémentaire** au-delà du compte-rendu factuel — il doit proposer une mise en contexte historique, structurelle, comparatiste ou analytique.

Pas de changement de température / modèle.

### Axe 4 (optionnel, à discuter) — Signal de type "analyse" côté source

Marquer un sous-ensemble de flux comme `source_subtier = "analysis"` (ex : "La Croix — Analyses", "The Conversation", "Alternatives Économiques"). Restreindre le pool deep à ce sous-ensemble **si** `subtier == "analysis"` est disponible, sinon fallback sur `source_tier == "deep"`.

Hors scope du présent fix — demande une migration DB + audit des sources. Seulement mentionné pour mémoire.

---

## 4. Fichiers modifiés (pour référence)

- `packages/api/app/services/editorial/deep_matcher.py` (Axes 1 + 2)
- `packages/api/app/services/editorial/config.py` + `config/editorial_config.yaml` (Axe 1 — param `deep_min_age_hours`)
- `config/editorial_prompts.yaml` (Axe 3)
- Tests : `packages/api/tests/editorial/test_deep_matcher.py` — cas time-gate, cas near-duplicate, cas LLM rejette correctement.

---

## 5. Questions à valider

1. **Axe 1** : valeur par défaut de `deep_min_age_hours` — 24 h (sûr mais filtre aussi les décryptages rapides légitimes) ou 12 h (moins restrictif) ?
2. **Axe 2** : seuil `DEEP_TITLE_SIMILARITY_MAX` — 0.6 (strict) ou 0.5 (très strict) ? Un seuil trop bas peut rejeter de vraies analyses qui réutilisent des mots-clés du sujet.
3. **Axe 4** : d'accord pour l'écarter de ce fix (demande un chantier dédié) ?
4. **Périmètre PR** : Axes 1 + 3 suffisent-ils pour ce tour, Axe 2 en PR suivant ? Ou tout en un seul PR ?
