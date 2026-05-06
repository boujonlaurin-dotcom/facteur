# Bug: Account creation — 3 régressions post-signup

**Status:** FIX EN COURS
**Severity:** HIGH (blocant pour nouveaux users)
**Date:** 2026-05-06
**Branche:** `boujonlaurin-dotcom/fix-email-confirm-onboarding`

---

## Symptômes utilisateur

À la création de compte Facteur :

1. **Lien email ne réouvre pas l'app** — clic sur "Confirmer mon email" → page Supabase (Site URL) ou écran blanc, l'app ne se relance pas.
2. **Bouton "J'ai confirmé mon email" inactif** — même après avoir cliqué le lien email côté serveur, le bouton dans l'app ne débloque rien. Seul `signOut()` + `signIn()` permet d'avancer.
3. **Onboarding démarre à la Section 3** ("Quels sont vos centres d'intérêt ?") au lieu de la Section 1 (Welcome / Mission / diagnostic).

---

## Root causes

### #1 — Custom scheme non déclenché par les clients mail

`signUpWithEmail()` passait `emailRedirectTo: 'io.supabase.facteur://login-callback'`. Les clients mail mobiles et certains browsers Android/iOS refusent d'invoquer un scheme custom non-HTTPS depuis un lien email (pas un Universal/App Link). Résultat : Supabase tombe sur la **Site URL** configurée dans le dashboard, qui n'a jamais été pointée vers une page utile.

### #2 — `refreshSession()` ne re-fetch pas le user record

Le bouton "J'ai confirmé mon email" appelait `SessionRefresher.refresh()` → `Supabase.auth.refreshSession()`. Ce dernier échange le refresh token contre un nouvel access token mais **ne re-lit pas le user record en DB**. Le user retourné conserve `emailConfirmedAt = null` même après que Supabase a flaggé l'email comme confirmé côté serveur.

### #3 — Bump forcé vers Section 3 + box `onboarding` non vidée au signOut

`auth_state.dart` définissait `_requiredOnboardingVersion = 3`. Pour tout user déjà onboardé avec une version stockée < 3, le code :
- forçait `needsOnboarding = true`
- pré-écrivait `section: 2, question: 0` dans la box Hive `onboarding` (Section 3 visuelle = `OnboardingSection.sourcePreferences` → index enum 2)

`signOut()` ne nettoyait pas la box `onboarding`. Conséquence : un nouveau signup sur un device qui avait déjà eu un user avec ce bump héritait de `section: 2, question: 0` via `OnboardingNotifier._loadSavedAnswers()`, démarrant directement à la 3ᵉ section.

---

## Fixes

| Bug | Fichier | Modification |
|---|---|---|
| #1 | `apps/mobile/lib/core/auth/auth_state.dart:signUpWithEmail` | Native redirige vers `https://boujonlaurin-dotcom.github.io/facteur/email-confirmation.html` (HTTPS) |
| #1 | `apps/mobile/web/email-confirmation.html` (NEW) | Page statique : tente l'ouverture du scheme `io.supabase.facteur://login-callback` + boutons fallback |
| #2 | `apps/mobile/lib/core/auth/auth_state.dart:refreshUser` | Utilise `_supabase.auth.getUser()` (GET /auth/v1/user — fresh DB) puis `SessionRefresher.refresh()` si confirmé |
| #3 | `apps/mobile/lib/core/auth/auth_state.dart` | Suppression de `_requiredOnboardingVersion` + bloc de bump dans `_checkOnboardingStatus` ; nettoyage des `onboarding_app_version` dans `setOnboardingCompleted` / `setNeedsOnboarding` |
| #3 | `apps/mobile/lib/core/auth/auth_state.dart:signOut` | Clear de la box Hive `onboarding` |

Aucun changement backend (`packages/api/`). Aucune migration Alembic.

---

## Étapes manuelles Supabase Dashboard (post-merge)

[Auth → URL Configuration](https://supabase.com/dashboard/project/ykuadtelnzavrqzbfdve/auth/url-configuration) :

- **Site URL** : `https://boujonlaurin-dotcom.github.io/facteur/email-confirmation.html`
- **Redirect URLs** (whitelist, ajouter si manquant) :
  - `https://boujonlaurin-dotcom.github.io/facteur/email-confirmation.html`
  - `https://boujonlaurin-dotcom.github.io/facteur/email-confirmation.html#*`
  - `io.supabase.facteur://login-callback` (conservé pour anciens tokens en vol)

Vérifier le template "Confirm signup" : `{{ .ConfirmationURL }}` doit être utilisé tel quel — Supabase y injecte automatiquement le `redirect_to` passé par le client mobile.

---

## Tests manuels

| # | Scénario | Attendu |
|---|---|---|
| #3 | Créer un compte neuf → confirmer email → atterrissage onboarding | Démarre sur **WelcomeScreen** (Section 1, intro1), pas sur ThemesQuestion |
| #3 bis | Se reconnecter avec un user déjà onboardé | Atterrissage direct sur `/feed`, jamais sur `/onboarding` |
| #2 | Signup → ne pas cliquer le lien email → cliquer "J'ai confirmé" | Pas de bypass (user reste sur l'écran de confirmation) |
| #2 bis | Cliquer le lien email → revenir dans l'app → cliquer "J'ai confirmé" | Router redirige vers `/onboarding` sans signOut/signIn |
| #1 | Ouvrir l'email sur Android (app installée) → click "Confirmer mon email" | App s'ouvre |
| #1 bis | Désinstaller l'app → click le lien | Page web `email-confirmation.html` s'affiche, bouton "Ouvrir dans l'app" fonctionne |

---

## Tests automatisés

- `cd apps/mobile && flutter test` — suite passe
- `cd apps/mobile && flutter analyze` — zéro warning
