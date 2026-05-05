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

---

## Itération 2 — pourquoi #567 n'a pas suffi (2026-05-05 11:00 UTC)

Hotfix #567 (commit `58a82e23`, déployé ~09:48 UTC) a ajouté
`session.begin_nested()` + `asyncio.wait_for` autour de chaque candidat.
**Le bug a continué à fire** : 6 nouveaux events sur cette release en
5 min, dernier 10:53 UTC (même user `c959d7ef`).

### Cause racine réelle (HIGH confidence)

Breadcrumbs de l'event PYTHON-3P `97ac66340f6c4d92b8ec3cca928a0222` :

| t (UTC) | event |
|---|---|
| 10:52:56.380 | `SET LOCAL idle_in_transaction_session_timeout = 10000` |
| 10:52:56.403 | `SELECT user_sources WHERE user_id=…` (`_followed_source_ids`) — **ouvre une tx** |
| 10:52:56 → 10:53:09 | appel LLM Mistral 13 s, AUCUNE activité DB → **tx idle > 10 s** |
| ~10:53:06 | (côté PG) `IdleInTransactionSessionTimeout` → connexion tuée serveur-side (Sentry PYTHON-3R) |
| 10:53:09.469 | `SAVEPOINT sa_savepoint_1` envoyé sur connexion morte |
| 10:53:19 | `await db.commit()` (router) → `PendingRollbackError` (PYTHON-3P/3S) → 503 |

Le SAVEPOINT du #567 protégeait la **boucle d'ingestion**, mais la
session était déjà cramée AVANT d'y entrer. Cause directe : **une SELECT
sur `user_sources` ouvrait une tx avant l'appel LLM**, qui restait idle
13 s pendant le call Mistral, dépassant le `idle_in_transaction_session_timeout=10s`
(filet anti-zombie posé après l'incident 2026-04-28, `database.py:166`).

Règle déjà documentée : `docs/stories/core/18.1.veille-backend-foundations.md:53`
— *« Pas de session ouverte pendant un appel LLM »*. `SourceSuggester.suggest_sources`
la violait via `_followed_source_ids`.

### Fix réel

`source_suggester.py:131-167` — déplacer
`await self._followed_source_ids(...)` de dessus le bloc LLM à dessous,
juste avant le `if not candidates:`. Aucune autre modif.

`followed_ids` n'est consommé que dans `_fallback` (purement DB) et la
list-comp finale → ré-ordonnancement sûr.

### Test anti-régression

`tests/test_veille_source_ingestion.py::TestNoTxDuringLLM::test_followed_ids_query_runs_after_llm`
enregistre l'ordre des appels (`llm`, `followed_ids`) et assert qu'ils
sont dans cet ordre. Si une régression future remet une SELECT avant le
LLM, ce test bloque.

### Pourquoi pas relâcher `idle_in_transaction_session_timeout` ?

10 s = filet global anti-zombies posé après incident 2026-04-28
(`database.py:151-156`). L'augmenter recrée le risque. Hors scope.

---

## Itération 3 — pourquoi #568 n'a pas suffi (2026-05-05 14:38 UTC)

Hotfix #568 (commit `f85b1da8` / merge `a7550f47`, release prod
`ade40a80` déployée 14:25 UTC) a déplacé
`await self._followed_source_ids(...)` APRÈS le call LLM.
**Le bug a re-fire 12 minutes après le déploiement** :

- Sentry **PYTHON-3Z** `IdleInTransactionSessionTimeout` (1 user, 2 events,
  first 14:37:46 UTC, last 14:38:03 UTC)
- Sentry **PYTHON-40** `HTTPException 503` (1 user, 2 events, first 14:37:46 UTC)
  — couplé 1:1 avec PYTHON-3Z

Sentry a indexé le bug sous deux NOUVELLES issues (fingerprint différent
de PYTHON-3P/3Q/3R/3S de l'Itération 2) — confirmation que le chemin
d'erreur a muté avec la release.

### Cause racine réelle (verrouillée par breadcrumbs)

Event Sentry `c5c381ebf5a74fbfa285bfa37e0698c7` (release `ade40a80`,
user `c959d7ef`, transaction `app.routers.veille.suggest_sources`) :

| t (UTC) | event |
|---|---|
| 14:37:50.785 | `SET LOCAL statement_timeout = 30000` — **ouvre la tx implicite** |
| 14:37:50.829 | `SET LOCAL idle_in_transaction_session_timeout = 10000` |
| 14:37:50 → 14:38:03 | `httpx` POST `api.mistral.ai` (≈12.85 s, AUCUNE activité DB) |
| ~14:38:00.829 | (côté PG) idle > 10 s → connexion tuée serveur-side |
| 14:38:03.685 | `SELECT user_sources WHERE user_id=…` (`_followed_source_ids`) → `IdleInTransactionSessionTimeout` |
| → finally | `db.commit()` → `PendingRollbackError` → **503** |

**Ce que l'Itération 2 a manqué :** l'agent qui a écrit la section
précédente a accusé la SELECT `_followed_source_ids` d'ouvrir la tx.
**C'était les `SET LOCAL` eux-mêmes :**

- `safe_async_session()` (`database.py:204-234`) appelle
  `apply_session_timeouts(session, …)` *immédiatement* après l'ouverture
  du context, AVANT `yield`.
- `apply_session_timeouts` exécute deux `SET LOCAL` qui, en SQLAlchemy
  2.x async (lazy autobegin), **ouvrent la tx implicite**.
- À partir de ce moment, toute pause `await` non-DB (LLM, HTTP) est de
  l'idle-in-transaction. Déplacer la SELECT après le LLM ne change rien :
  la tx était déjà ouverte par les SET LOCAL.

### Fix réel

`source_suggester.py:133-179` — encadrer le call LLM par :

1. **AVANT** le bloc LLM : `await session.rollback()` ferme la tx
   implicite ouverte par les SET LOCAL. Aucun travail user n'a été
   committé entre-temps, le rollback est sans effet métier.
2. **APRÈS** le bloc LLM (et avant la première query DB suivante) :
   `await apply_session_timeouts(session)` ré-émet les SET LOCAL sur la
   nouvelle tx que la prochaine query ouvrira → filet anti-zombie
   restauré pour la boucle d'ingestion + commit final.

Le helper `_push_session_timeouts` est promu en `apply_session_timeouts`
(public) pour être importable depuis le service.

### Test anti-régression

`tests/test_veille_source_ingestion.py::TestNoTxDuringLLM::test_rollback_before_llm_then_timeouts_reapplied`
verrouille l'ordre :
`session.rollback() → llm → apply_session_timeouts → followed_ids`.
Toute régression future qui retire le rollback avant LLM ou le re-push
après bloque ce test.

### Pourquoi pas la refacto architecturale (event listener `after_begin`) ?

Plus propre : émettre SET LOCAL automatiquement à chaque nouvelle tx
via un `event.listens_for(SyncSession, "after_begin")` éliminerait le
foot-gun pour TOUS les endpoints qui font du long I/O sous `Depends(get_db)`.
Hors scope du hotfix : changement architectural plus large, à sortir en
story dédiée. Lister les autres endpoints à risque (rg `Depends\(get_db\)`
+ grep `httpx`/`mistral`/`anthropic` dans le même handler) avant.
