# Bug: Module personalization manquant en CI

## Status: InProgress

## Date: 24/01/2026

## Symptome

- Crash du conteneur au demarrage.
- Erreur `ModuleNotFoundError: No module named 'app.models.user_personalization'`.

## Cause probable

- Fichiers backend de personnalisation non versionnes (model/router/layer).

## Correctif cible

- Ajouter au repo les fichiers manquants et inclure le router `personalization` dans `app.routers`.

## Verification

- Lancer l'image Docker et verifier le demarrage (ou `/api/health`).
