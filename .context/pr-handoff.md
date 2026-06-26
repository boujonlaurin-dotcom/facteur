## fix(scaling): saturation pool DB nocturne (PYTHON-5M/5G/4X) + alerte 2 seuils

Corrige la racine de la pression pool matinale (~07h20-07h35 Paris) et ses
retombées, **sans augmenter le pool** (`max_connections=60` partagé entre staging
et prod). Doc : `docs/maintenance/maintenance-saturation-pool-db-nocturne.md`.

### Axe A — discipline rollback dans le digest (PYTHON-5G)
- `rollback()` + `apply_session_timeouts()` dans les `except` *trending* et
  *editorial precompute* de `run_digest_generation`.
- Grille isolée dans sa propre `safe_async_session()` courte (calque `cov_session`),
  idempotence `ON CONFLICT DO NOTHING` préservée → plus de `PendingRollbackError`,
  le mot du jour se fige.

### Axe B — borner la concurrence (PYTHON-5M)
- `concurrency_limit` digest 10 → 5 (signature + scheduler).
- `subtopic_weight_decay` 07h20 → 06h50 (hors pic). Pool inchangé.

### Axe C — alléger le cleanup off-peak 03h (PYTHON-4X)
- `statement_timeout_ms=120_000` ; extraction des `content_id` côté Postgres (JSONB,
  3 layouts) au lieu de tirer 172 MB d'`items` ; counts best-effort ; DELETE batché.
  Sémantique de préservation (90 j) inchangée.

### Axe D — métrique / alerte de suivi (cette étape)
- **Sonde pool à 2 seuils** (`_pool_health_probe`) : *warn* ≥70 % **soutenu** sur 2
  sondes consécutives → Sentry `level=warning` (ignore les pics transitoires) ;
  *page* ≥90 % → Sentry `level=fatal` immédiat. Seuils configurables
  (`pool_warn_threshold_pct` / `pool_page_threshold_pct` /
  `pool_warn_sustained_probes`).
- **Alerte sur `zombie_session_sweeper_killed`** : Sentry `level=error` (tout kill =
  un `safe_async_session` manqué) en plus du warning structlog.

### Tests & migration
- `pytest` vert sur `test_pool_observability.py`, `workers/test_zombie_session_sweeper.py`,
  + les tests Axes A/B/C.
- **Aucune migration Alembic** (aucun DDL ; l'index `ix_user_content_status_content_id`
  existe déjà). Lecture seule prod tenue, aucun déploiement déclenché.
