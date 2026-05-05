# PR — fix(veille): /suggestions/sources Iter 4 — parallélisation boucle + transition mobile 25 s

## Summary

Itération 4 du fix `/suggestions/sources` (suite de #561, #562, #567, #568, #572). Le pattern idle-in-tx de #572 est verrouillé (PYTHON-3Z/40 dernière occurrence à 14:38 UTC, instant du déploiement) mais l'utilisateur (`c959d7ef`) signalait toujours :
1. Step 3 reste en spinner > 1 min puis bascule sur le mock — au refresh manuel, les sources sont là.
2. La page de transition Step 2 → Step 3 (`flow_loading_screen`) ne sert pas à faire patienter — l'utilisateur arrive direct sur Step 3 spinner.

Diagnostic Sentry post-#572 (event PYTHON-41, release `ecffd1bcff5dd0`) :
- LLM Mistral seul = **~16 s** (déjà supérieur au cap mobile `_loadingMaxDuration=8 s`)
- Boucle séquentielle 12 candidats × 0.85 s typique + jusqu'à 4 timeouts à 8 s = **30-60 s pire cas**
- Donc dépassement systématique de `_loadingMaxDuration` (8 s) et fréquent du `Dio.timeout` (30 s)

Deux fixes complémentaires shipped ensemble (l'un sans l'autre ne résout pas) :

### Fix A — Paralléliser la boucle d'ingestion (perf serveur)

`packages/api/app/services/veille/source_suggester.py:194-229` — boucle séquentielle `for cand in candidates:` refactorisée en deux phases :

1. **Phase 1 (parallèle, sémaphore 4)** — `RSSParser.detect()` HTTP-only, hors session DB. `asyncio.gather` avec sémaphore polite (`_DETECT_CONCURRENCY=4`, aligné avec stage 4 RSSParser). `asyncio.wait_for(_HYDRATE_TIMEOUT_S=8s)` par candidat préservé.
2. **Phase 2 (séquentielle)** — `_persist_detected()` fait le SELECT `feed_url` existant + INSERT si nouveau, dans un `session.begin_nested()` SAVEPOINT par candidat (préservé). SQLAlchemy AsyncSession n'étant pas safe pour des opérations concurrentes, l'ingest DB reste séquentiel — c'est le HTTP qui dominait, pas l'INSERT.

Wall-clock : **⌈12/4⌉ × 0.85 ≈ 3 s** (au lieu de 10 s typique). Pire cas avec 4 timeouts simultanés : 8 s (au lieu de 32 s).

Invariant #572 préservé : `await session.rollback()` avant LLM + `await apply_session_timeouts(session)` après LLM, intacts.

### Fix B — Aligner le budget transition mobile (UX)

`apps/mobile/lib/features/veille/providers/veille_config_provider.dart:230` — `_loadingMaxDuration` constante factorisée en `loadingMaxDurationFor(int from)` :
- `from == 1` (Step 1 → Step 2, pré-fetch topics rapide) → **8 s** (inchangé)
- `from == 2` (Step 2 → Step 3, LLM + boucle ingestion) → **25 s** (5 s de marge sous le `Dio.timeout=30 s`)

Avec Fix A actif, la requête typique tient ~16-19 s — la transition halo joue toute la durée du fetch et l'utilisateur arrive sur Step 3 avec les sources déjà chargées.

## Fichiers modifiés

### Backend
- `packages/api/app/services/veille/source_suggester.py` — refacto Phase 1/Phase 2, suppression `_hydrate_or_ingest`, ajout `_detect_candidate` + `_persist_detected`, constante `_DETECT_CONCURRENCY=4`. Imports : `RSSParser`, `DetectedFeed` (au lieu de `SourceService`).
- `packages/api/tests/test_veille_source_ingestion.py` — patch sites `SourceService.detect_source` → `RSSParser.detect`, helper `_detect_response` retourne `DetectedFeed`. Nouveau test `TestParallelDetect::test_detect_runs_concurrently_within_semaphore` (assert wall-clock < 3 s pour 12 candidats × 0.5 s parallèle, max in-flight = 4).
- `packages/api/tests/test_veille_source_suggester_eval.py` — adaptation patch site + factory `DetectedFeed`.

### Mobile
- `apps/mobile/lib/features/veille/providers/veille_config_provider.dart` — `_loadingMaxDuration` → `loadingMaxDurationFor(int from)` (8 s pour `from=1`, 25 s pour `from=2`).
- `apps/mobile/test/features/veille/providers/veille_config_provider_test.dart` — 3 nouveaux tests sur `loadingMaxDurationFor`.

### Doc
- `docs/bugs/bug-veille-suggestions-sources-pending-rollback.md` — ajout section « Itération 4 (2026-05-05) — décalage budget temps client / serveur » avec timeline Sentry, diagnostic UX, fix A+B, hors scope confirmé.

## Tests

- **Backend pure-mock** (sans Postgres local — Docker disque plein) :
  - `TestParallelDetect::test_detect_runs_concurrently_within_semaphore` : ✅ PASS (12 candidats × 0.5 s sleep, wall-clock 1.5 s, max in-flight = 4)
  - `TestNoTxDuringLLM::test_rollback_before_llm_then_timeouts_reapplied` : ✅ PASS (invariant #572 verrouillé)
- **Backend integration** (TestAlreadyFollowedFlag, TestIngestion, TestDedupByDomain, TestThemeGuard, TestSavepointIsolation, TestCandidateTimeout, TestLLMTimeout, TestNoTxDuringLLM::test_followed_ids_query_runs_after_llm, TestParametrizedEval) : skip local par manque de Postgres ; à valider en CI.
- **Mobile** : `flutter test` lancé sur `veille_config_provider_test.dart` — 3 nouveaux tests sur `loadingMaxDurationFor` à valider.
- **Lint** : `ruff check` + `ruff format --check` ✅ all green.

## Risques

- **Concurrence DB** : 4 SAVEPOINT séquentiels en Phase 2 — préservé exactement comme avant. Aucun nested begin parallèle. Risque nul de race SQLAlchemy.
- **Httpx pool** : 4 requêtes parallèles via `httpx.AsyncClient` partagé (`max_connections=100` par défaut). Sites cibles non pollués (sémaphore polite, aligné sur stage 4 interne).
- **curl-cffi sync vs async** : `curl_cffi.requests.AsyncSession` est async (`rss_parser.py:139`), donc `asyncio.wait_for(8s)` cancel correctement le coro — pas de hang non-cancellable.
- **Timeout Dio 30 s** : avec Fix A le wall-clock typique tombe à ~19 s, donc largement sous timeout. Pire cas (LLM lent + 4 timeouts) : ~24 s. Si Mistral renvoie 30 s+, on tombe en error Dio comme avant — la transition se ferme via la branche error, comportement inchangé.

## Verification post-merge

1. Surveiller Sentry release post-merge :
   - Aucun nouvel event `IdleInTransactionSessionTimeout` (PYTHON-3Z/3R) ou `PendingRollbackError` (PYTHON-3P/3S) → invariant #572 toujours verrouillé.
   - Volume PYTHON-41 / PYTHON-3T / PYTHON-3X (échecs RSSParser sur candidats LLM exotiques) inchangé — c'est attendu, ce sont les sites qui bloquent les bots, pas un bug.
2. Tester via TestFlight le flow Step 2 → Step 3 :
   - Tap valider Step 2 → animation halo joue 16-25 s (au lieu de 8 s)
   - Arrivée sur Step 3 : sources affichées immédiatement (pas de spinner secondaire)

## Hors scope explicite

- Cache négatif par hostname — gain marginal post-parallélisation.
- Skip RSSParser pour candidats LLM — change la qualité du `feed_url`, story dédiée si besoin.
- Streaming SSE — refactor architectural lourd, pas justifié.
- Refactor `safe_async_session` event-listener `after_begin` — déjà hors scope #572.
