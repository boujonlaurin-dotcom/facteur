# Bug — Bonnes Nouvelles plus pertinentes après LR-1 PR 2 (coupes de coût Mistral)

## Symptôme

Le PO signale que les **Bonnes Nouvelles** (feature clé) ne sont plus du tout
pertinentes depuis la PR de réduction de coûts Mistral. Régression qualitative
sur la sélection finale des articles « bonnes nouvelles » du jour.

## Diagnostic

Deux PRs de coût ont été mergées récemment sur `main` :

- **#905 — LR-1 PR 1** (mesure tokens + rate-limiter large-only) : purement
  additif/observabilité côté `good_news_classifier.py` et
  `classification_service.py`. Le rate-limiter ajouté ne borne que
  `EditorialLLMClient` (curation/deep_matcher/perspective), **pas**
  `GoodNewsClassifier` qui a son propre client HTTP. Aucun changement de contenu
  de prompt ni de taille de batch. **Non suspect.**
- **#914 — LR-1 PR 2** (batching classif + prompt cache + trims éditoriaux) :
  contient le vrai suspect (levier 1, batching).

### Root cause — levier 1 de #914 (batching de classification)

`packages/api/app/config.py` a remplacé le batch fixe de la passe 1 de
classification (`mistral-small`, qui produit entre autres le flag `serene`,
seul gate d'entrée vers la passe 2 `is_good_news` sur `mistral-large`) par un
batch accumulé :

```
classification_worker_batch_size:     5  → 12
classification_worker_min_batch_size: 1  → 8   (gate d'accumulation)
classification_worker_max_wait_s:     0  → 300
classification_worker_interval_s:    10  → 30
```

Or `batch_size=5` **n'était pas arbitraire** : fixé délibérément par la PR #152
(mars 2026), passée de 20 → 5 explicitement *« pour maximiser la qualité de
classification »*. PR #914 a défait cette leçon documentée sans la ré-évaluer,
pour amortir le prompt système (taxonomie 51 topics) et réduire le coût. Le
maintenance doc de #914 revendiquait *« zéro changement de comportement
produit »* — faux : un batch plus gros (2,4×) dilue l'attention du modèle par
article (plus d'articles à juger simultanément dans un seul prompt), dégradant
la précision de `serene` → mauvais candidats transmis à la passe 2
`is_good_news` → sélection finale non pertinente. Le délai d'accumulation
(jusqu'à 5 min, gate min 8) ajoute de la latence de fraîcheur, secondaire mais
dans le même sens.

### Leviers de #914 **conservés** (hors scope, sans risque qualité identifié)

- **Prompt cache** (`prompt_cache_key`, passe 1 + entités + good-news) : ne
  change ni le contenu du prompt ni le comportement du modèle, juste la
  facturation.
- **Curation** : drop `article_titles` du prompt de sélection de clusters — ne
  touche ni la passe 1 ni la passe 2 des Bonnes Nouvelles.
- **Divergence** : gate LLM sur `divergence_llm_min_perspectives` — hors scope
  Bonnes Nouvelles.

## Fix

Revenir uniquement sur le levier de batching (celui qui a un historique
documenté de lien avec la qualité), en gardant les gains de coût sans risque
qualité (prompt cache, trims éditoriaux).

**`packages/api/app/config.py`** — restaurer les valeurs pré-#914 (chemin de
rollback env-only documenté par la PR elle-même) :

```python
classification_worker_batch_size: int = 5
classification_worker_min_batch_size: int = 1
classification_worker_max_wait_s: int = 0
classification_worker_interval_s: int = 10
```

Avec `min_batch_size=1` et `max_wait_s=0`, la gate d'accumulation
`_should_process()` (ajoutée par #914 dans `classification_worker.py`) redevient
un no-op — traite dès qu'il y a ≥1 item pending, comme avant #914. Aucun code du
worker à toucher : uniquement les 4 constantes de settings + le commentaire.

## Vérification

1. `pytest -v tests/workers/test_classification_worker_gate.py tests/ml/test_classification_service.py tests/ml/test_good_news_classifier.py` — ces tests fixent `min_batch_size`/`max_wait_s` explicitement par cas (indépendants des defaults de `config.py`), donc le revert ne les casse pas.
2. `pytest -v` suite complète backend.
3. Alembic inchangé (aucune migration touchée).
4. Après déploiement staging : contrôle manuel PO des Bonnes Nouvelles du jour
   sur 2-3 jours pour confirmer le retour à la pertinence (pas de vérif auto
   sans jeu d'éval ground-truth).

## Fichiers touchés

- `packages/api/app/config.py` (4 constantes + commentaire)
- `docs/bugs/bug-bonnes-nouvelles-qualite-regression.md` (ce doc)

---

## Addendum — P3 HARDENING : exclusion dure du sport en serein (worker mort 30/06)

Contexte réévalué (preuves DB prod juillet 2026) : le batching #914 n'était que
le déclencheur superficiel. La **vraie** cause du sport (NBA/Basket USA) qui
remonte dans « Bonnes nouvelles » est double :

1. **Worker de classif mort le 30/06** → tout le frais a
   `is_good_news / is_serene / theme = NULL` (34,5k articles).
2. En prod, le fallback d'urgence retombe sur du contenu quelconque non-anxiogène
   et n'applique **aucune** exclusion sport (le `-80` du sélecteur n'est qu'une
   pénalité de score, pas un filtre).

P1 (ranimer le worker, ops Railway) et P2 (release hebdo #948/#957) restent des
actions PO. Ce P3 est le volet code — **defense-in-depth** : empêcher le sport
d'entrer dans « Bonnes nouvelles » **même si** le classifieur good-news produit un
faux positif (une altercation/transaction NBA n'est pas « sport-shaped » pour le
LLM et peut passer `is_good_news=True`).

### Changements

1. **`is_sport_content`** (`services/recommendation/filter_presets.py`) : fallback
   sur `content.source.theme` quand `content.theme` est NULL (article non
   classifié). Accès non-déclenchant (`__dict__.get("source")`, relation lue
   seulement si déjà eager-loaded) → pas de lazy-load async involontaire.
2. **Sélecteur serein** (`services/digest_selector.py::_score_candidates`) : en
   mode `serein`, un article sport est **écarté du pool** (`continue`) au lieu
   d'être seulement pénalisé (-80). En `pour_vous`, la pénalité reste inchangée.
3. **Fallback d'urgence serein** (`services/digest_service.py::_get_emergency_candidates`) :
   skip dur des articles sport quand `is_serene` (defense-in-depth sur le dernier
   recours, source eager-loaded).

### Tests

- `tests/test_low_priority_cap.py` — 3 cas fallback `source.theme` d'`is_sport_content`
  (NULL→source sport flag ; content.theme prime ; source tech ne flag pas).
- `tests/test_emergency_candidates_serein.py` — sport exclu du fallback serein
  par mot-clé (NBA, source mal-thémée `tech`) **et** par `source.theme="sport"`
  (titre neutre + theme article NULL).
- `tests/test_digest_selector.py` — l'ancien `test_sport_penalty_applies_in_serein_mode`
  devient `test_sport_hard_excluded_in_serein_mode` (le sport n'est plus scoré en serein).

### Note qualité modèle

`GOOD_NEWS_MODEL = "mistral-large-latest"` est **inchangé depuis #594** (déjà le
modèle le plus cher). Repasser à un modèle plus coûteux est inutile : le levier,
si le tri reste laxiste une fois le worker sain, est la strictness du prompt
pass-2 ou la porte `serene`, pas un swap de modèle.
