# Bug — Incohérence du clustering entre le carrousel, l'Analyse de biais et le Pas de recul

**Date** : 2026-04-18
**Branche** : `claude/fix-clustering-consistency-gbFsw`
**Sévérité** : P1 — impact UX direct dans l'Essentiel quotidien
**Statut** : Plan en cours de validation

---

## 1. Reproduction

Capture du matin 2026-04-18 pour le sujet "Mort de Nathalie Baye" :

- Le **carrousel** affiche **3 articles** (3 dots, article actif Ouest-France).
- Le bloc **Analyse de biais** affiche **"Fort désaccord · 1 sources"** avec la barre `Gauche (0) · Centre (1) · Droite (0)`.
- L'**analyse développée** ("Lire l'analyse") mentionne **6 médias** : France Info, Gala, Première, Marie France, ladepeche.fr, Ecostylia Magazine.
- Le **Pas de recul** suggère *"Les mines des empires : 10 points sur la géopolitique des…"* — aucun lien avec la mort de l'actrice.

---

## 2. Root Cause Analysis

### 2.1 Trois jeux de données indépendants pour un même sujet

| Compteur UI | Source de données | Fichier |
|---|---|---|
| Carrousel (dots + `DigestTopic.source_count`) | `cluster.source_ids` (articles ingérés dans notre DB dans les 24–48 h) | `briefing/importance_detector.py` → `TopicSelector` |
| Header biais (`perspective_count`) | Google News RSS + DB entity match **filtré sur `bias_stance != "unknown"`**, pivot = article le plus récent du cluster | `editorial/pipeline.py:303-358` via `perspective_service.get_perspectives_hybrid` |
| Analyse LLM développée | Même fetch Google News + DB, mais **liste complète** (y compris `unknown`) | `pipeline.py:415-442` → `perspective_service.analyze_divergences` |

Les trois chiffres **ne peuvent pas coïncider** par construction : ils n'interrogent pas le même pool d'articles. PR #390 avait aligné header/bar/bottom-sheet entre eux (tous basés sur `known_perspectives`) mais **pas avec le carrousel**, qui reste sur `cluster.source_ids`.

### 2.2 Le "Pas de recul" accepte des appariements sémantiquement nuls

`deep_matcher.py` enchaîne :

1. **Pass 1** : pré-filtre Jaccard avec seuil `deep_jaccard_threshold = 0.04` (très permissif, commentaire config : *"bas pour maximiser les candidats LLM"*) + bonus entités (+0.15 max).
2. **Pass 2** : le LLM peut rejeter (`selected_index: null`). Le prompt dit *"selectionne le meilleur"* — formulation biaisée vers la sélection.
3. **Pass 3 broader_fallback** (ligne 157-175) : si Pass 2 rejette, on **baisse le seuil à `threshold * 0.7 = 0.028`**, on élargit la liste, et on prend le top Jaccard via `_fallback_pick` (pas de LLM, seuil min `0.08`).

