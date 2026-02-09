# Analyse du problème de connexion - Facteur

## Date: 2026-02-09
## Branche: fix/auth-login-failure

---

## Problème rapporté

La connexion à l'application ne fonctionne plus sur :
- Navigateur (boujonlaurin-dotcom.github.io)
- Application Android

Mais fonctionne en local lors des tests (Chrome sur Mac, lancé via VSCode).

---

## Analyse des causes

### 1. Fuite d'informations sensibles (CRITIQUE - CORRIGÉ)

**Problème:** Le message d'erreur affichait l'URL Supabase complète avec le project_ref.

**Localisation:** `apps/mobile/lib/features/auth/screens/login_screen.dart`, lignes 346-355

**Impact:** Exposition publique de l'infrastructure backend, potentiellement exploitable.

**Correction:** Suppression du bloc de code DEBUG qui affichait `SupabaseConstants.url`.

---

### 2. Erreurs trop génériques masquant le vrai problème

**Problème:** La fonction `AuthErrorMessages.translate()` capturait TOUTES les erreurs contenant les mots "session", "token" ou "expired" et les traduisait par "Ta session a expiré", masquant ainsi les vraies erreurs de configuration.

**Localisation:** `apps/mobile/lib/features/auth/utils/auth_error_messages.dart`, lignes 113-117

**Impact:** Impossible de distinguer une erreur de configuration (clés Supabase manquantes/malformées) d'une vraie session expirée.

**Correction:**
- Ajout de catégories d'erreurs plus spécifiques (400, 401, 403)
- Messages plus précis pour les erreurs de session (session_not_found, jwt_expired, etc.)
- Messages distincts pour les erreurs de configuration

---

### 3. Absence de gestion des erreurs de parsing

**Problème:** Si les secrets GitHub `SUPABASE_URL` ou `SUPABASE_ANON_KEY` sont vides ou mal formatés, le client Supabase pourrait générer des `FormatException` non capturées.

**Correction:** Ajout d'un bloc `on FormatException catch` dans `auth_state.dart` pour détecter ces erreurs et afficher un message approprié.

---

## Hypothèse principale: Secrets GitHub manquants

**Cause la plus probable:** Les secrets GitHub `SUPABASE_URL` et `SUPABASE_ANON_KEY` ne sont pas correctement configurés ou sont vides.

**Vérification requise:**
1. Aller dans GitHub → Settings → Secrets and variables → Actions
2. Vérifier que les secrets suivants existent et sont correctement remplis:
   - `SUPABASE_URL` (ex: `https://ykuadtelnzavrqzbfdve.supabase.co`)
   - `SUPABASE_ANON_KEY` (clé publique de Supabase)
   - `REVENUECAT_IOS_KEY` (pour les paiements iOS)

**Comment vérifier:**
- Ouvrir les DevTools du navigateur sur la version déployée
- Vérifier dans la console si l'erreur est une `FormatException` ou une erreur réseau
- Si l'erreur est "Erreur de configuration", cela confirme que les secrets sont manquants

---

## Changements effectués

### 1. `apps/mobile/lib/features/auth/screens/login_screen.dart`
- **Supprimé:** Bloc DEBUG affichant `SupabaseConstants.url`

### 2. `apps/mobile/lib/features/auth/utils/auth_error_messages.dart`
- **Ajouté:** Gestion des erreurs HTTP 400, 401, 403
- **Amélioré:** Messages d'erreur de session plus spécifiques
- **Ajouté:** Messages distincts pour les erreurs de configuration

### 3. `apps/mobile/lib/core/auth/auth_state.dart`
- **Ajouté:** Capture `FormatException` dans `signInWithEmail()`
- **Amélioré:** Messages d'erreur plus informatifs

---

## Prochaines étapes recommandées

1. **Vérifier les secrets GitHub** (priorité CRITIQUE)
   - Se connecter à GitHub
   - Vérifier Settings → Secrets and variables → Actions
   - Confirmer que SUPABASE_URL et SUPABASE_ANON_KEY sont définis

2. **Tester après correction des secrets**
   - Redéployer l'application
   - Tester la connexion

3. **Monitoring**
   - Vérifier les logs Sentry pour les erreurs de connexion
   - Surveiller les taux d'échec de connexion

---

## Références

- GitHub Actions workflow: `.github/workflows/build-web.yml`
- Configuration des constantes: `apps/mobile/lib/config/constants.dart`
- Écran de login: `apps/mobile/lib/features/auth/screens/login_screen.dart`
