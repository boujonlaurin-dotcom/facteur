# Bug: Veille — configs créées sans sources → digests vides systématiques

## Statut
- [x] Corrigé (date: 2026-05-07)

## Sévérité
🔴 Critique — 4 des 7 livraisons des 14 derniers jours (dont les 2 plus récentes post-#577) avaient `source_count=0` côté config, donc `item_count=0` côté delivery. Symptôme côté PO : « la 1ère veille n'arrive pas en fin d'onboarding ».

## Description

Symptômes signalés par le PO (2026-05-07), après #577 (mode Wow + watchdog) :

1. **À la fin de la configuration**, aucune 1ère veille n'arrive — l'utilisateur ne voit rien.
2. **Dans l'historique**, certaines livraisons affichent « La livraison a échoué » avec `last_error='watchdog_backfill: stuck running …'` — texte technique brut affiché à l'user.

## Cause racine

Pipeline déterministe une fois `/api/veille/suggestions/sources` en erreur (encore actif malgré #567/#568/#572/#575) :

1. `/suggestions/sources` retourne 503/timeout → mobile retombe sur `_MockSourcesFallback` (`apps/mobile/lib/features/veille/screens/steps/step3_sources_screen.dart`).
2. Le user coche/décoche dans la liste mock (`VeilleMockData.followedSources/nicheSources`) qui n'a **pas** de `apiSourceId`.
3. `_buildUpsertRequest` (`apps/mobile/lib/features/veille/providers/veille_config_provider.dart:872-885`) **filtre tous les mocks** (`if (meta?.apiSourceId == null) continue;`) → `source_selections=[]`.
4. Backend `POST /api/veille/config` (`packages/api/app/routers/veille.py:249-335`) acceptait sans broncher (aucune validation min sources) → table `veille_sources` = 0 row.
5. `POST /deliveries/generate-first` lance le background task → `digest_builder.build()` hit `if not ctx.user_source_ids: return []` (path `skip_empty_config`).
6. Delivery passe à SUCCEEDED en ~250 ms avec `items=[]`.
7. Mobile poll voit `succeeded`, navigue vers `/veille/deliveries/<id>` → `_DeliveryEmptyView` rend « Pas de cluster pour cette livraison. ».

Côté symptôme 2 : `_DeliveryFailedView` affichait directement `delivery.lastError` (texte technique non-i18n) sous le titre.

## Solution

### Phase A — Empêcher la création de configs sans sources

- **Backend (A1)** : `VeilleConfigUpsert.source_selections` passe à `min_length=1` (Pydantic 422). Filet final dans `upsert_config` : si toutes les selections collapsent au même source_id après dedup, `HTTPException(422, "Sélectionne au moins une source pour ta veille.")` après `db.rollback()`.
- **Mobile (A2)** : `VeilleConfigState.realSelectedSourceCount` = nombre de sources avec `apiSourceId` non-null. Step 3 `VeilleCtaButton(onPressed: hasRealSource ? notifier.goNext : null)` + hint « Sélectionne au moins une source pour continuer. ».
- **Mobile (A3)** : suppression de la liste mock cliquable du fallback Step 3. Quand `/suggestions/sources` est en erreur ou retourne `[]`, on n'affiche plus que `_SuggestionsUnavailable` (texte d'erreur sobre + bouton « Réessayer »). Le bouton « + Ajouter une source » (qui passe par `addCustomSourceToVeille` avec un vrai `apiSourceId`) reste disponible.
- **Mobile (A4)** : `veille_config_screen.dart` distingue `e.statusCode == 422` (validation, message ciblé) du reste (network/réessayer).

### Phase B — Nettoyage historique

- **B1** : DELETE des 5 rows historiques cassées (4 succeeded `item_count=0` + 1 failed `watchdog_backfill`) via Supabase MCP. Décision PO : pure suppression (dette dev/bêta, pas de donnée user de valeur).
- **B2** : `_DeliveryFailedView` n'affiche plus `lastError` brut. Le texte technique reste dans Sentry/logs.

### Phase C — Filets

- **C1** : `cleanup_stuck_running_deliveries` dans `app/jobs/veille_generation_job.py`, scheduled `*/5 min` via `IntervalTrigger`. Marque FAILED toute row `RUNNING > 15 min` (worker SIGKILL/OOM Railway non rescannés). Capture Sentry par row.
- **C2** : `posthog.capture("veille_config_submitted", source_count=…)` dans `upsert_config` pour mesurer si la métrique tombe bien à 0% après A1.

## Fichiers modifiés

- `packages/api/app/schemas/veille.py` — `min_length=1` sur `source_selections`.
- `packages/api/app/routers/veille.py` — 422 post-dedup + PostHog capture.
- `packages/api/app/jobs/veille_generation_job.py` — `cleanup_stuck_running_deliveries`.
- `packages/api/app/workers/scheduler.py` — job `veille_stuck_cleanup` `*/5 min`.
- `packages/api/tests/routers/test_veille_routes.py` — tests 422.
- `packages/api/tests/test_veille_generation_job.py` — tests cleanup stuck.
- `apps/mobile/lib/features/veille/providers/veille_config_provider.dart` — getter `realSelectedSourceCount`.
- `apps/mobile/lib/features/veille/screens/steps/step3_sources_screen.dart` — fallback sans liste mock + CTA disabled.
- `apps/mobile/lib/features/veille/screens/veille_config_screen.dart` — message 422 ciblé.
- `apps/mobile/lib/features/veille/screens/veille_delivery_detail_screen.dart` — drop `lastError` UI.
- `apps/mobile/test/features/veille/screens/step3_sources_screen_test.dart` — test fallback + test CTA disabled.

## Hors scope

- Stabilisation `/api/veille/suggestions/sources` (root cause `IdleInTransactionSessionTimeout`, ouvre un sprint dédié). A1+A3 protègent l'utilisateur indépendamment : même si la suggestion est en 503, l'user doit choisir au moins une source via « + Ajouter une source » avant de continuer.
- Mapping LLM-slug → taxonomie canonique (déjà tracé dans `bug-veille-empty-digests-and-no-wow.md`).

## Validation

- pytest `test_veille_routes::test_post_rejects_empty_source_selections` + `test_post_rejects_missing_source_selections` → 422.
- pytest `test_veille_generation_job::TestCleanupStuckRunning` → row stuck >15 min FAILED, row récente intacte.
- flutter test `step3_sources_screen_test` → fallback texte + CTA disabled state.
- DB post-fix : `SELECT COUNT(*) FROM veille_configs vc WHERE NOT EXISTS (SELECT 1 FROM veille_sources WHERE veille_config_id=vc.id)` doit retourner 0.
