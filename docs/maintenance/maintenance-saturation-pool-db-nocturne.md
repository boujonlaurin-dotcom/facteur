# Maintenance — Saturation pool DB nocturne (PYTHON-5M / 5G / 4X)

## Contexte
Trois issues Sentry corrélées sur la fenêtre matinale ~07h20-07h35 Paris (même
trace) : **PYTHON-5M** « DB pool pressure high: 100 % » (saturation pool app),
**PYTHON-5G** `PendingRollbackError` à `ensure_daily_puzzle` (grille), **PYTHON-4X**
`QueryCanceled` (statement timeout 30 s) au cleanup. Pas d'effet UI direct, mais
racine d'incidents en cascade (jobs de nuit qui rollback, mot du jour non figé,
contribution aux timeouts feed).

## Cause racine
- Fenêtre matinale : digest (`concurrency_limit=10`) + `subtopic_weight_decay`
  (07h20, chevauche) + pic feed du rituel ⇒ le pool de 20 conns/backend sature à
  100 %. `max_connections=60` est **partagé** entre staging (`main`) et prod
  (`production`) ⇒ **augmenter le pool est exclu** (2 × 20 = 40, déjà proche du
  plafond).
- `run_digest_generation` partage **une seule session** entre pré-étapes ; les
  `except` *trending* / *editorial precompute* avalent l'exception **sans
  `rollback()`** → session `PENDING_ROLLBACK` → la grille réutilise la session
  empoisonnée → `PendingRollbackError` (5G).
- Le cleanup tire 172 MB de JSONB `daily_digest.items` en Python + 2 counts
  d'observabilité qui re-scannent `contents` (~10 s chacun) → dépasse 30 s sous
  pression (4X).

## Changements
### Axe A — discipline rollback dans le digest (5G)
- `digest_generation_job.py` : `rollback()` + `apply_session_timeouts()` dans les
  `except` *trending* et *editorial precompute* (re-pousse les `SET LOCAL` après
  rollback). Grille isolée dans sa propre `safe_async_session()` courte (calque du
  pattern `cov_session`), idempotence `ON CONFLICT DO NOTHING` préservée.

### Axe B — borner la concurrence, PAS augmenter le pool (5M)
- `concurrency_limit` digest 10 → **5** (signature + appel scheduler).
- `subtopic_weight_decay` décalé 07h20 → **06h50** (reste avant le digest, hors
  pic). Pool `pool_size`/`max_overflow` **inchangés**.

### Axe C — alléger le cleanup off-peak 03h (4X)
- Session cleanup avec `statement_timeout_ms=120_000`.
- Extraction des `content_id` référencés côté Postgres (opérateurs JSONB, 3
  layouts) au lieu de tirer les blobs `items` ; counts d'observabilité best-effort ;
  DELETE batché. Sémantique de préservation (90 j) **inchangée**.

### Axe D — métrique / alerte de suivi (cette étape)
- **Sonde pool à 2 seuils** (`_pool_health_probe`, 5 min) :
  - *warn* `usage_pct >= pool_warn_threshold_pct` (70 %) **soutenu** sur
    `pool_warn_sustained_probes` (2) sondes consécutives → log
    `db_pool_pressure_high` + `sentry_sdk.capture_message(level="warning")`. Le
    streak module-level ignore les pics transitoires (1 sonde) du rituel matinal.
  - *page* `usage_pct >= pool_page_threshold_pct` (90 %) → log
    `db_pool_pressure_critical` + `capture_message(level="fatal")` **immédiat**,
    sans fenêtre soutenu (saturation imminente).
- **Alerte sur `zombie_session_sweeper_killed`** : tout kill = un
  `safe_async_session` manqué quelque part → `capture_message(level="error")` en
  plus du warning structlog (la métrique `db_idle_in_transaction_swept{count}`
  always-on reste émise à chaque passage).

## S1 — Sérialisation jobs + garde anti-double-digest + couverture retry (suite, cette PR)

> Suite directe des axes A-D ci-dessus. Même racine (fenêtre pool partagée
> matinale), nouveaux gaps structurels : jobs sans `max_instances`, triple
> appelant non coordonné de `run_digest_generation`, session batch idle-in-tx
> sur le **chemin succès**, et couverture retry insuffisante sur 2 reads chauds.

