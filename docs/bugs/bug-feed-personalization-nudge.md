# Bug: Personalization nudge manquant en CI

## Status: InProgress

## Date: 24/01/2026

## Symptome

- Build CI echoue avec "PersonalizationNudge isn't defined".

## Cause probable

- Fichiers utilises par le feed non versionnes (widget nudge + provider).

## Impact

- APK non generable en CI.
- Boucles d'iterations longues (15 min) pour une erreur triviale.

## Correctif cible

- Ajouter les fichiers manquants au repo.
- Verifier les imports et la resolution des symboles dans le feed.

## Verification

- Lancer le script `docs/qa/scripts/verify_feed_personalization_nudge.sh`.
