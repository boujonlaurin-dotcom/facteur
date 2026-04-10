# Bug — Déconnexions récurrentes & re-demande de confirmation email

**Statut** : En cours
**Branche** : `boujonlaurin-dotcom/fix/auth-session-persistence`
**Fichiers critiques** :
- `packages/api/app/dependencies.py`
- `apps/mobile/lib/core/auth/auth_state.dart`
- `apps/mobile/lib/core/api/api_client.dart`
- `apps/mobile/lib/core/api/providers.dart`
- `apps/mobile/lib/features/auth/screens/email_confirmation_screen.dart`

## Symptôme

L'utilisateur est déconnecté de manière récurrente et l'app le redirige vers l'écran
« Vérifie ta boîte mail » alors que son email a déjà été confirmé. Plusieurs fix
passés (`bug-auth-bounced-silent.md`, `bug-auth-flow.md`) ont introduit le flag
`forceUnconfirmed` sans traiter les causes racines.

## Diagnostic — 3 désynchronisations qui se renforcent

### #1 — JWT stale après confirmation email (backend)
`dependencies.py:213-244` : le backend lit `email_confirmed_at` **depuis le payload JWT**.
Supabase n'invalide pas le JWT lors de la confirmation d'email → un user fraîchement
confirmé continue de recevoir des 403 jusqu'à la rotation naturelle du JWT (~1h).

### #2 — Cache négatif 5 min (backend)
`dependencies.py:22-25` : `_EMAIL_CACHE_TTL_SECONDS = 300` cache **indifféremment**
les True et les False. Un False lu une fois gèle l'user en « non confirmé » pendant
5 min, même s'il confirme dans la seconde qui suit.

### #3 — Flag `forceUnconfirmed` sticky (mobile)
`auth_state.dart:596-634` : `refreshUser()` ne remet `forceUnconfirmed=false` que si
le **nouveau** JWT contient `email_confirmed_at`. Si le refresh échoue (réseau) ou
ramène encore un JWT stale, le flag persiste → redirection permanente vers
l'EmailConfirmationScreen. Le timer auto-refresh (6s) swallow silencieusement les
`AuthException`.

### Aggravants
- `providers.dart:22-25` : n'importe quel 403 (pas seulement `email_not_confirmed`) set le flag.
- `api_client.dart:89-96` : 403 ne tente aucun refresh+retry (contrairement au 401).
- `auth_state.dart:218-228` : dedup du listener ignore les updates si `sameUser && !emailStatusChanged`, même si `forceUnconfirmed==true` et l'update aurait pu le reset.
- `auth_state.dart:107-114` : timeout init 10s force `isLoading=false` brutalement.

## Plan de fix

### Backend
1. **Cache positif uniquement** : ne jamais cacher `confirmed=False`. Seul True est mis en cache.
2. **TTL réduit** : 60s au lieu de 300s (sur les positifs).
3. **Trust DB over JWT pour provider=email** : si l'email n'est pas marqué confirmé dans le JWT mais que le provider est `email`, faire systématiquement le fallback DB (déjà le cas, mais sans pollution du cache négatif).
4. **Nouveau endpoint `GET /auth/me/email-status`** : léger, sans cache négatif, utilisé par le mobile pour poll la confirmation sans dépendre de la rotation JWT.

### Mobile — `api_client.dart`
5. **Refresh-and-retry sur 403** : symétrique au 401. Sur 403, appeler `refreshSession()`, réessayer la requête. Ne propager `onAuthError(403)` que si le 2e appel retourne encore 403 **avec** un body `detail == "Email not confirmed"`.

### Mobile — `auth_state.dart`
6. **Reset `forceUnconfirmed` en init** : si le blocking refresh réussit et que le user est `isEmailConfirmed`, forcer `forceUnconfirmed=false`.
7. **Reset `forceUnconfirmed` sur app resume** : idem dans `didChangeAppLifecycleState`.
8. **Listener dedup** : ne pas court-circuiter si `state.forceUnconfirmed==true` — toujours processer pour permettre l'auto-recovery.
9. **`setForceUnconfirmed` défensif** : déclencher un `refreshSession()` asynchrone immédiat + check DB via le nouvel endpoint avant de verrouiller le flag.

### Mobile — `email_confirmation_screen.dart`
10. **Poll via endpoint DB** au lieu de `refreshUser()` seul : indépendant de la rotation JWT.

## Critères d'acceptation

- [ ] Un user qui vient de confirmer son email peut accéder à l'app **dans les 2 secondes** (pas 5 min).
- [ ] Relancer l'app après un kill ne redirige **jamais** vers l'écran de confirmation pour un user déjà confirmé.
- [ ] Un 403 transitoire (ex. réseau intermittent sur un endpoint non-auth) ne set plus `forceUnconfirmed`.
- [ ] Tests backend : le cache ne persiste plus les False.
- [ ] Tests mobile : la séquence `401 → refresh → retry → success` fonctionne aussi pour 403.
