# PR — Veille V3 PR1 Critical Fixes (T1+T2+T3)

## Summary

Corrige le bug `loading infini` post-onboarding veille (50 % d'échec en bêta soft launch) en fermant 3 trous : **T1** persistance `failed` + retry + Sentry, **T2** résilience `/suggestions/sources` (503 propre), **T3** mode édition `?mode=edit` du flow Veille.

## Investigation préalable

Voir [`docs/bugs/bug-veille-gen-investigation.md`](../docs/bugs/bug-veille-gen-investigation.md). Cause racine : `_run_first_delivery` (router) + `_process_config_with_semaphore` (scanner) catchaient les exceptions sans persister `generation_state=failed` → row stuck en `running` indéfiniment, le poll mobile ne sortait jamais. Cause secondaire : EDBHANDLEREXITED Supabase pendant `db.commit()` du POST `/suggestions/sources` propage une session invalide qui plante la livraison qui suit.

## What

### T1 — Backend : `failed` state + retry + Sentry

- `packages/api/app/routers/veille.py` : refactor `_run_first_delivery` → `_run_first_delivery_with_retry(config_id, target_date, delivery_id)`. Boucle retry 1× T+60 s. Si 2e échec → UPDATE `veille_deliveries` (FAILED, last_error, finished_at, attempts) via `safe_async_session`. Capture `sentry_sdk.capture_exception`. Logger `veille.first_delivery_failed_terminal`.
- `packages/api/app/jobs/veille_generation_job.py` : symétrie scanner via `_mark_scanner_delivery_failed`. UPDATE FAILED + Sentry. Pas de retry intra-scanner (la passe suivante du scanner est le retry naturel).
- Pas de catch spécifique EDBHANDLEREXITED — `safe_async_session()` rouvre une connexion saine, le retry suffit.

### T2 — Backend résilience `/suggestions/sources` + Mobile retry CTA

- `packages/api/app/routers/veille.py:464-506` : try/except double autour de `suggester.suggest_sources(...)` + `db.commit()`. `SQLAlchemyError` → rollback + 503 « Service temporairement indisponible. ». `httpx.TimeoutException`/`HTTPError` → 503 « Suggestions LLM indisponibles. ». Capture Sentry des deux côtés.
- `apps/mobile/lib/features/veille/screens/steps/step3_sources_screen.dart` : `_MockSourcesFallback` accepte un callback `onRetry` optionnel ; le parent (Step3SourcesScreen) le branche sur `refreshKeepingChecked` quand l'AsyncValue est en error. Bouton « Réessayer » avec icône.

### T3 — Mobile : mode édition « Modifier ma veille »

- `apps/mobile/lib/features/veille/screens/veille_dashboard_screen.dart:165` : CTA route `/veille/config?mode=edit`.
- `apps/mobile/lib/config/routes.dart:415` : `pageBuilder` lit `state.uri.queryParameters['mode']` et passe `editMode` à `VeilleConfigScreen`.
- `apps/mobile/lib/features/veille/screens/veille_config_screen.dart` :
  - Ajout `final bool editMode;` au constructeur.
  - Guard ajustée : redirect dashboard uniquement si `!editMode`. En mode edit + activeConfig non-null + state.selectedTheme null → `addPostFrameCallback(notifier.hydrateFromActiveConfig)`.
  - `handleSubmit()` court-circuite la première livraison + la modal notif quand `editMode == true`. Snackbar « Veille mise à jour » + redirect dashboard.
- `apps/mobile/lib/features/veille/providers/veille_config_provider.dart` : nouvelle méthode `hydrateFromActiveConfig(VeilleConfigDto cfg)` (idempotent via check `selectedTheme != null`). Mappe topics par `kind` (preset/custom/suggested), sources par `kind` (followed/niche), fréquence/jour avec helpers `_frequencyFromWire`/`_dayFromWire`.

## Tests

### Backend
- `packages/api/tests/test_veille_first_delivery_failure.py` (3 cas) :
  - T1 retry-then-fail → row FAILED + last_error + sentry.
  - T1 retry-then-succeed → pas de FAILED persisté, pas de sentry.
  - T1 scanner exception → row FAILED + sentry.
- `packages/api/tests/routers/test_veille_routes.py::TestSuggestions` :
  - `test_sources_db_error_returns_503` (OperationalError → 503).
  - `test_sources_llm_timeout_returns_503` (httpx.TimeoutException → 503).
- Patch test existant : `test_creates_pending_delivery` référence maintenant `_run_first_delivery_with_retry`.

### Mobile
- `apps/mobile/test/features/veille/providers/veille_config_provider_test.dart` (3 nouveaux cas) :
  - hydrate populates state from DTO (theme, topics, sources, frequency, day, purpose).
  - hydrate idempotent (no-op si `selectedTheme` déjà set).
  - monthly frequency → day par défaut (mon).
- `flutter test` ciblé : 8/8 verts (5 anciens + 3 nouveaux).

### E2E (à valider via /validate-feature)
3 scénarios documentés dans `.context/qa-handoff.md` (S1 T1, S2 T2, S3 T3).

## How ça a été vérifié

- [x] `flutter test test/features/veille/providers/veille_config_provider_test.dart` → 8/8 verts.
- [x] `flutter analyze` sur les 5 fichiers mobile touchés → 0 errors (info `prefer_const` pré-existants).
- [ ] `pytest -v` (à lancer en /go — DB Supabase locale requise).
- [ ] `ruff format --check && ruff check` (à lancer en /go).
- [ ] `alembic heads` → 1 head (aucune migration ajoutée par cette PR).
- [ ] /validate-feature S1/S2/S3 (post-merge ou en pre-merge selon dispo QA).

## Hors scope (issues GitHub à créer)

1. **Intégrité min-sources POST `/config`** : rejeter `body.source_selections == []` avec 422.
2. **Cleanup script rows stuck > 15 min** : job périodique passe à FAILED toute row `generation_state='running' AND started_at < NOW() - INTERVAL '15 minutes'`.

## Zones à risque

- **BackgroundTask Sentry** : capture explicite obligatoire (FastAPI BackgroundTasks n'ont pas le middleware Sentry du request lifecycle). Vérifier en prod l'apparition d'un événement après un fail volontaire.
- **Session SQLAlchemy après rollback** : aucune query subséquente sur la session après `await db.rollback()` (le `raise HTTPException` est immédiat).
- **autoDispose + hydrate** : `veilleConfigProvider` est autoDispose ; le state est reset à chaque entrée du screen, donc l'hydratation se relance proprement à chaque visite en mode edit.

## Notes

- Branche créée depuis `origin/main` après `git fetch` (cf. memory `feedback_rebase_before_work.md`).
- `ruff format --check` + `ruff check` à lancer avant push (cf. memory `feedback_python_ruff_format_check.md`).
- Investigation doc `docs/bugs/bug-veille-gen-investigation.md` incluse dans la PR pour traçabilité.
