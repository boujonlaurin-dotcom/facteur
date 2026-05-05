# QA Handoff — Veille `/suggestions/sources` : savepoint + timeouts + retry mobile

## Feature développée
Hotfix critique sur le bug "loading infini" perçu en Step 3 de l'onboarding veille (PYTHON-3P/3Q : 13 occurrences en 3 h, 2 users). Trois corrections backend (savepoint par candidat, timeouts par candidat + global LLM, sentry capture) + une correction mobile (réintroduction du bouton « Réessayer » perdu dans PR2 #562).

## PR associée
À créer après /go (cible : `main`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Step 3 — Sources | `/veille/config` (step 3) | Modifié (bouton Réessayer dans `_MockSourcesFallback`) |

## Scénarios de test

### Scénario 1 : Happy path — sources arrivent normalement
**Parcours** :
1. App connectée, sans veille active.
2. Aller sur `/veille/config` → Step 1 (thème) → choisir « Tech ».
3. Step 2 (topics) → choisir 2-3 topics.
4. Step 2 → tap « Continuer ».
5. Animation halo Step 2→3.
**Résultat attendu** :
- Le serveur répond en < 25 s (timeouts en place).
- Step 3 affiche la liste rankée par pertinence (8-12 sources).
- Aucun spinner infini.

### Scénario 2 : Backend hang sur un domaine bad
**Parcours** :
1. Reproduire localement avec un candidat URL qui hang (ex : `binge.audio/feed/`).
2. Lancer `/api/veille/suggestions/sources`.
**Résultat attendu** :
- Backend skip le candidat après 8 s (`source_suggester.candidate_timeout` log).
- Les autres candidats sont ingérés normalement.
- Réponse 200 sous 25 s.

### Scénario 3 : Backend 503 (PendingRollbackError simulé) — fallback mobile
**Parcours** :
1. Backend down ou throw 503 sur `/suggestions/sources`.
2. Step 3 mounted → spinner pendant ~30 s (timeout Dio) puis erreur API.
**Résultat attendu** :
- Mock fallback affiché avec message « Suggestions indisponibles, conserve ta sélection. ».
- **Bouton « Réessayer » présent et cliquable** (régression PR2 #562 corrigée).
- Tap « Réessayer » → relance la requête (`refreshKeepingChecked`).
- Si backend toujours KO → reste sur le mock fallback ; si recovery → liste rankée affichée.

### Scénario 4 : LLM Mistral timeout (> 20 s)
**Parcours** :
1. Configurer un délai artificiel sur le serveur mock LLM ou couper Mistral API.
2. Appeler `/suggestions/sources`.
**Résultat attendu** :
- Backend bascule sur `_fallback` (sources curées du thème).
- Réponse 200 avec `sources` non-vide (relevance_score=null).
- Log `source_suggester.llm_timeout` émis.

### Scénario 5 : Une violation de contrainte ne poison plus la session
**Parcours** :
1. LLM produit 3 candidats dont un avec un `name` > 200 chars (violation `String(200)`).
2. Backend ingère.
**Résultat attendu** :
- Le candidat fautif est skippé via SAVEPOINT rollback.
- Les 2 autres candidats sont ingérés et committés.
- `db.commit()` final ne lève pas `PendingRollbackError`.
- Le candidat fautif est remonté à Sentry via `sentry_sdk.capture_exception`.

## Critères d'acceptation
- [ ] **Backend** : `pytest tests/test_veille_source_ingestion.py` → tests verts (incluant 3 nouveaux : `test_session_recovers_from_integrity_error`, `test_slow_candidate_is_skipped`, `test_llm_timeout_falls_back_to_curated`).
- [ ] **Mobile** : `flutter test test/features/veille/screens/step3_sources_screen_test.dart` → 1 test vert (bouton Réessayer présent + cliquable + déclenche fetch).
- [ ] **Sentry** : zéro nouvelle occurrence PYTHON-3P 24 h après merge en prod.
- [ ] **Supabase** : `SELECT count(*) FROM sources WHERE created_at > NOW() - INTERVAL '24 hours' AND is_curated = false` > 0 (preuve qu'au moins une ingestion réussit).
- [ ] **E2E mobile** : flow complet onboarding veille → Step 3 affiche des sources réelles (pas le mock fallback) sur thème `tech` avec topics IA.

## Zones de risque

1. **Savepoint behaviour avec test fixture `db_session`** : la fixture utilise `join_transaction_mode="create_savepoint"` ; les `session.begin_nested()` du code de prod créent des savepoints imbriqués. Vérifier que les tests de la suite pré-existante (15 dans `test_veille_source_ingestion.py`) restent verts.

2. **`asyncio.wait_for` + httpx timeouts** : `EditorialLLMClient` a déjà un `httpx.Timeout(30.0)` ; `_LLM_TIMEOUT_S=20s` est plus strict, donc effectif. RSSParser a 7 s par requête HTTP → un candidat qui exécute 14 variants suffix peut quand même dépasser 8 s ; le timeout par candidat coupe net.

3. **Sentry noise potential** : `sentry_sdk.capture_exception` dans le `except Exception` peut générer du bruit si le LLM produit régulièrement des candidats invalides. À surveiller dans les premiers jours post-merge ; ajuster le filter rule si > 50/jour.

## Dépendances

- **Endpoints touchés** : POST `/api/veille/suggestions/sources`.
- **Services backend** : `SourceSuggester`, `SourceService.detect_source` (RSSParser), `EditorialLLMClient` (Mistral).
- **Mobile** : `VeilleSourcesSuggestionsNotifier` (provider famille autoDispose), `Step3SourcesScreen`.
- **Doc** : `docs/bugs/bug-veille-suggestions-sources-pending-rollback.md` (diagnostic + fix complet).

## Hors scope (à créer en issues séparées)

- **Optim RSSParser** : éviter les 14 variants suffix sur un même domaine (les 100+ HTTP calls par request). Refactor `detect()` pour bail-out plus tôt.
- **Cleanup script rows stuck `running > 15min`** : pré-existait à ce bug.
