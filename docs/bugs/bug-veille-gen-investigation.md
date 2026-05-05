# Bug — Investigation cause racine "Génération veille en loading infini"

**Date** : 2026-05-04
**Investigateur** : agent dev
**Status** : findings prêts pour GO PO Phase 2
**PR cible** : `boujonlaurin-dotcom/veille-v3-pr1-critical-fixes` (T1 + T2 + T3)

---

## TL;DR

- **Symptôme** : après onboarding veille, mobile reste en loading infini puis snackbar "On t'enverra une notif quand ta veille est prête" ; pas de notif jamais envoyée.
- **Cause racine immédiate (confiance HAUTE)** : `_run_first_delivery` (`packages/api/app/routers/veille.py:626-649`) catche l'exception, logge `veille.first_delivery_failed`, mais **n'écrit jamais `generation_state = FAILED`** sur la row `veille_deliveries`. La row reste stuck en `running` indéfiniment. Confirmé par row prod `90adb2e5-da1a-46f6-8fb1-38f6d54ad62c` stuck depuis 4h30 avec `last_error=NULL`, `attempts=1`, `finished_at=NULL`.
- **Cause des exceptions backend (confiance HAUTE)** : **EDBHANDLEREXITED** — Supabase ferme la connexion DB pendant `db.commit()`, laissant la session en transaction invalide (`PendingRollbackError` au commit suivant). Pattern infra connu (cf. `docs/bugs/bug-infinite-load-requests.md` #363). Frappe particulièrement `app.routers.veille.suggest_sources` (Step 3 onboarding qui INSERT des sources niche) et propage à `_run_first_delivery` qui suit immédiatement.
- **Bug jumeau dans le scanner** : `_process_config_with_semaphore` (`packages/api/app/jobs/veille_generation_job.py:106-112`) a le **même défaut structurel** — exception caught + log only, pas d'UPDATE FAILED. Toute future livraison qui échoue reste stuck en `running`.
- **Anomalie collatérale** : la config `3f6b0bf0...` (user `9406afbc...`) est `succeeded` en 0.4 s avec `item_count=0` car elle n'a **aucune source rattachée**. `digest_builder.build()` retourne `[]` via `skip_empty_config` et le scanner marque SUCCEEDED. Mobile affiche `_DeliveryEmptyView`. Hors scope T1 mais à creuser séparément (intégrité POST /config qui doit refuser un upsert sans sources, ou tracker en métriques).
- **Hypothèses non-vérifiables** : OOM / SIGTERM Railway worker — `RAILWAY_TOKEN` invalide pour cette session, pas de logs Railway accessibles. Faible probabilité au vu du volume bêta (2 deliveries en 14j).

## Volumétrie (table `veille_deliveries`, fenêtre 14 j)

| `generation_state` | Count | First | Last |
|---|---|---|---|
| `succeeded` | 1 | 2026-05-04 05:00 UTC | 2026-05-04 05:00 UTC |
| `running` (stuck > 4h) | 1 | 2026-05-04 10:39 UTC | 2026-05-04 10:39 UTC |
| `failed` | 0 | — | — |
| `pending` | 0 | — | — |

**Lecture** : 50 % d'échec sur 2 livraisons. Volume très faible (bêta soft launch), donc statistiques fragiles, mais le pattern d'échec est non-ambigu : la seule génération initiale du dataset est cassée. La row "succeeded" est elle-même un faux positif (livraison vide).

## Chronologie reconstituée — user `fd6b9d0b-4c16-422b-9688-bae34d63f41c` (2026-05-04)

| Temps UTC | Événement | Évidence |
|---|---|---|
| ~10:30 | User parcourt l'onboarding, arrive sur Step 3 → POST `/api/veille/suggestions/sources` → ingestion sources niche | Sentry PYTHON-3N (transaction `app.routers.veille.suggest_sources`, user `fd6b9d0b...`) |
| 10:30:48 | **EDBHANDLEREXITED** : la connexion DB est tuée pendant `db.commit()` (ligne 481 du router) | Sentry PYTHON-3N stack `psycopg/_connection_base._commit_gen → wait_async` |
| 10:30:48 (même seconde) | `PendingRollbackError` sur même transaction — conséquence : session invalide après EDB exit | Sentry PYTHON-3J (même url, même user) |
| ~10:30 | Réponse 500 → mobile retombe sur `_MockSourcesFallback` (T2 en cours d'investigation) | Code `step3_sources_screen.dart:84` |
| 10:39:13.040 | User finalise onboarding → POST `/api/veille/config` succeed | DB row `veille_configs.6f3529f7` `created_at` |
| 10:39:13.836 | POST `/api/veille/deliveries/generate-first` 202 → row `veille_deliveries` créée en `pending` puis passée à `running` par `_phase1_mark_running` | DB row `veille_deliveries.90adb2e5` `started_at` |
| ~10:39 | Background task `_run_first_delivery` démarre, fait `run_veille_generation_for_config` | Code `routers/veille.py:626` |
| ~10:39 - 10:40 | **Exception levée pendant le pipeline** (probable EDBHANDLEREXITED ou propagation) → catch silencieux, `logger.error("veille.first_delivery_failed", ...)` | Code `routers/veille.py:642-647` |
| 10:39 - 15:09 (now) | Row reste en `running`, `last_error=NULL`, `finished_at=NULL` — **stuck 4h30** | DB query Supabase |
| Mobile poll 90 s | `veille_config_screen.dart:_pollFirstDelivery` ne sort jamais sur succeeded/failed → snackbar timeout | Code `veille_config_screen.dart:175-208` |
| Mobile retour dashboard | User redirigé vers dashboard (`context.go(/veille/dashboard)`) | Code `veille_config_screen.dart:82` |
| `next_scheduled_at = 2026-05-11 05:00 UTC` | Le scanner ne re-tentera la génération que **dans 7 jours** (frequency=weekly, day_of_week=0) | DB query Supabase |

L'exception spécifique du `_run_first_delivery` n'est **pas** dans Sentry (probablement parce que le `except Exception as exc: logger.error(...)` ne re-raise pas, et la background task n'a pas le middleware Sentry du request lifecycle). C'est un trou d'observabilité à fermer dans le fix.

## Hypothèses : confirmées / réfutées

### ✅ Confirmées (HAUTE confiance)

1. **Bug structurel `_run_first_delivery`** : code lu directement (`routers/veille.py:642-647`), exception caught sans persistance FAILED. Reproduit par DB row stuck.
2. **Bug structurel `_process_config_with_semaphore`** : code lu (`jobs/veille_generation_job.py:106-112`), même pattern.
3. **EDBHANDLEREXITED Supabase** sur `/suggestions/sources` du même user, à T-9min de la livraison stuck. Récurrence prod : PYTHON-3N (04/05), PYTHON-3M (03/05), PYTHON-2S (28/04), 11+ occurrences `IdleInTransactionSessionTimeout` sur 7 jours.

### 🟡 Hypothèses cause des exceptions dans `_run_first_delivery` (MOYENNE confiance)

L'exception qui plante `_run_first_delivery` n'est pas tracée séparément (logger.error uniquement). Très probablement EDBHANDLEREXITED ou PendingRollbackError vu la corrélation temporelle avec PYTHON-3N. Mais peut être :
- Timeout LLM Mistral cumulé (digest_builder appelle `chat_json` pour `why_it_matters`).
- Race condition sur la session ouverte par `_phase1_mark_running` puis fermée, suivie d'une nouvelle session pour `_phase3_persist`.

### ❌ Réfutées

- **Quota Mistral 429** : aucune issue Sentry mentionne 429 / RateLimit / Mistral. Réfuté.
- **Crash parsing RSS feedparser** : aucune issue `FeedParserError` / `feedparser` dans Sentry. Réfuté.
- **Mauvais theme_id provoque ck_source_theme_valid violation** : le garde-fou ligne 229-235 de `source_suggester.py` couvre déjà le cas. Pas vu dans les stacks. Réfuté.

### ⚪ Non-vérifiables

- **OOM** : pas de Railway logs (`RAILWAY_TOKEN` invalide cette session — voir bas de doc).
- **SIGTERM Railway redeploy** pendant background task : idem.

Étant donné le volume bêta (1 ou 2 deliveries / jour), OOM est très peu probable. SIGTERM possible mais pas dominant : Sentry a 11+ occurrences EDBHANDLEREXITED qui suffisent à expliquer les échecs.

## Reproduction locale

**Possible**, plusieurs vecteurs :

1. **Forcer EDBHANDLEREXITED** : démarrer l'API locale, lancer POST /generate-first puis killer la connexion Postgres au milieu (`pg_terminate_backend(pid)` depuis psql). La row va rester stuck en `running` → reproduit le bug T1.
2. **Forcer une exception générique** : monkey-patch `VeilleDigestBuilder.build` pour `raise RuntimeError("test")` → vérifier que la row passe à FAILED (après fix) vs reste en running (avant fix).
3. **Test unitaire** plus simple : mock `run_veille_generation_for_config` pour raise → assert delivery row update.

## Fix recommandé (préalable au code Phase 2)

### Backend (T1)

1. **`packages/api/app/routers/veille.py:626-649`** — extraire `_run_first_delivery` en `_run_first_delivery_with_retry(config_id, target_date, delivery_id)` :
   - try → log `veille.first_delivery_failed` → `await asyncio.sleep(60)` → retry → si 2e échec : ouvrir session, charger `VeilleDelivery`, set `generation_state = FAILED`, `last_error = type(exc).__name__ + ': ' + str(exc)[:480]`, `finished_at = now`, commit. Logger `veille.first_delivery_failed_terminal` (config_id, attempts=2, error_class, error_msg).
   - **Capturer l'exception via `sentry_sdk.capture_exception(exc)`** dans le except — fermer le trou d'observabilité (le logger.error actuel ne déclenche pas Sentry sans config explicite).
2. **`packages/api/app/jobs/veille_generation_job.py:91-112`** `_process_config_with_semaphore` : même UPDATE FAILED + Sentry capture en cas d'exception. Pas de retry intra-scanner (le scanner re-tourne tous les 30 min, c'est déjà un retry naturel — sauf que `next_scheduled_at` aura bougé. À étudier en T1 pour garantir un retry plausible). Logger `veille.scanner_delivery_failed_terminal`.
3. **Spécifiquement pour EDBHANDLEREXITED** : aucun catch spécifique requis — on traite toute exception en marquant FAILED. Le retry 1× protège contre les transitoires.

### Mobile (T1)

- `veille_delivery_detail_screen.dart` : déjà OK (`_DeliveryFailedView` existe lignes 149-199). Affiner copy : "La livraison a échoué. Le facteur retentera à la prochaine planification." (au lieu de la phrase actuelle qui sous-entend un retry imminent).
- `_pollFirstDelivery` (`veille_config_screen.dart:175-208`) sort déjà sur `failed` — aucun changement nécessaire après T1.

### Bonus hors scope T1

- **Anomalie row succeeded vide** : ajouter une vérification dans POST /api/veille/config (`routers/veille.py:245-331`) pour rejeter `body.source_selections == []` avec un 422 (ou minima 1 source). À discuter PO — peut être déjà géré côté mobile mais le backend doit être autoritaire.
- **Migration garde-fou DB** : ajouter un `CHECK (generation_state != 'running' OR started_at >= NOW() - INTERVAL '15 minutes')` n'est pas réaliste en SQL pur, mais un script de cleanup périodique qui passe à FAILED toute row stuck > 15 min serait une ceinture-bretelle utile (à creuser plus tard).

## Logs bruts représentatifs

### Sentry PYTHON-3N (04/05 10:30:48) — root cause backend

```
exc: InternalError_ : (EDBHANDLEREXITED) connection to database closed.
  sqlalchemy/engine/base.py: _commit_impl
  sqlalchemy/engine/default.py: do_commit
  sqlalchemy/dialects/postgresql/psycopg.py: commit
  psycopg/connection_async.py: commit / wait
  psycopg/_connection_base.py: _commit_gen / _exec_command

tags:
  transaction: app.routers.veille.suggest_sources
  url: https://facteur-production.up.railway.app/api/veille/suggestions/sources
  user: id:fd6b9d0b-4c16-422b-9688-bae34d63f41c
  release: f2dfe331 (HEAD actuel)
  railway_service: WEB
```

### Sentry PYTHON-3J (04/05 10:30:48 — même seconde) — conséquence

```
exc: ExceptionGroup : unhandled errors in a TaskGroup
  starlette/_utils.py collapse_excgroups
  starlette/middleware/base.py __call__
  anyio/_backends/_asyncio.py __aexit__
exc: PendingRollbackError : Can't reconnect until invalid transaction is rolled back.

tags:
  transaction: app.routers.veille.suggest_sources
  user: id:fd6b9d0b-4c16-422b-9688-bae34d63f41c
```

### Supabase — row stuck (live, 04/05 15:09 UTC)

```
id: 90adb2e5-da1a-46f6-8fb1-38f6d54ad62c
veille_config_id: 6f3529f7-d97e-4f61-8916-b16f31457655 (user fd6b9d0b...)
generation_state: running
attempts: 1
started_at: 2026-05-04 10:39:13.836
finished_at: NULL
last_error: NULL
stuck_duration: 04:29:58
items: []
```

## Annexes

### Cas particulier — config sans sources (anomalie collatérale)

Config `3f6b0bf0-3d51-448b-b2d1-57ce81102eeb` (user `9406afbc...`, créée 2026-05-03 17:58) → 0 sources rattachées en DB → scanner périodique 2026-05-04 05:00 UTC tourne `digest_builder.build(config_id)` qui hit `not ctx.user_source_ids` à la ligne 71 → return `[]` → `_phase3_persist` marque SUCCEEDED avec items=[]. Durée 0.4 s. Pas un blocker T1 mais un signal de robustesse côté création de config (POST /config a actuellement aucune validation min sources). À traiter en hors-scope.

### Accès logs production (bilan session)

| Source | Status | Couverture |
|---|---|---|
| Sentry CLI + API REST | OK | Issues + events + tags + stacks |
| Supabase MCP `execute_sql` | OK | Read-only, query libres |
| PostHog MCP | OK (non utilisé ici) | Events analytics, pas exception capture |
| Railway CLI (`railway logs`) | **KO** | `RAILWAY_TOKEN=12e18d39-... Unauthorized`. Hook session-start affiche `[OK]` mais ne teste que la connectivité réseau, pas l'auth. Peut-être un Project Token expiré ou révoqué. |

→ **Action utilisateur requise pour combler le trou OOM/SIGTERM** : refresh le `RAILWAY_TOKEN` (Project Token sur https://railway.com/account/tokens) et re-lancer une session si on veut creuser ces hypothèses. Le verdict actuel **ne dépend pas** de Railway logs (Sentry suffit pour conclure HAUTE confiance sur EDBHANDLEREXITED).

## Décision proposée pour Phase 2

**GO Phase 2** sur le périmètre T1+T2+T3 du plan initial, avec ces ajustements :

1. **T1 retry policy** : 1× retry à T+60s (comme prévu) car les EDBHANDLEREXITED sont typiquement transitoires (pgbouncer recycling). Si le retry échoue → FAILED + Sentry capture.
2. **T1 Sentry capture** : ajouter `sentry_sdk.capture_exception` dans le except (en plus du logger.error) pour fermer le trou d'observabilité. À ajouter aussi dans `_process_config_with_semaphore`.
3. **T2** : la cause backend EDBHANDLEREXITED touche aussi `/suggestions/sources`. Le timeout 20 s sur le LLM ne suffira pas si l'erreur survient après le LLM (au moment du commit). Ajouter un `try/except SQLAlchemyError → rollback + raise HTTPException(503)` au niveau du router pour que le mobile reçoive un 503 propre (et affiche le retry, cf. T2 fix mobile).
4. **Hors scope** : intégrité min-sources sur POST /config + cleanup script rows stuck > 15 min — créer 2 issues GitHub séparées.

→ **STOP : GO PO sur ce plan d'investigation avant d'attaquer le code.**
