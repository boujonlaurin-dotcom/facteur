# QA Handoff — Feed staggered loading

> Rempli par l'agent dev pour input à `/validate-feature`.

## Feature développée

Refonte du chargement initial du `FeedScreen` en 3 phases progressives (`critical` → `postFrame` → `idle`) pour :
1. Réduire le burst de requêtes HTTP au mount (de ~8 simultanées à 2 critiques)
2. Afficher prioritairement le digest et le shell du feed
3. Conserver le loader éditorial (citations `loaderBlurbs`) qui apparaît à t=3 s quand le feed met du temps

## PR associée

Sera créée vers `main` après QA — branche `claude/feed-staggered-loading`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Feed principal | `/feed` | **Modifié** (staggered loading) |

## Scénarios de test

### Scénario 1 : Cold start happy path

**Parcours** :
1. Logout (si déjà connecté).
2. Login.
3. Atterrir sur `/feed`.
4. Capturer des screenshots à : t=200 ms, t=1 s, t=3 s, t=5 s.
5. Ouvrir DevTools Network pour compter les requêtes HTTP par tranche temporelle.

**Résultat attendu** :
- **t=200 ms** : shell (logo + avatar) + `DigestEntryCard` (avec son shimmer interne) + `LoadingView` éditoriale (`FacteurLoader` visible) dans le sliver feed. Filter bar visible mais badges onglets vides.
- **t=1 s** : digest rendu si l'API a répondu, filter bar peuplée (badges + sources). Feed encore en loading si réseau lent.
- **t=3 s** : si feed pas encore arrivé, la citation `EditorialLoaderCard` apparaît (texte + attribution Camus/Beuve-Méry/etc.).
- **t=5 s** : feed rendu intégralement.
- **Réseau** : ≤ 2 requêtes HTTP à t=0 (digest/both + feed?page=1). ≤ 5 à t=300 ms (ajout tab-counts, user-sources, first-impression deps). Le reste (custom-topics, app/update, swipe-hint…) déclenché après t+800 ms ou après l'arrivée des données feed.

### Scénario 2 : Pull-to-refresh

**Parcours** :
1. Sur `/feed`, tirer vers le bas pour déclencher le `RefreshIndicator`.
2. Observer le comportement réseau et UI.

**Résultat attendu** :
- Le feed se recharge.
- La phase reste `idle` (les widgets sont déjà montés), donc tous les providers se rafraîchissent en parallèle — c'est cohérent avec l'attente utilisateur d'un refresh global.
- Aucun flash de placeholder (les badges, sources, etc. restent visibles pendant le refresh).

### Scénario 3 : Toggle Serein

**Parcours** :
1. Sur `/feed`, basculer le toggle Serein dans le `DigestEntryCard`.
2. Observer.

**Résultat attendu** :
- Le toggle fonctionne comme avant (refresh feed avec `isSerein` updated).
- Pas de régression sur l'affichage du `DigestEntryCard` (ordre des deux cartes change selon le toggle).

### Scénario 4 : SearchFilterSheet (trending topics)

**Parcours** :
1. Sur `/feed`, ouvrir la `SearchFilterSheet` (icône loupe dans filter bar).
2. Observer les trending topics.

**Résultat attendu** :
- Les trending topics se chargent à l'ouverture de la sheet (lazy), pas au mount du feed.
- Aucune régression vs avant.

### Scénario 5 : Cas réseau lent (3G simulé)

**Parcours** :
1. Chrome DevTools → Network → Throttling "Slow 3G".
2. Hard reload sur `/feed`.
3. Observer.

**Résultat attendu** :
- Le shell + `LoadingView` apparaissent immédiatement.
- La citation `EditorialLoaderCard` apparaît à t=3 s, rendant l'attente moins frustrante.
- Le digest s'affiche dès que `/digest/both` répond (probablement avant le feed sur 3G car payload plus léger).
- Aucune erreur console.

## Critères d'acceptation

- [ ] Le shell du feed (header + DigestEntryCard placeholder + LoadingView) est visible en moins de 300 ms après navigation vers `/feed`.
- [ ] Le digest s'affiche dès que `GET /api/digest/both` répond, sans attendre `/api/feed`.
- [ ] La citation `EditorialLoaderCard` apparaît bien à t=3 s sur réseau lent.
- [ ] Au plus 2 requêtes HTTP sortent à t=0 (digest + feed).
- [ ] PostHog reçoit les events `feed_load_timing` avec les 2 milestones (`first_paint`, `digest_visible`) et un `duration_ms` plausible.
- [ ] Aucune régression sur : pull-to-refresh, toggle Serein, filter bar, search sheet, navigation vers un article.
- [ ] Aucune erreur console pendant tout le parcours.

## Notes pour l'agent QA

- Le `FeedScreen` est `apps/mobile/lib/features/feed/screens/feed_screen.dart`.
- Le provider de phase : `apps/mobile/lib/features/feed/providers/feed_load_phase_provider.dart`.
- Le tracking analytics : `AnalyticsService.trackFeedLoadTiming` (`milestone` + `durationMs`).
- Pour observer les phases en runtime : Riverpod DevTools → `feedLoadPhaseProvider`.
