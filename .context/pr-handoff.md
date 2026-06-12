feat(observabilité): instrumentation API externes + sonde pool + résumé digest (scaling WP-E)

Enabler scaling **purement additif** (aucun impact user-facing, aucun changement de comportement métier). Phase 1 de l'investigation scaling 200 users — *mesurer avant de remédier*. Débloque WP-D (quotas/coûts Mistral), WP-B (digest), WP-A (pool). Doc : `docs/maintenance/maintenance-observabilite-scaling.md`.

## Volet 1 — Tracking persistant des appels API externes
- Nouvelle table append-only **`api_usage_events`** (`provider`, `model`, `call_site`, `user_id`, `status`, `latency_ms`, `created_at` + 2 index). Pas de contrainte d'unicité → zéro hot-row contention.
- Recorder best-effort **`record_api_call`** (`app/services/observability/usage_recorder.py`) : session courte dédiée (`safe_async_session`), jamais bloquant, ne lève jamais, gated par le kill-switch `usage_tracking_enabled`.
- 6 call sites instrumentés en `try/finally` (capte aussi `error`/`rate_limited`) : `classification_pass1`, `good_news_pass2`, `editorial` (chokepoint unique curation/pipeline/deep/perspective), `veille_suggester`, `smart_search_mistral`, `smart_search_brave`. Compteurs in-memory veille existants **laissés en place** (pas de rebranchement d'enforcement → WP-D).

## Volet 2 — Résumé de run digest always-on
- `compute_digest_coverage(session, target_date)` factorisé depuis le watchdog (source unique de la couverture, partagée scheduler ↔ job).
- Log always-on `digest_run_summary` (`duration_seconds`, `total_users`, `success`, `failed`, `coverage_pct`) + `coverage_pct` ajouté à l'event PostHog `digest_generated`. Couverture lue dans une session dédiée best-effort. Aucune nouvelle table.

## Volet 3 — Sonde pool périodique + métrique idle-in-tx
- `read_pool_stats(engine)` factorisé (`app/observability/pool_stats.py`), réutilisé par `/api/health/pool` (comportement inchangé) **et** par la nouvelle sonde.
- Job APScheduler `_pool_health_probe` (interval 5 min) : alerte `db_pool_pressure_high` + `sentry_sdk.capture_message(level="warning")` au seuil `pool_alert_threshold_pct` (défaut 80).
- `zombie_session_sweeper` émet désormais `db_idle_in_transaction_swept{count}` always-on (idle-in-tx requêtable même à 0).

## Config (kill-switches)
`usage_tracking_enabled: bool = True` · `pool_alert_threshold_pct: int = 80`.

## Migration
`au01_api_usage_events`, `down_revision = gr02_grille_featured_article` (head courant ; `vf02` du plan était dépassé depuis #784). **1 seul head** confirmé via `alembic heads`. Additive pure (CREATE TABLE + 2 index), rollback trivial. `upgrade head` + `downgrade -1` rejoués sur **DB vide** → OK.

## Tests & VERIFY
- Nouveaux : `tests/test_usage_recorder.py` (kill-switch, best-effort never-raises, coercition user_id, call_site inconnu), `tests/test_pool_observability.py` (`read_pool_stats` saturé/ok/NullPool + sonde alerte/quiet/registration).
- Non-régression : `tests/ml/`, `tests/editorial/`, `tests/workers/`, `tests/test_digest_generation_job.py`, `tests/test_health_pool.py`, `tests/services/search/` → **tout vert** (~355 tests sur les modules touchés).
- Intégration live (Postgres) : 1 ligne/appel écrite (Mistral + Brave), kill-switch ⇒ 0 insert, requête WP-D `GROUP BY provider, model, day` OK.

## Risques & rollback
Write amplification négligeable (append-only + best-effort + flag, ~3k/j). Rollback à chaud : `usage_tracking_enabled=False` (sans redéploiement schéma) ou `alembic downgrade -1`. Pas de changelog user (PR backend sans impact visible).
