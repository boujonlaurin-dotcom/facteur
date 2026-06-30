# Maintenance — LR-1 / PR 2 : coupes de coût Mistral immédiates

> Phase 3 / Launch Readiness. Deuxième des 4 PR du plan LR-1 (cf.
> `.context/attachments/.../plan.md`). **Zéro changement de comportement
> produit.** Cible `main`. PR 3 (downgrades de modèle) reste séparée.
> Conclure avec `/go`.

## Objectif

Réduire le € Mistral **maintenant**, sans toucher au produit, par trois
leviers :

1. **Batching de classification** : la passe 1 (mistral-small) facture un gros
   prompt système (~la taxonomie 51 topics) à *chaque* appel batch. Plus le
   batch est gros et moins souvent appelé, moins le prompt système est refacturé.
   On passe d'un batch fixe de 5 toutes les 10 s à un batch accumulé
   (12 cible / 8 min) avec un plafond d'attente (max wait) pour ne pas affamer un
   petit reste de file. Priorité, retry, reset des items bloqués et sessions DB
   courtes inchangés.
2. **Prompt cache mesuré** : Mistral facture moins cher les tokens de prompt
   déjà vus (`usage.prompt_tokens_details.cached_tokens`). On ajoute le champ
   officiel `prompt_cache_key` (PAS `cache_control`, cf. docs Mistral) sur les
   prompts à gros préfixe stable (classification statique, extraction d'entités,
   good-news) et on **mesure** les tokens caché·es via une nouvelle colonne
   `api_usage_events.cached_prompt_tokens` (additif, nullable).
3. **Trims éditoriaux** :
   - Curation : on arrête d'envoyer `article_titles` (jusqu'à 10 titres /
     cluster) dans le résumé LLM — `topic_id`, `label`, `source_count`,
     `is_trending`, `theme` suffisent à la sélection. Économie directe de
     tokens prompt.
   - Divergence : on n'appelle le LLM de divergence que si ≥
     `divergence_llm_min_perspectives` (def. 4) perspectives ; en deçà, le
     fallback déterministe `compute_divergence_level` (déjà présent) suffit.

## Vérité terrain (constatée dans le code)

- 1 seul head Alembic : `ufb01_create_feedback_tables`. La migration
  `cached_prompt_tokens` s'enchaîne dessus → 1 head.
- `ClassificationWorker` (`app/workers/classification_worker.py`) est un
  singleton démarré depuis `main.py`. Il dequeue toujours `batch_size` items et
  les traite immédiatement. Pas de gate d'accumulation aujourd'hui.
- L'extraction d'entités est instrumentée sous le même call_site
  `classification_pass1` que la classification taxonomie (les deux passent par
  `_call_mistral`). On scinde : la classification garde `classification_pass1`,
  l'extraction d'entités prend `classification_entities`.
- `ClusterSummary.article_titles` n'est lu nulle part hors du `model_dump()`
  envoyé au LLM de curation → suppression du champ sûre.
- La divergence LLM est gatée par `len(merged_perspectives) >= 3` en dur dans
  `pipeline.py` ; le fallback déterministe existe déjà juste après.

## Tâches

### Batching classification
- [ ] `config.py` : `classification_worker_batch_size=12`,
      `classification_worker_min_batch_size=8`,
      `classification_worker_max_wait_s=300`,
      `classification_worker_interval_s=30`.
- [ ] `classification_worker.py` : worker piloté par les settings ; gate
      d'accumulation (traiter seulement si `pending >= min_batch` OU le plus
      vieux pending atteint `max_wait`). Priorité / retry / stale reset /
      sessions courtes préservés.
- [ ] `classification_queue_service.py` : helper `oldest_pending_age_seconds()`
      pour la condition max-wait.
- [ ] Split observabilité : `extract_entities_batch_async` → call_site
      `classification_entities`.

### Prompt cache + mesure
- [ ] `models/api_usage_event.py` : `cached_prompt_tokens` (int, nullable).
- [ ] Migration `pc02_api_usage_cached_tokens` (additive, down_revision
      `ufb01`, 1 head).
