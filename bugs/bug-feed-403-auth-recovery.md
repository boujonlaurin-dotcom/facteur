# Bug — Feed 403 "Email not confirmed" au resume + pull-to-refresh gelé

**Statut** : PLAN — en attente GO utilisateur
**Branche** : `claude/fix-auth-resume-bug-IJWB3`
**PR cible** : `main` (jamais staging)

## Fichiers critiques

- `apps/mobile/lib/features/feed/providers/feed_provider.dart`
- `apps/mobile/lib/core/auth/auth_state.dart`
- `apps/mobile/lib/core/api/api_client.dart`
- `apps/mobile/lib/features/feed/screens/feed_screen.dart`
- `packages/api/app/dependencies.py`

## Symptôme utilisateur

1. L'utilisateur est connecté, email confirmé, feed fonctionne.
2. Il quitte l'app (background) plusieurs heures → JWT Supabase expire (~1h).
3. Il revient (resume) → le feed affiche **403 "Email not confirmed"**.
4. Le **pull-to-refresh devient inerte**.
5. Seule issue : kill l'app + re-login complet.

## Diagnostic — 3 failures qui s'enchaînent

### Maillon 1 : Race JWT stale au resume (auth_state.dart:316-329)

Au `AppLifecycleState.resumed`, `refreshUser()` est appelé en **fire-and-forget**
(pas d'`await`). En parallèle, le widget tree se reconstruit et le FeedScreen
peut déclencher un pull-to-refresh immédiat. `ApiClient._dio` lit alors
`_supabase.auth.currentSession.accessToken` **AVANT** que `refreshSession()`
n'ait propagé le nouveau token → envoi avec JWT stale.

**Aucune invalidation explicite de `feedProvider`** après le refresh.

### Maillon 2 : ApiClient déclenche `setForceUnconfirmed` sur timeout de refresh (api_client.dart:105-156)

Sur un 403 `Email not confirmed`, le flow :

```dart
try {
  final refreshed = await _supabase.auth.refreshSession().timeout(5s);
  if (refreshed.session != null) { /* retry request */ }
} catch (_) { /* timeout ou AuthException */ }

// FALLTHROUGH — fires même si refresh a timeout
if (onAuthError != null && isEmailNotConfirmed) {
  onAuthError!(403);   // 🔴 BUG : setForceUnconfirmed sur timeout transitoire
}
```

Sur réseau lent OU DB Supabase en slow-response, le refresh timeout à 5 s →
le code tombe dans le fallthrough et **déclenche `setForceUnconfirmed` sans
avoir de 2nd 403 confirmé par le backend**. L'user part sur l'écran email
confirmation alors que son email est valide.

### Maillon 3 : FeedNotifier.refresh fige le provider (feed_provider.dart:249-268)

```dart
Future<void> refresh() async {
  _page = 1; _hasNext = true; _isLoadingMore = false;
  try {
    final response = await _fetchPage(page: 1);
    state = AsyncData(FeedState(...));
  } catch (e, stack) {
    state = AsyncError(e, stack);   // 🔴 Efface les items existants
    rethrow;                          // 🔴 Propagé à RefreshIndicator
  }
}
```

Après `AsyncError`, `state.value` devient `null`. Tous les handlers du
FeedScreen qui guardent sur `if (currentState == null) return;` court-circuitent
→ muteSource, toggleSave, refresh inline, etc. deviennent no-op. Le
RefreshIndicator reste visible (ScrollView présent), mais un nouveau pull
réexécute `refresh()` → même échec → AsyncError persistant.

### Maillon 4 (aggravant) : 403 vs 401 asymétrique côté backend (dependencies.py:231-255)

Le backend distingue mal "JWT stale" de "user réellement non-confirmé" :
- JWT sans `email_verified` + DB confirmé → OK (return user_id)
- JWT sans `email_verified` + DB non-confirmé → 403 "Email not confirmed"
- JWT sans `email_verified` + DB unreachable → fail-open return user_id

Le 403 n'indique pas si c'est "vraiment non-confirmé" ou "JWT en cours de
rotation". Le mobile traite les 2 cas pareil (lock sur confirmation screen).

## Plan de fix

### P0 — Mobile — ApiClient ne déclenche plus `setForceUnconfirmed` sur timeout (api_client.dart)

**Objectif** : ne fire `onAuthError(403)` **que** si on a une preuve forte que
le user est non-confirmé (2nd 403 après retry avec JWT frais), jamais sur timeout.

- Supprimer le fallthrough final qui appelle `onAuthError!(403)` aveuglément.
- Conserver l'appel `onAuthError!(403)` uniquement dans la branche `retryErr.statusCode == 403`.
- Si le `refreshSession()` échoue/timeout : laisser le 403 original bubble up
  au caller (le FeedNotifier le captera comme erreur normale).
- Logger clairement chaque chemin (Sentry `addBreadcrumb` + `captureMessage`).

### P1 — Mobile — FeedNotifier.refresh recoverable (feed_provider.dart)

**Objectif** : un pull-to-refresh qui échoue ne doit **plus** effacer le feed
existant ni geler le provider.

Changement :
```dart
Future<void> refresh() async {
  _page = 1; _hasNext = true; _isLoadingMore = false;
  try {
    final response = await _fetchPage(page: 1);
    state = AsyncData(FeedState(items: response.items, carousels: response.carousels));
  } catch (e, stack) {
    // Conserver le state précédent (AsyncData) si présent — sinon seulement
    // marquer AsyncError. Ne plus rethrow : le RefreshIndicator est terminé,
    // les erreurs sont reportées via un SnackBar par le FeedScreen.
    final previous = state.valueOrNull;
    if (previous != null) {
      // Re-émettre AsyncData identique pour débloquer le refresh sans wipe.
      state = AsyncData(previous);
    } else {
      state = AsyncError(e, stack);
    }
    // Log + bubble vers le caller via un flag de dernier-erreur si utile.
    print('FeedNotifier: refresh failed: $e');
  }
}
```

Puis côté `FeedScreen._refresh()` : capturer l'erreur propagée (si toujours
`rethrow`ée par `refreshArticlesWithSnapshot`) et afficher un SnackBar plutôt
que de laisser le widget bloqué.