### S1-A — sérialiser tous les jobs récurrents (`scheduler.py`)
`max_instances=1` (+ `coalesce=True`) sur **tous** les `add_job` : `rss_sync`,
`daily_digest`, `subtopic_weight_decay`, `digest_watchdog`, `storage_cleanup`,
`purge_deleted_users`, `recompute_source_language`, `cost_budget_projection`,
`zombie_session_sweeper`, `pool_health_probe` (`daily_essentiel_push_dispatch`
les avait déjà). Un run qui déborde sur le tick suivant ne lance jamais un 2e run
concurrent. **Défensif/documentaire** : APScheduler met déjà `max_instances=1`
par défaut → le vrai correctif anti-double-digest est S1-B.

### S1-B — garde anti-double-digest (réutilise `generation_state`, in-process)
`run_digest_generation` a **TROIS** appelants non coordonnés :
- cron `daily_digest` 07h30 (`scheduler.py`),
- watchdog 08h15 — **appel direct** (`scheduler.py`),
- **startup catchup** Railway boot 07h30-10h00 — **appel direct** (`main.py`),
  gardé seulement par son propre `_STARTUP_CATCHUP_LOCK`, indépendant de
  `generation_state`.

`max_instances=1` ne voit **que** le cron. Si le digest 07h30 tourne encore, un
2e digest complet démarre → 2 × `Semaphore(5)` = 10 slots pool d'un coup.

- **Garde IN-FUNCTION (load-bearing)** dans `run_digest_generation` : si
  `is_generation_running()` est déjà `True` **à l'entrée**, retourne
  `{"skipped": True, "reason": "already_running", "stats": job.stats}`.
  **Placée AVANT `mark_generation_started()`** (qui met `_is_running=True` et
  reset `_started_at` inconditionnellement). Ferme les 3 appelants d'un coup.
- **Garde call-site** dans `_digest_watchdog` : skip + log
  `digest_watchdog_skipped_generation_in_progress` si `is_generation_running()`
  avant l'appel (évite même d'ouvrir une session).
- **Safety-timeout (600s)** de `generation_state` : un run > 10 min repasse
  `is_generation_running()` à `False` (auto-reset) → échappatoire voulue (un run
  aussi long est pathologique). Ne **pas** augmenter `_SAFETY_TIMEOUT` ; le
  watchdog ne doit **jamais** override la garde.

### S1-C — libérer la tx batch avant le LLM (`digest_generation_job.py`)
Sur le **chemin succès**, la lecture *trending* laissait la tx de la session
batch ouverte (`idle in transaction`) pendant les 3-5 min de pré-calcul éditorial
LLM (les `rollback()` existants des axes A étaient dans les `except` seulement).
Ajout, **après** le bloc trending et **avant** le pré-calcul :
`await session.rollback()` + `await apply_session_timeouts(session)` (sous
`contextlib.suppress`). Sûr : le contexte trending vit dans un local Python
(`global_trending_context`, dataclass d'UUIDs), `state_mark_pending` est déjà
commité, le pré-calcul re-requête tout sur une tx fraîche. La pipeline
éditoriale elle-même reste saine (sessions courtes via `session_maker`).

### S1-D — étendre `retry_db_op` à 2 reads chauds (cold-open)
Helper `app/utils/db_retry.py` réutilisé sur 2 endpoints en lecture pure (zéro
commit, replay sûr) :
- `collections.list_collections` (`routers/collections.py`),
- `feed.get_tab_counts` (`routers/feed.py`) — phase de requêtes (multi-await)
  enveloppée dans une factory `_load_counts()` passée à `retry_db_op`.

**Exclus (justifiés)** : `feed.get_personalized_feed` (déjà cache + single-flight,
replay coûteux), `contents.get_perspectives` (cache + HTTP externe + background
tasks), `letters.get_user_letters` (**write path** : commit). Les retries
write-path sont **différés** (dépendent de S3 — idempotence upsert).

## Hors périmètre
PG advisory lock entre jobs de nuit (option robuste si le décalage horaire ne
suffit pas), right-size du pool, dashboards Sentry/PostHog.

### Externaliser le scheduler dans un worker Railway séparé (vrai fix long terme)
C'est la bascule structurelle qui résout la cause racine (API + APScheduler +
worker classification **dans le même process** = `Procfile` 1 `uvicorn`, cf.
`docs/scaling/scaling-investigation-200-users.md` §2 « plafonds infra »). Différé
**hors de cette PR** car non trivial :

