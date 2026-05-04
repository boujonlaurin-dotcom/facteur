# QA Handoff — Veille V3 PR1 Critical Fixes (T1+T2+T3)

## Feature développée

Trois correctifs critiques sur le flow Veille V3 :
- **T1** Backend : la première livraison veille atterrit maintenant en `succeeded` ou `failed` (jamais stuck en `running`). Retry transparent 1× après 60 s, capture Sentry + persistance `last_error`. Symétrie côté scanner périodique.
- **T2** Résilience : `/api/veille/suggestions/sources` retourne un 503 propre quand la DB ou le LLM lèvent — au lieu d'un 500 + session SQLAlchemy empoisonnée. Step 3 mobile expose un bouton « Réessayer » dans le fallback mock.
- **T3** Mobile : le bouton « Modifier ma veille » ouvre le flow en mode édition (`?mode=edit`) avec hydratation complète du state (thème, topics, sources, fréquence/jour, purpose, brief). Submit court-circuite la première livraison.

## PR associée

À ouvrir vers `main` : `boujonlaurin-dotcom/veille-v3-pr1-critical-fixes`. Lien `gh pr view --web` après push.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Step 3 Sources (onboarding veille) | `/veille/config` step 3 | Modifié — bouton retry sur fallback erreur |
| Veille Config Screen | `/veille/config?mode=edit` | Modifié — mode édition (hydrate, court-circuit submit) |
| Veille Dashboard | `/veille/dashboard` | Modifié — bouton « Modifier ma veille » route avec `?mode=edit` |
| Veille Delivery Detail | `/veille/deliveries/{id}` | Inchangé — `_DeliveryFailedView` déjà existant, vérifier qu'il rend après T1 |

## Scénarios de test

### S1 — T1 : Première livraison qui échoue passe à FAILED

**Préparation** :
1. App locale + API locale (`uvicorn app.main:app --port 8080`).
2. Mock `app.jobs.veille_generation_job.run_veille_generation_for_config` pour `raise RuntimeError("boom")` à chaque appel (modifier temporairement le code, ou monkey-patch via test fixture). Alternativement : faire planter le LLM (variable env `MISTRAL_API_KEY=invalid`).

**Parcours** :
1. Login avec un compte sans veille active.
2. Lancer l'onboarding veille (Step 1 → 4) jusqu'au submit.
3. Observer le loading screen post-step-4.
4. Attendre ~60 s (le retry interne) puis ~60 s de plus (la 2e tentative qui échoue).
5. Au bout de ~120 s, observer le poll s'arrêter sur `failed`.

**Résultat attendu** :
- Mobile : le snackbar « La génération a échoué. On retentera à la prochaine livraison. » apparaît, puis redirection vers le dashboard.
- DB : `SELECT generation_state, last_error, finished_at, attempts FROM veille_deliveries WHERE veille_config_id = '<id>'` → `failed` + `last_error` non-null contenant `RuntimeError: boom` + `finished_at` non-null + `attempts >= 1`.
- Sentry : 1 événement capturé (terminal handler après les 2 tentatives).

**Cas alternatif (succès au retry)** : mock `run_veille_generation_for_config` pour `raise` 1×, puis `return` succès. La row doit passer à `succeeded` après ~60 s et le mobile sortir du poll proprement.

### S2 — T2 : Step 3 Sources résilient sur erreur backend

**Préparation** :
1. Mock backend : modifier temporairement le router pour `raise OperationalError("test")` ou `raise httpx.TimeoutException("test")` dans `suggest_sources`.

**Parcours** :
1. Login + onboarding veille jusqu'au Step 3.
2. Sélectionner thème + topics (Step 1 + 2), atteindre Step 3.
3. Observer le rendu de Step 3.

**Résultat attendu** :
- Mobile : le widget `_MockSourcesFallback` est rendu avec le message « Suggestions indisponibles, conserve ta sélection. » + un bouton « Réessayer ».
- Tap sur « Réessayer » → relance l'appel `/suggestions/sources`. Si le mock backend est désactivé entre temps, les suggestions API doivent charger normalement.
- Backend : `curl -X POST /api/veille/suggestions/sources` retourne **503** avec `detail` contenant `Service temporairement indisponible.` (SQL error) ou `Suggestions LLM indisponibles.` (LLM timeout).
- Console Flutter : pas d'erreur unhandled, le state `AsyncError` est correctement géré.

### S3 — T3 : Mode édition « Modifier ma veille »

**Préparation** :
1. Compte avec une veille déjà active (config existante avec topics, sources, purpose).

