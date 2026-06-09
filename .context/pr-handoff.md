# PR A — Mobile : démarrage perçu quasi-instantané (squelette + auth non-bloquant + rendu progressif)

## Résumé

À l'ouverture matinale, le temps perçu tap→contenu était >5s (jusqu'à 20s+ si
`/api/digest` renvoie 202). Le matin est structurellement différent des
ré-ouvertures : le cache local est invalidé chaque nuit (jamais de SWR matinal),
le JWT (TTL 1h) est mort et un `await refresh()` **bloquant** gatait le splash,
et rien ne s'affichait avant le retour de **tous** les endpoints (3 de base +
jusqu'à 14 feeds thèmes/sources). Cette PR (mobile only, aucune nouvelle
dépendance) supprime ces trois gates.

## Changements

- **A1 — Auth refresh non-bloquant** (`core/auth/auth_state.dart`)
  - `_init` peint l'état authentifié **immédiatement** ; le refresh tourne en
    arrière-plan, exposé via `AuthStateNotifier.initialRefresh`.
  - `.catchError` ne gère que l'`AuthException` (refresh token mort → signout +
    `sessionExpired`, identique à l'ancien chemin bloquant). On ne re-pose
    **jamais** `lastTokenRefreshAt` à la main : l'event SDK `tokenRefreshed`
    reste l'unique signal d'invalidation (cf. `bug-feed-403-auth-recovery.md`).
    Single-flight conservé via `SessionRefresher` (cf.
    `bug-android-disconnect-race.md`).

- **A2 — Cache → squelette fidèle** (`services/flux_continu_cache_service.dart`)
  - `readLatest()` ne jette plus sur day mismatch — pose `isStale` + lit
    `savedAt`. `readToday()` devient un wrapper « du jour uniquement ». Le cache
    d'hier sert à dessiner la structure, **jamais** à afficher du contenu périmé.

- **A3 — Provider squelette + rendu progressif 2 phases**
  (`providers/flux_continu_provider.dart`)
  - `build()` peint un **squelette** (sections dérivées des prefs locales :
    favoris thèmes/sources, ordre Tournée, veille) sur cache d'hier/cold, ou le
    **vrai** contenu sur snapshot du jour (SWR in-day).
  - **Garde anti-tempête 401** : `await initialRefresh` borné (~3s) avant le
    batch → les ~3+14 appels partent avec un JWT frais ; sinon l'intercepteur 401
    single-flight reste le filet.
  - `_fetchAll` (via `_buildStateFromPayload`) émet en 2 phases :
    hero/Essentiel/Actus/Bonnes d'abord (≈ 1 round-trip de base), puis les
    sections thèmes/sources. L'émission progressive ne se fait QUE quand un
    squelette est monté (pas de blink en SWR / pull-to-refresh).
  - Flag `isSkeleton` sur `FluxContinuState`. Garde `_bootstrapping` : neutralise
    les listeners de prefs pendant le bootstrap (le 1er `_fetchAll` lit déjà les
    prefs fraîches) — restaure l'invariant « aucune réaction de listener avant le
    1er build complet ».

- **A4 — Squelette par section** (`screens/flux_continu_screen.dart`)
  - Remplace le `LoadingView()` plein écran par `_FluxContinuSkeleton`
    (en-têtes réels via `SectionBanner` + corps `ExploreDiscoverySkeleton`),
    non scrollable, hors physics de snap. **Pas** de lazy-load au scroll
    (garde-fou snap/haptique, cf. mémoire `flux_snap_haptic_feel`).

- **A5 — Micro-opt Sentry** : non inclus (optionnel, gain à confirmer au
  profiling ; réordonner l'init Sentry touche la capture des crashs de boot).

## Note d'archi (Riverpod) — important pour la review

`provider.future` se résout à la **1ère** émission mid-build (vérifié). Comme
`build()` émet désormais squelette → base-only → complet, les tests attendent
l'état stabilisé via un helper `settle()` au lieu de `.future`. Migration
appliquée aux 3 suites flux provider (comportement final inchangé).

## Vérification

- `flutter analyze` : **clean** sur les 5 fichiers lib touchés ; 0 erreur projet.
- Tests : `flutter test test/features/flux_continu/ test/features/auth/ test/core/auth/`
  → `+272 -3`. Les **3 échecs sont pré-existants** (baseline pristine = `+266 -3` :
  `essentiel_hi_fi_card` badge Météo/layout — flaky, et `router_redirection`
  EmailConfirmationScreen — Hive/Supabase non init en widget test). **Aucun
  nouvel échec dans les zones touchées.**
- Tests ajoutés :
  - `flux_continu_cache_service_test.dart` (nouveau) : `readLatest` isStale/savedAt,
    `readToday` null sur périmé, JSON corrompu → null.
  - `flux_continu_provider_test.dart` : cache d'hier → 1ère peinture squelette
    (jamais de contenu périmé) ; cold → base-only émis avant les sections thèmes.

## À faire côté review / suivi (hors PR)

- **Profiling cold-launch sur device réel** + simulation d'un matin (cache d'hier)
  pour mesurer splash→1ère frame avant/après (le plancher moteur Flutter domine
  l'absolu ; on prouve la suppression des gates refresh + fan-out). Logs
  `[PERF] fluxContinu.build mode=content_fresh|skeleton_stale|cold` ajoutés.
- **PR B (backend)** recommandée juste après : tuer le 202 du chemin critique
  (cas nouveau-user post-store), caches courts, payload allégé. Voir
  `docs/maintenance/maintenance-quick-start-boot-perf.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
