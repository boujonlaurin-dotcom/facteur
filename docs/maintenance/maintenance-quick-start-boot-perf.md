# Maintenance — Quick Start : démarrage app < 1s

## Status

In Progress — PR1/3 (boot parallélisé)

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

### PR2 — SWR Flux Continu + preload + rendu progressif (gain : ré-ouvertures <100ms perçu, 1ère ouverture −1 à −2s)

- `FluxContinuCacheService` (Hive `flux_continu_cache`, clé `flux_continu:{userId}:{date}`)
- `fluxContinuPreloadProvider` watché dans `FacteurApp.build()`
- Split `fluxContinuProvider._fetchAll` en sous-notifiers indépendants
- Remplacement `LoadingView()` plein écran par skeleton par section
- `Future.wait` sur les 3 themes (au lieu de série)

### PR3 — Backend caches + fix retry 202

- Cache in-memory 30s sur `/api/essentiel`, `/api/users/top-themes`, `/api/digest/both`
- Retry 202 digest non-bloquant + polling background mobile

## Fichiers touchés PR1

- `apps/mobile/lib/main.dart` — refactor bootstrap

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
