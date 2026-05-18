# Maintenance — Feed staggered loading

> **Date** : 2026-05-18
> **Branche** : `claude/feed-staggered-loading`
> **PR ciblée** : `main`
> **Type** : optimisation perf + UX (réduction du burst de requêtes au mount)

## Contexte

Après la refonte récente du feed, l'arrivée de l'utilisateur sur `FeedScreen` déclenche **~8 providers Riverpod en parallèle**, ce qui produit :

- un **burst de ~8 requêtes HTTP simultanées** par user-login → risque de saturation du pool DB Railway (historiquement la 1ʳᵉ cause de crash de l'app) ;
- un **temps de chargement perçu de 4-8 s**, variable selon la connexion.

Demandes du CEO (Laurin) :
1. Soulager le serveur (réduire le burst initial).
2. Rendre le chargement progressif — le digest étant déjà toujours en tête du feed, l'afficher en premier puis lancer le reste.
3. S'assurer que le loader éditorial (citations) reste bien visible pendant l'attente — il existe déjà (`loader_blurbs.dart` + `EditorialLoaderCard`), mais l'attente est parfois assez courte pour qu'il ne se déclenche pas (reveal à t=3 s).

## Approche retenue : staggered loading Flutter-only

Pas de refonte backend. Les providers Riverpod étant lazy (déclenchés au premier `ref.watch`), on contrôle leur ordre via un nouveau `feedLoadPhaseProvider` (enum `critical | postFrame | idle`) qui avance par vagues :

| Phase | Trigger | Requêtes / providers déclenchés |
|-------|---------|---------------------------------|
| **Critical** (t=0) | mount | `feedProvider` (GET /api/feed?page=1), `digestProvider` (GET /api/digest/both via `DigestEntryCard`) |
| **Post-frame** (~t+16 ms) | `WidgetsBinding.addPostFrameCallback` | `tabCountsProvider`, `userSourcesProvider`, `firstImpressionSlotProvider` (qui dépend de notif settings, renudge, well-informed, ios-add-to-home) |
| **Idle** (t+800 ms OU dès que `feedProvider` est `AsyncData`) | Timer fallback OR feed listener | `customTopicsProvider`, `swipeLeftHintSeenProvider`, `appUpdateProvider`, et tous les watches déjà naturellement gatés par `feedAsync.when data` (streak, savedSummary, pepites, sereinToggle, etc.) |

**Endpoint backend agrégé `/feed/bootstrap` explicitement écarté** : il imposerait au first paint le coût de la requête la plus lente (feed page 1, double-phase query) et supprimerait le gain UX du progressive rendering.

## Changements

### Nouveau fichier

- `apps/mobile/lib/features/feed/providers/feed_load_phase_provider.dart`
  - `enum FeedLoadPhase { critical, postFrame, idle }`
  - `feedLoadPhaseProvider = StateProvider<FeedLoadPhase>(...)`
  - Helpers `advanceFeedLoadPhase(Ref)`, `advanceFeedLoadPhaseFromWidget(WidgetRef)`, `resetFeedLoadPhase(WidgetRef)` — transitions monotoniques (impossible de redescendre).

### Fichiers modifiés

- `apps/mobile/lib/features/feed/screens/feed_screen.dart`
  - `initState` : démarre `Stopwatch` analytics + planifie Phase 2 (post-frame callback) et Phase 3 (Timer 800 ms).
  - `build` : lit `feedLoadPhaseProvider` puis gate les `ref.watch` non-critiques selon la phase (filter bar, avatar update badge, topics suivis, hint seen, etc.).
  - `ref.listen(feedProvider)` : ajout du tracking `first_paint` + auto-advance vers Phase 3 dès l'arrivée des données feed.
  - `ref.listen(digestProvider)` : nouveau, tracking `digest_visible_ms`.
  - `ref.listen(appUpdateProvider)` : déplacé sous condition Phase 3.

- `apps/mobile/lib/core/services/analytics_service.dart`
  - Nouvelle méthode `trackFeedLoadTiming({milestone, durationMs})` qui logue à la fois côté backend (`_logEvent`) et PostHog (`feed_load_timing`).

### Tests

- `apps/mobile/test/features/feed/feed_load_phase_provider_test.dart` (nouveau, 5 tests)
  - Défaut = `critical`
  - Progression monotonique
  - Refus de redescendre
  - Idempotence
  - Extensions `hasReachedPostFrame` / `hasReachedIdle`

## Vérification

### Tests locaux
```bash
cd apps/mobile && flutter test test/features/feed/feed_load_phase_provider_test.dart
# → 5/5 passent
```

### Mesures perf (PostHog)
Surveiller sur 24 h post-deploy via le projet PostHog "Facteur" :
- `feed_load_timing` event, filtré par `milestone` :
  - `first_paint` — cible p50 < 1 000 ms, p95 < 2 500 ms
  - `digest_visible` — cible p50 < 1 500 ms
- Comparaison cohorte avant/après le merge.

### Backend (sans modification)
- Logs Railway : observer le nombre de connexions DB simultanées par user-login pendant le pic matinal. Cible : -60 % à -75 % sur le burst peak.
- Sentry : surveiller la disparition de `connection pool exhausted`.

### Régression à valider explicitement
- `SearchFilterSheet` charge bien `trendingTopicsProvider` à l'ouverture (lazy, non-modifié).
- Pull-to-refresh : tous les providers se rafraîchissent correctement (la phase reste `idle` pendant un refresh — les widgets sont déjà montés, donc le bénéfice staggered ne s'applique qu'au cold start).
- Filter bar : badges onglets affichent 0 pendant ~16 ms puis se peuplent. Aucun freeze.

## Hors scope (à réévaluer si insuffisant)

- Endpoint backend agrégé `/feed/bootstrap`.
- Caching HTTP `Cache-Control: private, max-age=60` sur `/feed/tab-counts` et `/feed/trending-topics`.
- Modification du reveal-delay de la citation éditoriale (reste à t=3 s, conforme à la demande du CEO).
- Skeleton placeholders.
