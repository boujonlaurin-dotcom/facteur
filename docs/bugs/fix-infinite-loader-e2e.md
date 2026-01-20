# Bug Fix: Infinite Loader & 403 Forbidden - E2E

## Symptômes
1. **Infinite Loader** : L'app bloquait sur le splash screen.
2. **403 Forbidden** : Feed affichait une erreur pour les utilisateurs non confirmés.
3. **UX Login** : Pas de feedback explicite ni de moyen de renvoyer l'email.

## Causes Racines
- **Infrastructure** : Absence de timeouts sur init.
- **Logique** : Router permettait accès partiel ; Backend rejette (Normal).
- **UX** : Manque de gestion du cas "Email non confirmé" dans l'UI.

## Solutions Appliquées

### 1. Robustesse Système (Backend/Auth)
- **Timeouts** : Sur toutes les opérations critiques d'init.
- **Auto-Logout 403** : `ApiClient` intercepte désormais les 403/401 et force une déconnexion globale. C'est une sécurité ultime.

### 2. Guard & UX (Frontend)
- **Startup Check** : `AuthState` vérifie strictement `emailConfirmedAt`. Si non, déconnexion immédiate + Message d'erreur spécifique.
- **Login Screen** :
  - Affiche le message : "Veuillez confirmer votre email..."
  - **Bouton Ajouté** : "Renvoyer l'email de confirmation".

## Fichiers Modifiés
- `apps/mobile/lib/main.dart` (Timeouts)
- `apps/mobile/lib/core/auth/auth_state.dart` (Guard + Resend Logic)
- `apps/mobile/lib/core/api/api_client.dart` (Interceptor 403 -> AutoLogout)
- `apps/mobile/lib/core/api/providers.dart` (Wiring ApiClient -> AuthState)
- `apps/mobile/lib/features/auth/screens/login_screen.dart` (UI Button)

## Vérification Finale
1. **Compte Non Confirmé** :
   - Bloqué au Login (Message rouge).
   - Peut cliquer sur "Renvoyer l'email".
2. **Compte Confirmé** :
   - Accès Feed sans erreur.
3. **Session Expirée en cours** :
   - `ApiClient` détecte 403 -> Logout automatique -> Retour Login.

## Date
2026-01-20