- **Coordination cross-process requise.** `generation_state` (la garde S1-B) est
  **in-memory, per-process** : sorti dans un service séparé, le worker scheduler
  et le service web API ne partagent plus le flag → la garde anti-double-digest
  ne tient plus. Il faut un verrou partagé : **PG advisory lock**
  (`pg_try_advisory_lock`, déjà cité « Hors périmètre » plus haut) ou **Redis**.
- **Budget connexions (le chiffrage qui compte).** Le pooler Supabase plafonne à
  **60 connexions partagées** entre staging (`main`) et prod (`production`).
  Aujourd'hui chaque backend = 1 pool `pool_size=10 + max_overflow=10 = 20` ⇒
  2 × 20 = **40/60** au pic. Un worker scheduler séparé = **un nouveau pool** par
  environnement ⇒ 2 backends web (2 × 20) **+** 2 workers scheduler ⇒ il faut
  **right-sizer** : le worker n'a pas besoin de 20 conns (digest borné à
  `concurrency_limit=5` + marge jobs mono-connexion ⇒ ~`pool_size=6`), sinon on
  crève les 60. Prérequis = la sonde pool (axe D) pour mesurer la marge réelle
  avant de figer les tailles.
- **Coût Railway.** +1 service par environnement (worker scheduler), soit
  l'équivalent d'un petit conteneur uvicorn supplémentaire ×2 (staging + prod).
  Décision infra séparée (cf. `docs/maintenance/maintenance-scaling-db-robustness.md`,
  « découplage worker (S2) »).

## Tests
- `tests/test_pool_observability.py` : warn seulement si soutenu (2 sondes), reset
  du streak sous le seuil, page immédiat level=fatal >= 90 %.
- `tests/workers/test_zombie_session_sweeper.py` : capture Sentry level=error sur
  kill, aucune capture sur run clean.
- `test_digest_generation_job.py`, `test_digest_content_refs.py`,
  `test_storage_cleanup.py`, `workers/test_scheduler.py` : Axes A/B/C.
- Pas de migration Alembic (aucun DDL ; l'index `ix_user_content_status_content_id`
  existe déjà).

### Tests S1 (cette PR)
- `tests/workers/test_scheduler.py` : **chaque** job a `max_instances == 1`
  (+ `coalesce` là où ajouté) ; watchdog skip `run_digest_generation` si
  `is_generation_running()` est `True` (coverage < 90 %), l'appelle une fois si
  `False`.
- `tests/test_digest_generation_job.py` : `is_generation_running() → True` ⇒
  `run_digest_generation` retourne `{"skipped": True, ...}`, `mark_generation_started`
  **non** appelé, aucune `safe_async_session` ouverte ; `→ False` ⇒ procède.
  + safety-timeout `generation_state` (monkeypatch `time.monotonic`). S1-C : sur
  chemin succès, `session.rollback`/`apply_session_timeouts` appelés avant la
  boucle de pré-calcul.
- Endpoints reads (S1-D, modèle `tests/test_sources_resilience.py`) : mock
  `service.list_collections` `side_effect=[OperationalError, payload]` ⇒ 2 awaits
  + retour OK (idem `feed.get_tab_counts`). Le helper `retry_db_op` est déjà
  couvert unitairement par `TestRetryDbOp` — pas de duplication.
- Pas de migration Alembic (config/Python pur ; `generation_state` est in-memory ;
  1 head inchangé).

## Acceptation post-deploy (lecture seule prod)
Sur la fenêtre 07h00-08h30 : alerte *warn* dès pression soutenue ≥70 %, *page* si
≥90 % ; `zombie_session_sweeper_killed` remonté en Sentry s'il survient ; absence
de nouveaux 5G/4X.

### Acceptation S1 (lecture seule prod, post-deploy)
Sur la fenêtre 07h00-08h30 : **plus de pic pool x2** lié à un double digest
concurrent ; en cas d'overlap évité, logs `digest_generation_already_running_skipped`
(garde in-function) et/ou `digest_watchdog_skipped_generation_in_progress` (garde
watchdog) visibles ; pas de hausse des 500 sur `/api/collections/` ni
`/api/feed/tab-counts` lors des hoquets de pool (retry transparent). Pas de
load-test local de la fenêtre nocturne (couverte par unit tests).
