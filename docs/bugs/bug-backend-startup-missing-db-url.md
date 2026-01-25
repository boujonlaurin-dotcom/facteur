# Bug: Backend ne demarre pas sans DATABASE_URL

## Status: InProgress

## Date: 24/01/2026

## Symptome

- Le conteneur Railway crash au demarrage.
- Trace uvicorn sans message d'erreur explicite.

## Cause probable

- Variable `DATABASE_URL` absente en environnement production.
- Le validateur de config refuse un fallback localhost en production.

## Correctif

- Ajouter un guard explicite qui echoue avec un message clair si `DATABASE_URL` est manquante.

## Action requise infra

- Renseigner `DATABASE_URL` dans Railway (service API) ou connecter la base.

## Verification

- Lancer un deploy Railway avec `DATABASE_URL` defini et verifier `/api/health`.
