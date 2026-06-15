# Maintenance — Quick Start : démarrage app < 1s

## Status

In Progress — **PR1 (boot parallélisé) ✅ livrée** · **PR A (démarrage perçu quasi-instantané, mobile) ✅ livrée** · PR B (robustesse/scalabilité backend) à suivre.

> Le diagnostic post-PR1 a montré que le **matin** est structurellement différent
> des ré-ouvertures : le cache local est invalidé chaque nuit (jamais de SWR
> matinal), le JWT est mort (TTL 1h) et un `await refresh()` bloquant gatait le
> splash, et rien ne s'affichait avant le retour de **tous** les endpoints
> (3 de base + jusqu'à 14 feeds). PR A attaque ces trois gates. Détail ci-dessous.

## Problème

À l'arrivée sur l'app mobile, le temps perçu entre tap sur l'icône et contenu interactif est **>5s** (souvent 4.5–6.5s sur réseau correct, jusqu'à 20s+ si `/api/digest` renvoie 202 "preparing"). Objectif PO : **<1s perçu**.

## Diagnostic (path critique séquentiel bloquant)

```
main() bootstrap : Hive ×4 + Supabase + PostHog + Notifs (SÉRIEL)   ~1.5–2.5s
   ↓ runApp()
Splash + auth refresh (router bloqué isLoading)                      ~0.5–1.5s
   ↓ redirect /flux-continu
FluxContinuScreen mount → LoadingView() plein écran
   ↓ fluxContinuProvider._fetchAll() Future.wait 4 endpoints
   ↓ tout doit revenir avant rendu
[+ _fetchThemeSections() 3 appels SÉRIELS]
```

## Approche (3 PRs)

### PR1 — Boot mobile parallélisé (gain attendu −0.5 à −1s, toutes ouvertures)

- `Future.wait` sur les 4 `Hive.openBox` (était séquentiel)
- `Future.wait` sur Supabase / PostHog / FlutterDownloader (indépendants)
- Différer en post-runApp les services non-critiques pour la 1ère frame :
  - `ensureExactAlarmPermission` (system call lent)
  - `isDigestNotificationScheduled` + `scheduleDailyDigestNotification` (DB-backed alarm)
  - `getDiagnostics` + capture PostHog `notif_diag`
  - `HomeWidget.registerInteractivityCallback`
- Conserver `PushNotificationService.init()` dans le path critique (rapide, et nécessaire pour les notifications cold-launch)
- Réduire timeout Supabase 15s → 3s (au-delà, on continue avec la session Hive restaurée si dispo)
- Logs `[PERF]` pour mesurer chaque étape

### PR A — Mobile « Démarrage perçu quasi-instantané » ✅ livrée (gain matin garanti)

Une PR cohérente mobile-only, sans nouvelle dépendance. Réutilise
`FluxContinuCacheService`, les patterns `_compose`/`_refetchThemesOnly`/
`_refetchSourcesOnly` et le single-flight `SessionRefresher`.

- **A1 — Auth refresh non-bloquant** (`core/auth/auth_state.dart`) : `_init`
  peint l'état authentifié **immédiatement** (plus de `await refresh()`
  bloquant) ; le refresh tourne en arrière-plan, exposé via
  `AuthStateNotifier.initialRefresh`. Le `.catchError` ne gère que
  l'`AuthException` (refresh token mort → signout + `sessionExpired` identique à
  l'ancien chemin). On ne re-pose **jamais** `lastTokenRefreshAt` à la main :
  l'event SDK `tokenRefreshed` reste l'unique signal d'invalidation
  (cf. `bug-feed-403-auth-recovery.md`).
- **A2 — Cache → squelette fidèle** (`flux_continu_cache_service.dart`) :
  `readLatest()` ne jette plus sur day mismatch — pose `isStale` (+ lit
  `savedAt`). `readToday()` devient un wrapper « du jour uniquement ». Le cache
  d'hier sert à dessiner la structure, **jamais** à afficher du contenu périmé.
