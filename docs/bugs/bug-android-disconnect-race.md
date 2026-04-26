# Bug — Déconnexions matinales Android (race "double-refresh")

**Statut** : EN COURS — implémentation
**Branche** : `boujonlaurin-dotcom/fix-android-auth-race`
**PR cible** : `main`
**Sévérité** : CRITIQUE (rétention)

## Symptôme

Presque chaque matin, l'app Android déconnecte l'utilisateur. Au tap sur l'icône, écran de login au lieu du digest. Touche tous les utilisateurs Android (100 % du trafic est Android).

Les fixes précédents (`bug-auth-flow.md`, `bug-auth-bounced-silent.md`, `bug-auth-session-persistence.md`, `bug-feed-403-auth-recovery.md`) se sont concentrés sur le 403 "Email not confirmed" et le flag `forceUnconfirmed` — la cause racine n'a jamais été traitée.

## Données factuelles

### Supabase Auth (9 dernières semaines, user `laurin_boujon@proton.me`)

- **210 sessions créées** — un user normal en aurait ~5
- **100 % des `refresh_tokens` sont `revoked=true`**
- Sessions de 50–500 min seulement, médiane ~3 h
- Pic de création de sessions : **8h–13h UTC** (10h–15h Paris) → cohérent avec usage matinal

### Trafic et observabilité

- 100 % Android (385 events sur 30 jours), pas d'iOS pour comparer
- Aucun event PostHog d'auth instrumenté (`user_logged_out`, `auth_error`, `session_expired` → 0)
- `email` jamais envoyé dans `$identify` PostHog → impossible de filtrer par user
- `sentry_flutter` est dans `pubspec.yaml:64` mais **jamais initialisé** (TODO `apps/mobile/lib/main.dart:223`)
- Backend Sentry : 0 erreur 401/auth/token sur 14 jours → la déconnexion ne vient pas du serveur

## Diagnostic — Race "double-refresh" sur refresh tokens single-use

Supabase utilise des refresh tokens en **mode rotation single-use** : chaque refresh révoque l'ancien et émet un nouveau. Si deux refresh partent en parallèle avec le même token, le 1er réussit, le 2e reçoit `AuthException` ("session_not_found", "Already Used", "invalid refresh token").

**6 endroits différents appellent `refreshSession()` sans coordination** :

| # | Localisation | Trigger |
|---|---|---|
| 1 | `apps/mobile/lib/core/auth/auth_state.dart:172` | Refresh bloquant à `_init()` (cold start) |
| 2 | `apps/mobile/lib/core/auth/auth_state.dart:312-323` | Timer proactif toutes les 45 min |
| 3 | `apps/mobile/lib/core/auth/auth_state.dart:367-371` | `AppLifecycleState.resumed` (fire-and-forget, **pas de await**) |
| 4 | `apps/mobile/lib/core/auth/auth_state.dart:719` | `refreshUser()` (proactif + resume) |
| 5 | `apps/mobile/lib/core/api/api_client.dart:81` | Interceptor Dio sur 401 (chaque requête en parallèle) |
| 6 | `apps/mobile/lib/core/api/api_client.dart:122` | Interceptor Dio sur 403 email_not_confirmed |
| 7 | SDK Supabase | `autoRefreshToken=true` par défaut |

### Scénario "déconnexion matinale" reproductible

