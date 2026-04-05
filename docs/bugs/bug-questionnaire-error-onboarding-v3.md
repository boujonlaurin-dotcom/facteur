# Bug: Erreur en fin de questionnaire (onboarding v3 re-trigger)

## Statut : 🔧 En cours de fix

## Symptôme

Les utilisateurs voient "Oups, un problème est survenu / Impossible de sauvegarder ton profil" à la fin du questionnaire d'onboarding. Le problème est **très fréquent**.

## Cause racine

### Bug principal : champs requis null lors du re-onboarding Section 3

Quand un utilisateur existant (onboarding version < 3) rouvre l'app :

1. `auth_state.dart:348-359` détecte la version obsolète → redirige vers Section 3 only
2. Les réponses Sections 1/2 ont été effacées par `clearSavedData()` après le 1er onboarding
3. L'utilisateur complète Section 3 et soumet
4. `_formatAnswersForApi()` envoie `objective: null`, `approach: null`, `response_style: null`
5. Backend Pydantic rejette avec **422** (champs requis non-nullable)
6. Le mobile ne retente pas les erreurs de validation → écran d'erreur immédiat

### Bug secondaire : `daily_article_count` vs `weekly_goal`

- `user_api_service.dart:89` envoie `daily_article_count`
- `schemas/user.py:81` attend `weekly_goal`
- Le champ est silencieusement ignoré → le choix utilisateur (3/5/7) est perdu, toujours 5

## Fichiers impactés

| Fichier | Modification |
|---------|-------------|
| `packages/api/app/schemas/user.py` | Rendre `objective`, `approach`, `response_style` optionnels |
| `packages/api/app/services/user_service.py` | Conserver les valeurs existantes pour champs absents |
| `apps/mobile/lib/core/api/user_api_service.dart` | Filtrer null + fix `daily_article_count` → `weekly_goal` |

## Scénario de reproduction

1. Avoir un compte avec onboarding complété en version < 3
2. Mettre à jour l'app (version avec `_requiredOnboardingVersion = 3`)
3. Ouvrir l'app → redirigé vers Section 3
4. Compléter Section 3 → "Créer mon essentiel"
5. **Résultat** : erreur 422, écran "Oups, un problème est survenu"

## Fix appliqué

- Backend : champs Section 1/2 optionnels avec defaults, service conserve les valeurs existantes
- Mobile : filtrage des null dans le payload, correction du nom de champ `weekly_goal`
