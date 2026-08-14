# Bug : Sign in with Apple impossible — « provider is not enabled »

**Status :** Code CORRIGÉ / Configuration Supabase **À FAIRE** (action manuelle, hors dépôt)
**Sévérité :** CRITICAL — bloque inscription **et** connexion des utilisateurs iOS
**Signalé :** 13/08/2026 (capture d'écran utilisateur)
**Créé :** 14/08/2026

---

## 1. Symptôme

Un utilisateur iOS tape « Se connecter avec Apple » depuis l'écran de login.
Au lieu de la feuille système Apple, Safari s'ouvre en vue modale sur
`ykuadtelnzavrqzbfdve.supabase.co` et affiche du JSON brut :

```json
{"code":400,"error_code":"validation_failed","msg":"Unsupported provider: provider is not enabled"}
```

L'utilisateur ferme la vue et retombe sur l'écran de login. **Aucun message
d'erreur dans l'app, aucune trace dans Sentry ni PostHog.**

## 2. Analyse

Quatre défauts distincts se cumulent. Le premier est bloquant à lui seul ; les
trois autres expliquent pourquoi il est resté invisible aussi longtemps et
pourquoi le rétablir ne suffirait pas.

### 2.1 — Cause racine : le provider Apple n'est pas activé côté Supabase

`msg: "Unsupported provider: provider is not enabled"` est la réponse de GoTrue
quand `EXTERNAL_APPLE_ENABLED=false`. Le provider Apple n'a jamais été activé
sur le projet `ykuadtelnzavrqzbfdve`. Le bouton était donc câblé sur un endpoint
qui ne pouvait que répondre 400.

> ⚠️ **Cette partie ne se corrige pas dans le dépôt.** Elle demande une action
> dans le dashboard Supabase et dans le compte Apple Developer — voir §4.

### 2.2 — Le flux passait par le navigateur au lieu de la feuille native

`auth_state.dart` appelait `signInWithOAuth(OAuthProvider.apple)`, qui ouvre
`https://<projet>.supabase.co/auth/v1/authorize?provider=apple` dans un
navigateur externe. Conséquences :

- **toute erreur GoTrue s'affiche hors de l'app**, en JSON, non traduisible et
  non catchable — c'est exactement la capture reçue ;
- Apple attend la feuille native sur iOS (HIG *Sign in with Apple*) ;
- le flux navigateur exige la configuration **web** complète (Services ID +
  clé secrète .p8 + redirect URL), là où le flux natif ne demande que le
  **Bundle ID en client ID autorisé**.

### 2.3 — L'état de chargement ne redescendait jamais

`signInWithOAuth` rend la main dès le navigateur lancé. Le code posait
`isLoading: true` et ne le remettait **jamais** à `false` sur ce chemin. Au
retour de Safari — erreur *ou* simple annulation — `authState.isLoading` restait
`true`, donc les boutons Apple **et Google** restaient désactivés jusqu'au
prochain lancement de l'app. Un utilisateur qui annulait par erreur se
retrouvait sans aucun login social possible.

### 2.4 — Aucune instrumentation

L'échec se produisant dans le navigateur, ni Sentry ni PostHog n'en voyaient la
trace. Le bug n'a été détecté que parce qu'un utilisateur a envoyé une capture
d'écran.

### 2.5 — Bonus : la cible de redirection web n'existait pas

Le flux Apple visait `Uri.base.resolve('auth/callback')`. Aucune route
`/auth/callback` n'est déclarée dans `apps/mobile/lib/config/routes.dart` : même
avec le provider activé, le retour web aurait atterri sur une route morte.
Google, lui, visait correctement la page courante.

## 3. Correctifs livrés (code)

| # | Correctif | Fichier |
|---|-----------|---------|
| 1 | Flux **natif** Sign in with Apple sur iOS/macOS (`sign_in_with_apple` + `signInWithIdToken`), avec nonce brut/SHA-256 | `lib/core/auth/apple_sign_in.dart` (nouveau), `lib/core/auth/auth_state.dart` |
| 2 | `isLoading` relâché sur **tous** les chemins : succès, annulation, erreur Apple, erreur Supabase | `lib/core/auth/auth_state.dart` |
| 3 | Annulation utilisateur traitée comme un non-événement (pas de message d'erreur rouge) | `lib/core/auth/auth_state.dart` |
| 4 | Échecs de login social remontés dans Sentry **et** PostHog (`social_sign_in_failed`, tags `auth_provider` / `auth_stage`) | `lib/core/auth/auth_state.dart` |
| 5 | Messages français dédiés : provider désactivé, nonce rejeté, client ID non autorisé, annulation | `lib/features/auth/utils/auth_error_messages.dart` |
| 6 | Nom Apple (`first_name` / `last_name` / `full_name`) persisté dès la **première** autorisation — Apple ne le renvoie jamais ensuite | `lib/core/auth/auth_state.dart` |
| 7 | Redirection web unifiée avec Google (page courante, plus de `/auth/callback` mort) | `lib/core/auth/auth_state.dart` |
| 8 | Visibilité du bouton alignée sur la capacité réelle (`AuthStateNotifier.supportsNativeAppleSignIn`), macOS inclus | `lib/features/auth/screens/login_screen.dart` |

Après ces correctifs, si la configuration §4 n'est pas encore faite,
l'utilisateur voit **dans l'app** :

> Cette méthode de connexion est momentanément indisponible. Utilise ton email
> et ton mot de passe en attendant.

…et l'échec apparaît dans Sentry. Plus jamais de JSON dans Safari.

## 4. Configuration restante — À FAIRE (hors dépôt)

> Sans cette étape, le bouton Apple continue d'échouer — proprement, mais il
> échoue. Le flux natif iOS ne demande que les étapes 4.1 et 4.2.

### 4.1 — Apple Developer (portail développeur)

1. **Certificates, Identifiers & Profiles → Identifiers → App IDs** : ouvrir
   l'App ID `app.facteur` et cocher la capability **Sign in with Apple**.
   L'entitlement correspondant est déjà dans le dépôt
   (`ios/Runner/Runner.entitlements` → `com.apple.developer.applesignin`).
2. Régénérer le provisioning profile après activation de la capability
   (sinon la signature échoue au build).

### 4.2 — Supabase : provider Apple, flux natif iOS

Dashboard → **Authentication → Providers → Apple** :

1. Basculer **Enable Sign in with Apple** sur `ON`. ← *c'est le commutateur qui
   manquait et qui produisait le 400.*
2. **Authorized Client IDs** : ajouter le Bundle ID iOS **`app.facteur`**.
   C'est la seule valeur nécessaire au flux natif ; GoTrue vérifie que
   l'audience du JWT Apple correspond.

À ce stade, le login Apple **iOS** fonctionne. Rien d'autre n'est requis.

### 4.3 — (Optionnel) Apple sur le web

Le bouton reste affiché sur le build web, où le flux natif n'existe pas et
retombe sur OAuth par redirection. Pour que **ce** chemin fonctionne :

1. Apple Developer → **Identifiers → Services IDs** : créer un Services ID
   (ex. `app.facteur.web`), y activer Sign in with Apple, et déclarer :
   - *Domains* : le domaine du build web ;
   - *Return URLs* : `https://ykuadtelnzavrqzbfdve.supabase.co/auth/v1/callback`.
2. Apple Developer → **Keys** : créer une clé **Sign in with Apple** (.p8),
   noter Key ID et Team ID. **La clé n'est téléchargeable qu'une fois.**
3. Supabase → Providers → Apple : renseigner *Services ID*, *Team ID*, *Key ID*
   et le contenu du .p8 (« Secret Key »).

Tant que 4.3 n'est pas fait, le web affiche le message d'indisponibilité de §3
— comportement dégradé, mais propre. Si l'équipe préfère ne rien montrer sur le
web, retirer `kIsWeb ||` de la condition d'affichage dans `login_screen.dart`.

> 🔐 Ni la clé .p8, ni le Team ID, ni le Key ID ne doivent entrer dans le dépôt
> (GitGuardian tourne en CI). Ils vivent uniquement dans le dashboard Supabase.

## 5. Vérification

### Automatisée (dans la PR)

```bash
cd apps/mobile && flutter test test/features/auth/
cd apps/mobile && flutter analyze
```

Couvre : nonce (longueur, alphabet, unicité, SHA-256 conforme au vecteur de
référence), envoi du nonce **brut** à Supabase et du **hash** à Apple,
non-ouverture du navigateur sur iOS, persistance du nom Apple sans écrasement,
tolérance à l'échec de persistance, annulation, provider désactivé, traduction
des messages.

### Manuelle (après la configuration §4) — non exécutable en CI

Sign in with Apple ne fonctionne que sur un appareil/simulateur Apple signé avec
un compte iCloud : ces étapes demandent un Mac.

1. **Inscription** — appareil iOS avec un Apple ID *jamais* utilisé sur
   `app.facteur` : bouton Apple → feuille native → « Continuer » → l'app atteint
   l'onboarding. Vérifier dans Supabase → Authentication → Users que le compte
   existe avec provider `apple` et que `first_name` / `last_name` sont peuplés.
2. **Reconnexion** — se déconnecter, re-taper le bouton : la feuille native ne
   redemande ni nom ni email, et la session revient sur le **même** `user.id`.
3. **Masquer mon email** — refaire (1) avec un autre Apple ID en choisissant
   « Masquer mon adresse e-mail » : l'adresse `@privaterelay.appleid.com` doit
   être acceptée.
4. **Annulation** — ouvrir la feuille puis la fermer : aucun message rouge, et
   les boutons Apple **et** Google redeviennent immédiatement cliquables
   (c'était le blocage §2.3).
5. **Panne de config** — désactiver temporairement le provider dans Supabase :
   message français dans l'app, aucun navigateur ouvert, et un événement
   `social_sign_in_failed` (tag `auth_stage=supabase`) visible dans Sentry.

## 6. Suivi

- Alerter sur `social_sign_in_failed` dans Sentry : une régression de config
  redevient visible en minutes au lieu d'attendre une capture d'écran.
- La suppression de compte Apple (Guideline 5.1.1(v)) est déjà couverte par
  `account_screen.dart` + la PR backend B1.
