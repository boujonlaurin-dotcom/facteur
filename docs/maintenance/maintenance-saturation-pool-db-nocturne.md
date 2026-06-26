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

## Hors périmètre
PG advisory lock entre jobs de nuit (option robuste si le décalage horaire ne
suffit pas), right-size du pool, dashboards Sentry/PostHog.

## Tests
- `tests/test_pool_observability.py` : warn seulement si soutenu (2 sondes), reset
  du streak sous le seuil, page immédiat level=fatal >= 90 %.
- `tests/workers/test_zombie_session_sweeper.py` : capture Sentry level=error sur
  kill, aucune capture sur run clean.
- `test_digest_generation_job.py`, `test_digest_content_refs.py`,
  `test_storage_cleanup.py`, `workers/test_scheduler.py` : Axes A/B/C.
- Pas de migration Alembic (aucun DDL ; l'index `ix_user_content_status_content_id`
  existe déjà).

## Acceptation post-deploy (lecture seule prod)
Sur la fenêtre 07h00-08h30 : alerte *warn* dès pression soutenue ≥70 %, *page* si
≥90 % ; `zombie_session_sweeper_killed` remonté en Sentry s'il survient ; absence
de nouveaux 5G/4X.