**Parcours** :
1. Login → /veille/dashboard (vue de la config existante).
2. Tap sur « Modifier ma veille ».
3. Vérifier la route : URL `/veille/config?mode=edit`.
4. Step 1 doit s'afficher (PAS de redirect dashboard) avec le thème pré-sélectionné.
5. Naviguer Step 1 → 2 → 3 → 4 : vérifier que les topics, sources (followed + niche), fréquence, jour, purpose, brief sont tous pré-cochés/remplis.
6. Modifier au moins une valeur (ex. changer le jour de la semaine de Mar à Jeu).
7. Tap « Continuer » au Step 4 (submit).

**Résultat attendu** :
- Pas de loading screen « première livraison ».
- Snackbar « Veille mise à jour ».
- Redirection immédiate vers `/veille/dashboard`.
- DB : `SELECT day_of_week FROM veille_configs WHERE user_id = '<id>'` reflète la modification.
- Tap « X » du header en mode edit → retour dashboard, config existante intacte (pas de delete, pas de modif).

## Critères d'acceptation

### T1
- [ ] Row `veille_deliveries` passe à `failed` (jamais stuck en `running`) quand la génération échoue 2 fois.
- [ ] `last_error` contient le type + msg de l'exception (≤ 500 chars).
- [ ] Sentry capture l'exception via `sentry_sdk.capture_exception`.
- [ ] Mobile sort du poll sur `failed` et affiche le snackbar.
- [ ] Scanner périodique applique la même politique (pas de retry, FAILED direct).

### T2
- [ ] `POST /api/veille/suggestions/sources` retourne 503 (jamais 500) sur SQLAlchemyError.
- [ ] `POST /api/veille/suggestions/sources` retourne 503 sur httpx.TimeoutException / HTTPError.
- [ ] Step 3 mobile affiche un bouton « Réessayer » fonctionnel sur erreur.

### T3
- [ ] `?mode=edit` ouvre le flow sans redirect.
- [ ] State pré-rempli : thème, topics (preset/custom/suggested), sources (followed/niche), fréquence, jour, purpose, brief.
- [ ] Submit en mode edit → POST UPSERT + snackbar « Veille mise à jour » + retour dashboard.
- [ ] Cancel → retour dashboard, config intacte.

## Zones de risque

- **T1 Sentry capture en BackgroundTask** : FastAPI BackgroundTask n'a pas le middleware Sentry du request lifecycle. La capture explicite est obligatoire et doit être testée en prod (vérifier l'apparition d'un événement après un fail volontaire).
- **T2 SQLAlchemy session après rollback** : vérifier qu'aucune query subséquente sur la même session n'est tentée après le rollback (sinon `PendingRollbackError`). Le `raise HTTPException` après `await db.rollback()` est testé.
- **T3 hydratation idempotente** : le `addPostFrameCallback` peut se ré-exécuter à chaque rebuild. Le notifier est gardé idempotent par le check `state.selectedTheme != null` → no-op après la 1re hydratation.
- **T3 état autoDispose** : le `veilleConfigProvider` est `autoDispose`. Si le user ouvre /veille/config?mode=edit puis revient au dashboard puis re-ouvre, le state est reset → 1re hydratation s'applique à nouveau (correct, pas de leak d'état pré-cédent).

## Dépendances

- Backend endpoints : `POST /api/veille/suggestions/sources`, `POST /api/veille/deliveries/generate-first`, `POST /api/veille/config` (UPSERT).
- Sentry SDK (`sentry_sdk.capture_exception`).
- Provider Riverpod : `veilleActiveConfigProvider`, `veilleConfigProvider`, `veilleSourceSuggestionsProvider`.
- GoRouter `state.uri.queryParameters` pour lire `?mode=edit`.

## Tests automatisés livrés

- `packages/api/tests/test_veille_first_delivery_failure.py` (3 cas) — T1 retry + FAILED + scanner.
- `packages/api/tests/routers/test_veille_routes.py::TestSuggestions::test_sources_db_error_returns_503` — T2.
- `packages/api/tests/routers/test_veille_routes.py::TestSuggestions::test_sources_llm_timeout_returns_503` — T2.
- `apps/mobile/test/features/veille/providers/veille_config_provider_test.dart` (3 nouveaux cas) — T3 hydrateFromActiveConfig.

Test widget UI Step3 (T2 mobile) **non livré** côté unitaire — couvert par S2 Playwright + le test backend 503 garantit le contrat. À ajouter en suivi si récurrence.
