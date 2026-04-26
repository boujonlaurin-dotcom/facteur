# Bug: RSS sync — connexion DB idle tuée par PgBouncer → "Essentiel du jour" ne charge plus

> Suite/complément au refactor P1/P2 décrit dans
> [`bug-infinite-load-requests.md`](./bug-infinite-load-requests.md).

## Description
Le 26 avril 2026 au matin, l'écran "Essentiel du jour" ne charge plus. Logs Railway :

```
Job "RSS Feed Synchronization (trigger: interval[0:30:00])" raised an exception
File "/app/app/workers/rss_sync.py", line 19, in sync_all_sources
    async with async_session_maker() as session:
psycopg.OperationalError: consuming input failed: server closed the connection unexpectedly
```

L'exception se produit à chaque cycle (toutes les 30 min) **dans le `__aexit__`** : le ROLLBACK de cleanup s'exécute sur une connexion déjà tuée par le serveur.

## Cause racine
Le refactor P2 (`_short_session()` + `process_source` hors session) a bien retiré la session longue **côté inner**, mais il restait deux points où `self.session` était encore tenue ouverte longtemps :

1. **`packages/api/app/workers/rss_sync.py:19`** : un outer `async with async_session_maker() as session:` enveloppe l'appel complet à `sync_all_sources()`. Cette session reste checked-out pendant tout le `gather()`.
2. **`packages/api/app/services/sync_service.py:75`** (`SyncService.sync_all_sources`) : le SELECT initial des sources actives utilise toujours `self.session`, qui pointe sur la session outer.

Pendant le `gather()` (5 sources concurrentes × 50 entries × HTTP fetch + paywall detection + LLM), la connexion outer reste **idle, checked-out**. Supabase PgBouncer tue toute connexion idle > ~5 min. `pool_pre_ping=True` et `pool_recycle=180` ne protègent qu'**au checkout**, pas pendant la détention idle.

## Impact "Essentiel du jour"
Le job RSS sync échoue à chaque cycle → plus aucun nouvel article ingéré. Le `DigestSelector` filtre sur `hours_lookback=48`. Sans contenu récent, la fenêtre se vide → `/api/digest` renvoie 503/empty.

## Fix appliqué
- `packages/api/app/services/sync_service.py`
  - `SyncService.__init__` : `session: AsyncSession | None = None`
  - `sync_all_sources` : le SELECT initial passe par `self._short_session()` (helper déjà existant), libérant la connexion avant `gather()`
- `packages/api/app/workers/rss_sync.py`
  - `sync_all_sources()` : retire l'outer `async with`. Instancie `SyncService(session=None, session_maker=async_session_maker)`.
  - `sync_source(source_id)` (single-source, court-lived) : inchangé.

Aucune migration Alembic. Aucun SQL Supabase.

## Tests
- `pytest packages/api/tests/test_sync_service.py -v` (4/4 ✓)
- `pytest packages/api/tests/workers/test_scheduler.py -v` (test `test_digest_job_timezone_europe_paris` échoue déjà sur main — `pytz` identity, pré-existant)