Conséquence : même quand le LLM a dit "aucun candidat ne convient", le fallback déterministe peut forcer un article de fond totalement hors sujet dès que quelques tokens se recoupent (tokens génériques du `deep_angle` inventé par la curation pour un sujet "people", recul thématique large d'un article sur la géopolitique des mines, etc.).

De plus, le prompt `curation` impose *"deep_angle : 1 phrase decrivant quel angle systemique/structurel chercher"* — il ne prévoit pas de retourner `null` quand le sujet n'a pas d'angle de fond pertinent (people, faits divers, actualité strictement événementielle).

### 2.3 Mapping clair des problèmes

| # | Problème rapporté | Cause technique |
|---|---|---|
| 1 | 3 articles dans carrousel vs 1 source dans biais | `source_count` ≠ `perspective_count` : deux datasets |
| 2 | Analyse LLM mentionne 4–6 médias, différents des deux autres | `analyze_divergences` reçoit la liste brute (inclut `unknown`), là où `perspective_count` l'exclut |
| 3 | Pas de recul hors-sujet | (a) curation force un `deep_angle` artificiel ; (b) broader_fallback déclenche un pick Jaccard après refus LLM |

---

## 3. Plan d'implémentation proposé

### Axe A — Unifier le compteur de sources autour du cluster

**Principe** : le cluster est la **source de vérité** pour "combien de médias couvrent ce sujet ?". Google News ne sert qu'à enrichir l'analyse éditoriale, jamais à définir le compteur affiché.

1. `editorial/pipeline.py::_process_perspectives` :
   - Calculer `bias_distribution` à partir des **sources du cluster** d'abord (`cluster.contents → resolve_bias(domain)`), puis fusionner avec les perspectives Google News filtrées sur les domaines *nouveaux* (non déjà dans le cluster).
   - Définir `perspective_count = len(unique_domains)` où `unique_domains` = domaines du cluster ∪ domaines Google News à biais connu.
   - Garantir l'invariant : `perspective_count >= len(cluster.source_ids)` (on peut avoir plus de perspectives que le cluster, mais jamais moins).
2. `perspective_service.analyze_divergences` : passer la même liste unifiée (cluster + Google News nouveau) et filtrer les `unknown` avant l'envoi LLM, pour que la prose mentionne exactement les mêmes médias que le compteur.
3. Mobile (`divergence_analysis_block.dart`) : garder `perspectiveCount` tel quel (nouvelle définition serveur cohérente), pas de changement client.

### Axe B — Rendre le "Pas de recul" rigoureux

1. `config/editorial_prompts.yaml::deep_matching.system` :
   - Reformuler pour exiger un **lien thématique explicite** ; la consigne par défaut doit être *"en cas de doute, retourner null"*.
   - Ajouter un test de pertinence explicite dans le prompt : *"Le candidat partage-t-il au moins 2 entités nommées ou un angle structurel commun avec le sujet ? Sinon → null."*
2. `config/editorial_prompts.yaml::curation.system` :
   - Autoriser `deep_angle: null` quand le sujet est purement événementiel / people / faits divers ("si aucun angle systémique n'est pertinent, renvoyer `deep_angle: null` et ne pas forcer").
3. `editorial/deep_matcher.py::match_for_topics` :
   - Skipper Pass 1–3 pour les topics avec `deep_angle` null/empty.
   - **Supprimer Pass 3 broader_fallback** : si le LLM a rejeté, on respecte la décision (pas d'override déterministe).
   - Monter `_fallback_pick.min_score` de `0.08` → `0.15` (il ne sert plus qu'en cas d'exception LLM).
4. `config/editorial_config.yaml::deep_jaccard_threshold` : monter `0.04` → `0.08`. Le seuil actuel est "bas pour maximiser les candidats LLM", mais avec un prompt stricter et sans Pass 3, on peut resserrer sans perdre de couverture utile.

### Axe C — Observabilité

1. Logger dans `pipeline` la composition finale des perspectives : `{cluster_count, google_news_added, total_known_bias}` pour pouvoir vérifier en prod que les 3 chiffres sont cohérents.
2. Logger le taux de rejet LLM sur deep_matching (avant/après fix) pour mesurer l'impact de la rigueur accrue sur le taux de "Pas de recul" affichés.

---

## 4. Fichiers à modifier

### Backend
- `packages/api/app/services/editorial/pipeline.py` (Axe A — `_process_perspectives`)
- `packages/api/app/services/perspective_service.py` (Axe A — fusion cluster + GNews)
- `packages/api/app/services/editorial/deep_matcher.py` (Axe B — skip null angle, suppression broader_fallback, seuil min)
- `packages/api/config/editorial_prompts.yaml` (Axe B — prompts deep_matching + curation)
- `packages/api/config/editorial_config.yaml` (Axe B — `deep_jaccard_threshold`)
- `packages/api/app/services/editorial/schemas.py` (Axe B — `SelectedTopic.deep_angle: str | None`)

### Tests
- `packages/api/tests/editorial/test_pipeline.py` : invariant `perspective_count >= cluster_sources`, cohérence distribution.
- `packages/api/tests/editorial/test_deep_matcher.py` (à créer si absent) : rejet respecté, pas de broader fallback, topics sans `deep_angle` skippés.
- Pas de changement mobile nécessaire (champ `perspective_count` garde son nom, sémantique serveur alignée).

---

## 5. Test plan manuel

1. Rebuild digest local via `uvicorn` + lancer `python scripts/run_editorial_pipeline.py` (ou équivalent) sur un dataset contenant :
   - un sujet "people" (pas d'angle de fond) → vérifier `deep_article = null`, aucun "Pas de recul" affiché.
   - un sujet multi-source ciblé (ex: climat, élection) → vérifier `perspective_count >= source_count`, les médias de la prose = médias du compteur.
2. Vérifier sur l'app mobile (Chrome) que les 3 affichages (carrousel, header biais, analyse développée) mentionnent des nombres/médias cohérents.

---

## 6. Questions / points à valider avec l'utilisateur

- **Axe A** : ok pour que `perspective_count` inclue les sources du cluster (auparavant il ne contenait que les perspectives *externes*, Google News) ? Cela peut faire augmenter le chiffre affiché pour certains sujets.
- **Axe B** : ok pour accepter une baisse du taux de "Pas de recul" (fréquence plus faible mais pertinence plus haute) ?
- **Timing** : fix combiné (A + B + C) dans un seul PR, ou séparer A (aligner compteurs) et B (stricter prompt) pour minimiser le blast radius ?