**Note** : `refreshArticlesWithSnapshot` appelle déjà `refresh()` en interne
sans catch — le changement au-dessus suffira.

### P2 — Mobile — Invalidation feedProvider au resume (auth_state.dart + main app)

**Objectif** : quand le JWT est rafraîchi, re-fetcher le feed **proprement**
au lieu de se retrouver avec des items stale et un access token obsolète.

Solution : exposer un `sessionRefreshTickProvider` (int counter) qui est
incrémenté par `AuthStateNotifier.refreshUser()` **après succès**. Le
`feedProvider` et autres data providers (ou le FeedScreen via `ref.listen`)
peuvent écouter et invalider.

Implémentation minimale (choix retenu) :
- Dans `FeedNotifier.build()`, ajouter `ref.watch(sessionRefreshTickProvider);`
  pour forcer un rebuild à chaque refresh d'auth.
- `AuthStateNotifier.refreshUser()` bumpe le tick via un callback injecté au
  moment de la construction du notifier **OU** via un StreamController statique
  consommé par un Provider.

Pattern simple : utiliser `_supabase.auth.onAuthStateChange` event `tokenRefreshed`
via un `StreamProvider` dédié, et `ref.watch` côté feedProvider. Plus découplé
que l'injection.

Choix d'implémentation : **utiliser un `StreamProvider<AuthChangeEvent?>` qui
expose les events `tokenRefreshed` de Supabase**. feedProvider le watch → tout
refresh de token invalide le feed. Pas de nouvelle API custom.

### P3 — Backend — Sentry tagging + log enrichi (dependencies.py)

**Objectif** : tracer la fréquence du scénario 403 pour mesurer l'impact du fix.

Changements :
- Sur `logger.warning("auth_user_blocked_unconfirmed", user_id=user_id)` : ajouter
  `sentry_sdk.capture_message("auth_user_blocked_unconfirmed", level="warning")`
  avec tags `{"jwt_alg": alg, "provider": provider}`.
- Sur `logger.warning("auth_db_unreachable_fail_open", ...)` : idem, avec
  `level="info"` pour tracker le fallback.

**PAS de conversion 403 → 401** ici : le 403 reste sémantiquement correct. La
vraie fix est côté mobile (P0) qui ne doit pas interpréter un 403 transient
comme définitif. Refaire le backend ajoutrait de la complexité pour un
bénéfice marginal.

### P4 — Tests

**Unit — `feed_refresh_recovery_test.dart` (nouveau)**
- `FeedNotifier.refresh()` face à une DioException 403 : state reste AsyncData
  avec les items précédents, pas d'AsyncError.
- `FeedNotifier.refresh()` sur premier appel (pas d'items précédents) : AsyncError OK.
- Le retry suivant après 403 transient réussit (mock repository).

**Unit — `auth_state_test.dart` (existant, ajouter cases)**
- `didChangeAppLifecycleState(resumed)` → `refreshUser()` succès → le
  stream `tokenRefreshed` est émis (ou le counter est bumpé).

**Unit — `api_client_403_test.dart` (nouveau)**
- 403 `Email not confirmed` + refresh timeout → `onAuthError` **PAS appelé**.
- 403 + refresh OK + retry 403 → `onAuthError(403)` appelé.
- 403 + refresh OK + retry 200 → `onAuthRecovered` appelé.

**E2E / Manual** (post-implementation)
- Scénario résumé dans `.context/qa-handoff.md` si on décide de lancer
  `/validate-feature` — non bloquant pour ce bug (pas de changement UI
  visible au-delà d'un SnackBar d'erreur).

## Critères d'acceptation

- [ ] Un user avec email confirmé qui revient de background après 1 h n'est
      **jamais** redirigé vers l'EmailConfirmationScreen.
- [ ] Un pull-to-refresh qui échoue (500, timeout, 403 transient) **conserve**
      les items du feed précédent + affiche un SnackBar d'erreur.
- [ ] Un 2e pull-to-refresh consécutif (après échec du 1er) a une chance de
      succéder — pas de state AsyncError gelé.
- [ ] Tous les tests unitaires existants passent.
- [ ] 3 nouveaux tests unitaires (feed refresh recovery + api client 403) passent.
- [ ] Sentry reçoit un event `auth_user_blocked_unconfirmed` pour chaque vrai
      403 backend (pour mesurer la baseline pré-fix).

## Hors-scope

- Refonte du flow `setForceUnconfirmed` / EmailConfirmationScreen.
- Nouveau endpoint `/auth/me/email-status` (mentionné dans
  `bug-auth-session-persistence.md`, traité séparément).
- Conversion backend 403 → 401 (choix explicite : fix côté mobile suffit).