1. App en background 8 h+ → JWT expiré, refresh token toujours valide
2. Au tap sur l'icône :
   - `AppLifecycleState.resumed` → `refreshUser()` non-awaité commence (path #3)
   - En parallèle, le widget tree rebuild, `feedProvider` / `sourcesProvider` / `posthog identify` envoient leurs requêtes → toutes 401
   - Chaque 401 déclenche un refresh dans l'interceptor (path #5) → 3-5 refresh simultanés
   - Le SDK Supabase planifie peut-être aussi son auto-refresh (path #7)
3. Le 1er refresh consomme le refresh token, génère un nouveau pair
4. Les autres refresh arrivent avec l'ancien refresh token → **`AuthException`**
5. `auth_state.dart:744-755` matche le pattern d'erreur ("session_not_found", "invalid refresh token") → `handleSessionExpired()` → `signOut()` + `sessionExpired=true` → **DÉCONNEXION**
6. OU `api_client.dart:95` `catch (_)` → `onAuthError(401)` → `handleSessionExpired()` → **DÉCONNEXION**

Cohérent à 100 % avec : 210 sessions/9 semaines + 100 % refresh tokens revoked + sessions de quelques heures seulement.

### Aggravants Android-spécifiques

- **Doze mode** plus agressif qu'iOS → l'app revient "froide" plus souvent (cold start vs warm resume) → plus d'opportunités pour le scénario
- `SupabaseHiveStorage` (`apps/mobile/lib/core/auth/supabase_storage.dart`) : si tué pendant `persistSession()` non-flushé, on relit une session stale au démarrage suivant

## Plan de fix

### P0 — Single-flight refresh (le seul fix qui arrête le saignement)

Nouveau singleton `SessionRefresher` dans `apps/mobile/lib/core/auth/session_refresher.dart` qui garantit qu'un seul `refreshSession()` est en vol à la fois. Tous les call sites (#1, #4, #5, #6) passent par ce singleton.

```dart
class SessionRefresher {
  Completer<Session?>? _inflight;

  Future<Session?> refresh({Duration timeout = const Duration(seconds: 8)}) async {
    if (_inflight != null) return _inflight!.future;
    final c = Completer<Session?>();
    _inflight = c;
    try {
      final res = await Supabase.instance.client.auth.refreshSession().timeout(timeout);
      c.complete(res.session);
      return res.session;
    } catch (e, st) {
      // Recheck SDK : un refresh interne (autoRefresh) a peut-être réussi entre-temps.
      final fresh = Supabase.instance.client.auth.currentSession;
      if (fresh != null && !fresh.isExpired) {
        c.complete(fresh);
        return fresh;
      }
      c.completeError(e, st);
      rethrow;
    } finally {
      _inflight = null;
    }
  }
}
```

### P1 — Recheck `currentSession` avant `handleSessionExpired`

Dans `refreshUser()` (`auth_state.dart:716-760`) : avant `handleSessionExpired()` sur `AuthException`, attendre 500 ms et re-lire `_supabase.auth.currentSession`. Si présente et valide → un autre caller a refresh OK → pas de signOut.

Symétrique dans `api_client.dart` `catch (_)` : recheck `currentSession` avant `onAuthError(401)`.

### P2 — Supprimer le timer proactif 45 min

`auth_state.dart:310-324` est redondant avec `autoRefreshToken=true` du SDK (refresh ~10 min avant expiration). Le supprimer évite une source de refresh concurrent.

### P3 — Au resume : await + flag isRefreshing

`auth_state.dart:367-371` : transformer `refreshUser()` non-awaité en `await`. Set `state.isRefreshing=true` pendant. L'`ApiClient` consulte ce flag avant d'envoyer une requête : si `true`, attendre la fin du refresh via le même `SessionRefresher`. Élimine la fenêtre de race.

### P4 — Hardening `SupabaseHiveStorage` (Android)

`supabase_storage.dart:78-92` :
- `try/catch` autour de `flush()` avec retry une fois sur `HiveError`
- Fallback miroir vers `flutter_secure_storage` (déjà dans `pubspec.yaml`) si Hive corrompu/inaccessible

### P5 — Instrumenter

1. **Initialiser `sentry_flutter`** dans `main.dart` (paquet déjà dans `pubspec.yaml`, juste un `Sentry.init()` à ajouter, DSN en `--dart-define`)
2. **PostHog events** :
   - `auth_session_expired` dans `handleSessionExpired()` avec property `reason` (refresh_failed, 401_after_refresh, network, refresh_token_revoked)
   - `auth_refresh_attempt` / `auth_refresh_success` / `auth_refresh_failure` (avec exception type)
   - `email` dans `$identify` (manquant aujourd'hui)
3. Capturer la stack trace de chaque `signOut()` non-explicite vers Sentry/PostHog

## Critères d'acceptation

- [ ] Un user Android avec session active qui revient de background après 8 h n'est **jamais** déconnecté
- [ ] 5 appels parallèles à `SessionRefresher.refresh()` → 1 seul appel SDK, tous les callers reçoivent la même session
- [ ] `refreshUser()` qui reçoit `AuthException` mais `currentSession` est valide → **PAS** de `handleSessionExpired`
- [ ] Tests unitaires nouveaux : `session_refresher_test.dart` + cases dans `auth_state_test.dart`
- [ ] Tous les tests existants passent
- [ ] Dashboard PostHog créé : `auth_session_expired` events par jour (cible : ~0)
- [ ] Vérification 2 semaines post-merge : nombre de sessions Supabase/user < 10/2sem (vs 210/9sem aujourd'hui)

## Hors-scope (déjà tenté ou orthogonal)

- Refonte du flag `forceUnconfirmed` (déjà 4 itérations dans `bug-auth-*`)
- Conversion 403 → 401 backend (rejeté dans `bug-feed-403-auth-recovery.md`)
- Migration `SupabaseHiveStorage` → `flutter_secure_storage` pur (raison historique du custom storage = bugs Keychain macOS)
- Refonte OAuth Apple/Google
