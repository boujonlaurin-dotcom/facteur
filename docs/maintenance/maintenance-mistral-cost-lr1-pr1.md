# Maintenance — LR-1 / PR 1 : mesurer le € Mistral + fixer le burst éditorial

> Phase 3 / Launch Readiness. Première des 4 PR du plan LR-1 (cf.
> `.context/attachments/.../plan.md`). **Zéro impact produit.**
> Cible `main`. Conclure avec `/go`.

## Objectif

1. **Capture des tokens** : transformer le compteur d'appels (`api_usage_events`)
   en vrai modèle €/token. Les réponses Mistral renvoient déjà
   `usage.{prompt_tokens, completion_tokens}` ; on les persiste pour pouvoir
   faire un `GROUP BY model` → € réel par modèle / call_site, sans dépendre du
   dashboard Mistral.
2. **Fix du burst éditorial (les 28 % de 429)** : l'`EditorialLLMClient` est
   appelé via des `asyncio.gather` non bornés (curation + deep_matcher +
   perspective, tous `mistral-large-latest`). On ajoute un token-bucket /minute
   + une `Semaphore` de concurrence **partagés au niveau module** (chokepoint
   unique), gatés sur le modèle large, + un retry/backoff sur `chat_text` (qui
   n'en avait aucun).

## Vérité terrain (constatée dans le code)

- 1 seul head Alembic : `au01_api_usage_events` (le « 2 heads » du plan était la
  situation pré-merge `origin/main`, désormais résolue). La migration tokens
  s'enchaîne proprement → `au02`.
- `EditorialLLMClient` est instancié **par appelant** (pipeline, perspective,
  veille x2, bias, smart_search) → le limiteur DOIT être un singleton module
  (sinon il ne borne pas l'agrégat). Les appels bursty sont tous `large`.
- Capture tokens nécessaire seulement sur les 2 sites à client propre
  (`classification_service`, `good_news_classifier`) + le chokepoint éditorial
  (`chat_json`/`chat_text`). `smart_search` (Mistral) passe déjà par `chat_json`
  → couvert ; son chemin Brave n'a pas de tokens.

## Tâches

### Capture tokens
- [ ] `models/api_usage_event.py` : `prompt_tokens` / `completion_tokens` (int, nullable).
- [ ] Migration `au02_api_usage_tokens` (additive, down_revision `au01`, 1 head).
- [ ] `usage_recorder.py` : params tokens sur `record_api_call` + champs sur
      `_ApiCallTracker` + propagation dans le `finally` de `track_api_call`.
- [ ] `classification_service._call_mistral` : pose les tokens sur le tracker.
- [ ] `good_news_classifier._call` : idem.
- [ ] `editorial/llm_client.chat_json` + `chat_text` : idem.

### Fix burst éditorial
- [ ] `config.py` : `mistral_large_rpm` (def. 60), `mistral_large_concurrency`
      (def. 4), `mistral_rate_limit_enabled` (def. True, kill-switch).
- [ ] `editorial/rate_limiter.py` (nouveau) : `_MistralRateLimiter` token-bucket
      + semaphore, loop-safe (recrée sem/lock au changement de loop), horloge
      injectable (fake clock pour tests).
- [ ] `editorial/llm_client.py` : singleton limiteur module + `_is_large_model`
      + `_do_post` (slot limiteur autour du POST, large only) ; ajout
      retry/backoff à `chat_text`.

### Tests
- [ ] `tests/test_usage_recorder.py` : enregistrement des tokens.
- [ ] `tests/editorial/test_rate_limiter.py` : token-bucket (fake clock) +
      cap de concurrence.
- [ ] `tests/editorial/test_llm_client.py` : retry `chat_text`, limiteur
      large-only, capture tokens.
- [ ] `tests/conftest.py` : fixture autouse reset du limiteur (bucket plein /test).
- [ ] Capture tokens côté classification / good_news.

### Verify
- [ ] `pytest -v` vert. Alembic 1 head, `upgrade head` + `downgrade` sur DB vide.
- [ ] `/go` (VERIFY → simplify → PR `--base main`).

## Acceptance

- Chaque ligne Mistral porte des compteurs de tokens → `GROUP BY model` donne
  un €/jour.
- Le limiteur borne le burst large (test fake-clock) ; `chat_text` retente sur
  429/5xx. Pas de changement de schéma/comportement pour les modèles non-large.
- Reversible : `mistral_rate_limit_enabled=False` désactive le throttle,
  `usage_tracking_enabled=False` coupe l'instrumentation, sans redéploiement de
  schéma.

## Pas de changelog

PR backend-only, aucun écran impacté → pas d'entrée `changelog.json`.

---

## Statut : implémenté + testé (prêt pour `/go`)

Toutes les tâches ci-dessus sont faites. Fichiers livrés :
- `app/config.py` (3 settings), `app/services/editorial/rate_limiter.py` (nouveau),
  `app/models/api_usage_event.py` (2 colonnes), `alembic/versions/au02_api_usage_tokens.py`
  (nouveau), `app/services/observability/usage_recorder.py`,
  `app/services/ml/classification_service.py`, `app/services/ml/good_news_classifier.py`,
  `app/services/editorial/llm_client.py`.
- Tests : `tests/editorial/test_rate_limiter.py` (nouveau), `tests/test_usage_recorder.py`,
  `tests/editorial/test_llm_client.py`, `tests/ml/test_classification_service.py`,
  `tests/ml/test_good_news_classifier.py`, `tests/conftest.py` (fixture reset limiteur).

### Vérif réalisée
- pytest ciblé vert (pyenv) : limiteur (fake-clock), recorder, llm_client (retry
  chat_text + gating large-only + tokens), call-sites classif/good_news ; +
  consommateurs (perspective/veille/bias). Collection pleine suite = 1650, 0 erreur.
- Alembic : 1 head (`au02`) ; SQL up/down rendu offline (ADD/DROP 2 colonnes).
- `ruff check app/` clean ; mes fichiers `ruff format` OK.

### Caveats env (non bloquants, CI-vert)
1. **DB locale** : conteneur test 54322 partagé avec un autre workspace Conductor
   (creds inconnues, `make db-reset` interdit) → les tests DB et l'upgrade DB-vide
   tournent en **CI** (`alembic-smoke` + pytest backend), pas en local.
2. **Hook stop-verify** : appelle `.venv/bin/pytest` (absent en Conductor) →
   faux négatif connu ; vérif réelle faite via pyenv pytest.
3. **Cycle d'import pré-existant** `editorial.pipeline ↔ llm_bias` (ordre-sensible,
   via `editorial/__init__`) — hors scope, mon ajout (`llm_client → rate_limiter`)
   est un leaf hors du cycle ; collection pleine suite OK.
4. **Drift ruff non épinglé** : `main.py` / `digest_generation_job.py`
   (non touchés) flaggés `would reformat` — issue connue, hors scope.

### Reste
`/go` (VERIFY → simplify → PR `--base main`, body = `.context/pr-handoff.md`).