- [ ] `usage_recorder.py` : param `cached_prompt_tokens` sur `record_api_call`
      + champ sur `_ApiCallTracker` + propagation dans le `finally`.
- [ ] `classification_service` : `prompt_cache_key` (classification statique +
      entités) + capture `cached_tokens` sur le tracker.
- [ ] `good_news_classifier` : `prompt_cache_key` + capture `cached_tokens`.

### Trims éditoriaux
- [ ] `editorial/schemas.py` : retirer `article_titles` de `ClusterSummary`.
- [ ] `editorial/curation.py` : `_cluster_to_summary` sans `article_titles`.
- [ ] `config.py` : `divergence_llm_min_perspectives=4`.
- [ ] `editorial/pipeline.py` : gate divergence sur le setting.

### Tests
- [ ] Worker : seuils d'accumulation (min batch / max wait), pas de session
      pendant l'appel LLM inchangé.
- [ ] Recorder : persistance `cached_prompt_tokens` + propagation tracker.
- [ ] Classification / good-news : `prompt_cache_key` présent, capture cached,
      split de call-site, parsing inchangé.
- [ ] Éditorial : forme du payload curation (sans `article_titles`) + seuil
      divergence.

### Verify
- [ ] `pytest -v` vert. Alembic 1 head, `upgrade head` + `downgrade` sur DB vide.
- [ ] `/go` (VERIFY → simplify → PR `--base main`).

## Acceptance

- Le worker accumule jusqu'à la cible / au plafond d'attente sans jamais tenir
  de transaction DB pendant l'appel Mistral ; priorité/retry/stale intacts.
- Chaque ligne Mistral porte `cached_prompt_tokens` quand l'API le renvoie →
  `GROUP BY model` mesure le bénéfice du cache.
- Curation : plus aucun titre d'article dans le prompt LLM. Divergence : pas
  d'appel LLM sous le seuil, `divergence_level` toujours rempli (fallback).
- Reversible env-only pour le batching : `batch_size=5`, `min_batch=1`,
  `max_wait=0`, `interval=10` restaure le comportement d'avant. `prompt_cache_key`
  est ignoré côté Mistral si non supporté (pas de régression).

## Pas de changelog

PR backend-only, aucun écran impacté → pas d'entrée `changelog.json`.

---

## Statut : implémenté + testé

Fichiers livrés :
- `app/config.py` (4 settings batching + `divergence_llm_min_perspectives`).
- `app/models/api_usage_event.py` (`cached_prompt_tokens`),
  `alembic/versions/pc02_api_usage_cached_tokens.py` (nouveau, head unique).
- `app/services/observability/usage_recorder.py` (param + tracker + propagation).
- `app/services/ml/classification_service.py` (`prompt_cache_key` classif/entités,
  capture `cached_tokens`, split call_site `classification_entities`).
- `app/services/ml/good_news_classifier.py` (`prompt_cache_key` + capture cached).
- `app/workers/classification_worker.py` (gate `_should_process`, settings-driven),
  `app/services/classification_queue_service.py` (`get_pending_stats`).
- `app/services/editorial/schemas.py` + `curation.py` (drop `article_titles`),
  `app/services/editorial/pipeline.py` (gate divergence sur le setting).
- Tests : `tests/test_usage_recorder.py`, `tests/ml/test_classification_service.py`,
  `tests/ml/test_good_news_classifier.py`,
  `tests/workers/test_classification_worker_gate.py` (nouveau),
  `tests/editorial/test_schemas.py`, `tests/editorial/test_curation.py`,
  `tests/editorial/test_pipeline.py`.

### Vérif réalisée
- Tests ciblés verts (recorder, classif, good-news, worker gate, schemas,
  curation, pipeline divergence).
- Alembic : 1 head (`pc02`) ; SQL up/down rendu offline (ADD/DROP 1 colonne).
- `ruff check app/` clean.
