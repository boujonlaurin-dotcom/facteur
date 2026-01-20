# Plan de Test : Flux d'Authentification & Validation Email

Ce document détaille les tests nécessaires pour valider le nouveau workflow de sécurité lié à l'inscription et la validation des emails.

## 1. Tests Unitaires & Intégration (Backend)

| Cas de Test | Procédure | Résultat Attendu |
|-------------|-----------|------------------|
| **JWT Validé** | Appeler un endpoint protégé avec un JWT ayant `email_confirmed_at` | Succès (200 OK) |
| **JWT Non Validé** | Appeler un endpoint protégé avec un JWT ayant `email_confirmed_at: null` | Erreur 403 (Email not confirmed) |
| **Social Login** | Appeler avec un JWT ayant `provider: google` et `email_confirmed_at: null` | Succès (200 OK) |

**Outil** : `packages/api/scripts/verify_auth_validation.py`

## 2. Tests Unitaires (Mobile)

| Cas de Test | Procédure | Résultat Attendu |
|-------------|-----------|------------------|
| **Statut isEmailConfirmed** | Vérifier la logique du getter avec différents profils (email vs social) | Retourne true uniquement si confirmé ou social |
| **Traductions Erreurs** | Vérifier que `AuthErrorMessages.translate` retourne les bons wordings | Wordings français corrects |

## 3. Tests Manuels (E2E)

### Scénario A : Inscription Email Standard
1. Cliquer sur "S'inscrire".
2. Saisir un email et un mot de passe.
3. **Résultat** : Redirection automatique vers l'écran "Vérifie ta boîte mail !".
4. Tenter de revenir en arrière ou de relancer l'app.
5. **Résultat** : Toujours bloqué sur l'écran de confirmation.

### Scénario B : Validation Effectuée
1. (Sur l'écran de confirmation) Cliquer sur le lien reçu par email (via un autre appareil ou simulateur).
2. Cliquer sur "J'ai confirmé mon email" dans l'app.
3. **Résultat** : Redirection vers l'Onboarding ou le Feed.

### Scénario C : Connexion Compte Non Validé
1. Se déconnecter.
2. Se connecter avec les identifiants d'un compte non validé.
3. **Résultat** : Redirection immédiate vers l'écran de confirmation.

### Scénario D : Connexion Sociale
1. Cliquer sur "Sign in with Google/Apple".
2. Effectuer la connexion.
3. **Résultat** : Accès direct à l'app (pas d'écran de confirmation email).

## 4. Tests d'Erreur (Edge Cases)
- **Lien expiré** : Tenter de valider avec un vieux lien Supabase -> Vérifier le toast d'erreur traduit.
- **Renvoyer l'email** : Cliquer sur "Renvoyer l'email" -> Vérifier le feedback visuel et la réception d'un nouvel email.
- **Déconnexion** : Cliquer sur "Se déconnecter" depuis l'écran de confirmation -> Doit ramener à l'écran de Login.
