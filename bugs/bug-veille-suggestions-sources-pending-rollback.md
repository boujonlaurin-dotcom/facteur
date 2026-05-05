# Bug — Veille `/suggestions/sources` : `PendingRollbackError` répété, loading infini perçu

## TL;DR

Sur prod (release `b6d2d3e4`, déployée 2026-05-05 ~02h15 Paris), POST `/api/veille/suggestions/sources` échoue systématiquement avec `PendingRollbackError` puis renvoie 503. Mobile reste 30 s en spinner (timeout Dio) puis affiche `_MockSourcesFallback` sans CTA retry → "loading infini" perçu, retry inutile.

**Cause racine** (HIGH confidence, 13 occurrences en 3h sur 2 users) :

1. `_hydrate_or_ingest` ne wrappe pas `await session.flush()` dans un savepoint. Une violation de contrainte (vraisemblablement `sources.feed_url` UNIQUE ou `sources.name` > 200 chars) empoisonne la session. Le `except Exception → continue` du loop ne fait pas de `rollback()`, donc tout `session.execute(...)` ultérieur lève `PendingRollbackError`. `db.commit()` final aussi.
2. Pas de timeout par candidat sur `source_service.detect_source(cand.url)`. RSSParser teste 14 variants suffix (rss, feed, feed.xml, …) avec httpx 7 s + curl-cffi 10 s en fallback. Sur un domaine qui hang (vu `binge.audio/feed/` 22× status=None sur 3 minutes), un seul mauvais URL gèle tout le pipeline.
3. Pas de timeout global sur `suggester.suggest_sources(...)`. La requête peut tourner > 3 min côté serveur, le mobile timeout à 30 s coupe la connexion mais le worker continue à brûler du CPU.
4. Bouton "Réessayer" perdu dans le merge V3 PR2 (#562) : `_MockSourcesFallback` actuel n'a aucun CTA, l'user ne sait pas comment se sortir du mock.

## Volumétrie (Sentry + Supabase, 2026-05-05 09:00 UTC)

| Métrique | Valeur |
|---|---|
| Sentry PYTHON-3P `PendingRollbackError` | 13 occurrences, 2 users, last 08:57 UTC |
| Sentry PYTHON-3Q `HTTPException 503` | 13 occurrences (suit 3P 1:1) |
| Sources `is_curated=False` ingérées via /suggestions/sources, dernières 12 h | **0** (toutes les `flush()` échouent) |
| Tentatives user `laurin.facteur@proton.me` en 2 min | 5 (08:55:40 → 08:57:10), toutes 503 |

## Reconstruction du flow (event PYTHON-3P latest)

User : `c959d7ef-d407-4a4a-a7cb-fdda6c065392` (`laurin.facteur@proton.me`)
Body : `theme_id=tech`, 7 topic_labels (IA, désinformation, biais algo, …), `purpose=preparer_projet`, `editorial_brief="J'écris une vidéo sur les dangers de l'IA…"`.

Breadcrumbs HTTP (100 captés, ~3 min de wall-clock) :
- 78× status 200 (RSS detection sur binge.audio/podcast/* et affordance.typepad.com et lemonde.fr)
- **22× status=None sur `https://www.binge.audio/feed/`** (timeout httpx 7 s, retry curl-cffi 10 s, boucle)
- 1× 403 sur `ladn.eu/newsletter/`

Request hang ~3 min côté serveur. Mobile timeout à 30 s → DioException → mock fallback sans CTA. User retry → même chemin de hang. PendingRollbackError final → 503 (ignoré côté mobile, déjà disconnecté).

## Hypothèses confirmées

| Hyp | Verdict | Evidence |
|---|---|---|
| `flush()` viole une contrainte → session poisonnée | **HIGH** | 0 source ingérée en 12h pour 13 tentatives. PYTHON-3P `_invalid_transaction` confirme transaction invalide. |
| RSSParser hang sur certains URLs | **HIGH** | 22× retry sur même URL `binge.audio/feed/` avec status=None (timeout) en 3 min. |
| Pas de timeout par candidat / global | **HIGH** | Code `_hydrate_or_ingest` ne wrappe pas dans `asyncio.wait_for`. Code router idem. |
| Bouton retry mobile manquant | **HIGH** | `_MockSourcesFallback` (ligne 213-247 step3_sources_screen.dart) sans `onRetry`. Ajouté en PR1 (#561), retiré dans PR2 (#562) qui a refait le widget. |

## Hypothèses réfutées

| Hyp | Verdict | Evidence |
|---|---|---|
| Quota Mistral 429 | KO | Aucun event Sentry `httpx.HTTPStatusError 429`. |
| EDBHANDLEREXITED Supabase | KO sur ce path | PYTHON-3N (EDBHANDLEREXITED) cassé sur `_run_first_delivery`, **pas** sur `suggest_sources`. |
| Theme invalide (`ck_source_theme_valid`) | KO | Body request : `theme_id=tech` (valide). Guard `_ALLOWED_SOURCE_THEMES` actif. |

## Fix recommandé

### Backend `packages/api/app/services/veille/source_suggester.py`

1. **Savepoint par candidat** dans la boucle d'ingestion :
   ```python
   for cand in candidates:
       try:
           async with session.begin_nested():  # SAVEPOINT
               hydrated = await asyncio.wait_for(
                   self._hydrate_or_ingest(session, source_service, cand, theme_id),
                   timeout=8.0,
               )
       except (asyncio.TimeoutError, Exception) as exc:
           sentry_sdk.capture_exception(exc)
           logger.warning(
               "source_suggester.hydrate_failed",
               name=cand.name, url=cand.url, error_class=type(exc).__name__, error=str(exc),
           )
           continue
       ...
   ```
   - Le savepoint isole les violations de contraintes : sur `IntegrityError`, seul le SAVEPOINT rollback, la session reste utilisable.
   - `asyncio.wait_for(..., 8.0)` cap chaque candidat → un mauvais URL ne gèle plus tout le pipeline.
   - `sentry_sdk.capture_exception` remonte la vraie cause des `flush()` qui foirent (jusque-là invisibles).

2. **Timeout global LLM** sur `chat_json` :
   ```python
   raw = await asyncio.wait_for(
       self._llm.chat_json(...),
       timeout=20.0,
   )
   ```
   Sur `TimeoutError` → bascule fallback curé.

### Backend `packages/api/app/routers/veille.py` `suggest_sources`

Aucun changement : le 503 sur SQLAlchemyError + httpx errors reste pertinent comme dernière barrière. Le savepoint en amont devrait éviter qu'on y arrive.

### Mobile `apps/mobile/lib/features/veille/screens/steps/step3_sources_screen.dart`

3. Réintroduire bouton "Réessayer" dans `_MockSourcesFallback` (perdu en PR2 #562). Trigger : `ref.read(veilleSourceSuggestionsProvider(params).notifier).refreshKeepingChecked(state.selectedSourceIds)`.

### Tests

- `tests/test_veille_source_suggester.py::test_hydrate_savepoint_isolation` : mock `flush()` qui throw `IntegrityError` au candidat #2 → assert candidats #1, #3, #4 OK + `db.commit()` final OK.
- `tests/test_veille_source_suggester.py::test_candidate_timeout` : mock `detect_source` qui sleep 30s → assert skip après 8s + log `candidate_timeout`.
- `apps/mobile/test/features/veille/screens/step3_sources_screen_test.dart::testRetryButtonPresent` : `AsyncValue.error` → assert bouton "Réessayer" présent + tap → appel `refreshKeepingChecked`.

## Hors scope (issues séparées)

- **Optim RSSParser** : éviter les 14 variants de suffix sur le même domaine (cause des 100 HTTP calls). Refactor `detect()` pour bail-out plus tôt après 2-3 essais sur le même hostname.
- **Cleanup script rows stuck `running > 15min`** : pré-existait à ce bug, pas lié à `/suggestions/sources`.

## Logs bruts représentatifs

### Sentry PYTHON-3P (latest 2026-05-05 08:57:10)

```
Exception: PendingRollbackError
Module: sqlalchemy.exc
Value: Can't reconnect until invalid transaction is rolled back. Please rollback() fully before proceeding
Transaction: app.routers.veille.suggest_sources
URL: POST /api/veille/suggestions/sources
Release: b6d2d3e43e6af9825663d449d9bd42396e53edd5
User: c959d7ef (laurin.facteur@proton.me)

Top frame (in_app):
  app/routers/veille.py: suggest_sources

Stack:
  sqlalchemy/ext/asyncio/session.py: commit
  sqlalchemy/orm/session.py: commit
  sqlalchemy/engine/base.py: _commit_impl
  sqlalchemy/engine/base.py: _revalidate_connection
  sqlalchemy/engine/base.py: _invalid_transaction
```

### Breadcrumbs HTTP (extrait, 22× même URL)

```
[8:54:41Z]  GET https://www.binge.audio/feed/  status=None  (timeout 7s)
[8:54:48Z]  GET https://www.binge.audio/feed/  status=None
[8:54:55Z]  GET https://www.binge.audio/feed/  status=None
... (20 more)
[8:57:06Z]  GET https://www.binge.audio/feed/  status=None
```