- **A3 — Provider squelette + rendu progressif 2 phases**
  (`flux_continu_provider.dart`) : `build()` peint un **squelette** (sections
  dérivées des prefs locales — favoris thèmes/sources, ordre Tournée) sur cache
  d'hier/cold, ou le **vrai** contenu sur snapshot du jour (SWR in-day). Garde
  **anti-tempête 401** : `await initialRefresh` borné (~3s) avant le batch, pour
  que les ~3+14 appels partent avec un JWT frais. `_fetchAll` émet en 2 phases :
  hero/Essentiel/Actus/Bonnes d'abord (≈ 1 round-trip de base), puis les
  sections thèmes/sources. Flag `isSkeleton` sur `FluxContinuState`. Un garde
  `_bootstrapping` neutralise les listeners de prefs pendant le bootstrap
  (le 1er `_fetchAll` lit déjà les prefs fraîches).
- **A4 — Squelette par section** (`flux_continu_screen.dart`) : remplace le
  `LoadingView()` plein écran par un scaffold `FluxContinuSkeleton` (en-têtes
  réels via `SectionBanner` + corps `ExploreDiscoverySkeleton`), non scrollable,
  hors physics de snap. Pas de lazy-load au scroll (garde-fou snap/haptique).
- **A5 — Micro-opt boot Sentry** : *non inclus* (optionnel, gain à confirmer au
  profiling ; réordonner l'init Sentry touche la capture des crashs de boot).

> Note d'archi (Riverpod) : `provider.future` se résout à la **1ère** émission
> mid-build. Comme `build()` émet désormais squelette→base→complet, les tests
> attendent l'état stabilisé (helper `settle()`) au lieu de `.future`.

### PR B — Backend « Robustesse & scalabilité du 1er démarrage » (à suivre)

- **Tuer le 202 du chemin critique** (cas nouveau-user post-store) : `/api/digest`,
  `/api/digest/both`, `/api/essentiel` renvoient toujours quelque chose vite
  (digest générique/découverte) + génération perso en background ; idéalement
  génération **eager au signup**.
- Caches : `Cache-Control` courts sur `/api/essentiel` + `/api/users/top-themes`,
  extension des caches in-memory (`digest_cache` 60s, `feed_cache` 30s).
- Payload allégé : ne pas servir `html_content` (10-50KB/article) dans la liste home.
- (Optionnel) endpoint agrégé `/api/home/bootstrap` (collapse 17→1) si la mesure
  PR A montre que le fan-out reste le goulot.

### Différé (après mesure)

- Pré-chargement background nuit (FCM data-push / WorkManager — absents du pubspec).
- Lazy-load des sections au scroll (levier fort mais risqué pour le snap).

## Fichiers touchés PR1

- `apps/mobile/lib/main.dart` — refactor bootstrap

## Fichiers touchés PR A

- `apps/mobile/lib/core/auth/auth_state.dart` — refresh non-bloquant + getter `initialRefresh`
- `apps/mobile/lib/features/flux_continu/services/flux_continu_cache_service.dart` — `readLatest()` + `isStale`/`savedAt`
- `apps/mobile/lib/features/flux_continu/providers/flux_continu_provider.dart` — squelette + 2 phases + garde `initialRefresh` + `_bootstrapping`
- `apps/mobile/lib/features/flux_continu/models/flux_continu_models.dart` — flag `isSkeleton`
- `apps/mobile/lib/features/flux_continu/screens/flux_continu_screen.dart` — `FluxContinuSkeleton` par section
- Tests : `flux_continu_cache_service_test.dart` (nouveau), `flux_continu_provider_test.dart` (squelette + 2 phases), migration `settle()` des suites flux provider.

## Vérification PR1

- `cd apps/mobile && flutter analyze`
- `cd apps/mobile && flutter test`
- Profiling timeline DevTools : mesurer `main()` → premier `runApp` avant/après
- Logs `[PERF] boot.*` dans la console pour validation

## Non-Goals PR1

- Pas de modification de l'écran d'arrivée (FluxContinuScreen) — PR2
- Pas de cache local pour les endpoints — PR2
- Pas de modification backend — PR3
- Pas de réécriture du retry digest 202 — PR3
