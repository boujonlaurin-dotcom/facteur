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
