# PR — bump DB pool 20→50 + restore stdout observability

## Why
Prod (Railway, Supabase Pooler partagé 60 conn) sature dès ~6 requêtes feed concurrentes :
- `pool_size=10 + max_overflow=10 = 20` → toute requête au-delà attend `pool_timeout=30s` puis timeout.
- Sentry IDs : QueuePool TimeoutError (cf. `queue.QueuePool` dans Sentry, `db_pool_pressure_high`).

En parallèle, les listeners d'observabilité existants (`long_session_checkout` `database.py`, `db_pool_pressure_high` `main.py`) émettent bien des `structlog.warning(...)` mais **n'apparaissent jamais dans Railway logs des 7 derniers jours** (audit). Avant de poser un kill-switch GH Action ou tout monitoring externe, il faut s'assurer que le pipeline stdout fonctionne.

## What

### `packages/api/app/database.py`
- Capacité prod consolidée dans `PROD_POOL_KWARGS` (importable depuis tests).
- `pool_size=25`, `max_overflow=25` → 50 conns max → ~16 requêtes feed concurrentes.
- `pool_timeout=30 → 10s` : un slot bloqué cède vite au lieu de masquer la saturation.
- Marge : 60 (Supabase) - 50 (app) = 10 conns pour le scheduler in-process.
- `pool_recycle=180`, `pool_pre_ping=True` inchangés.

### `packages/api/app/main.py`
- Boot probe `logger.warning("startup_logger_check", level="warning_emitted")` juste après `structlog.configure`. Si absent du 1er log post-deploy → pipeline stdout cassé, on sait avant de chercher pourquoi `db_pool_pressure_high` ne sort pas. Confirme aussi que `LoggingIntegration` Sentry (filtre `logging.ERROR`) ne capture pas les warnings structlog.
- `/api/health/pool` : `logger.info("pool_metrics_probed", **metrics)` avant return — base pour mesurer la fréquence de ping du futur kill-switch GH Action.

### `packages/api/tests/test_health_pool.py`
- `test_prod_pool_kwargs_capacity` lock 25/25/10/180 — toute modif future déclenche revue.

## Risques & mitigations
- **Saturation Supabase Pooler** : 50 conns app + éventuels workers pourraient frôler 60. Marge 10 explicite ; si plusieurs réplicas Railway → revoir avant scale horizontal.
- **pool_timeout=10s** : plus agressif. Si symptôme "tout charge à l'infini" disparaît au profit de 5xx visibles → succès attendu (visibilité).

## Critères d'acceptation
- [x] `pytest -v tests/test_health_pool.py` vert (2/2)
- [ ] Au boot prod : `db_pool_config pool_type=AsyncAdaptedQueuePool` + `startup_logger_check` visibles dans `railway logs`
- [ ] `curl /api/health/pool` retourne `size=25`
- [ ] 50 requêtes parallèles → 0 timeout pool

## Pas inclus
- Pas de migration Alembic.
- Pas de changement mobile.
- Kill-switch GH Action séparé (hand-off #3).
