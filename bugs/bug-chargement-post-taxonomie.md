# Bug: Chargement Infini au Lancement après Taxonomy Update

**Date**: 2026-01-20
**Statut**: Résolu
**Impact**: Critique (App inutilisable) - FIXÉ

## Résolution Finale
Le problème venait bien de migrations manquantes (`k8l9m0n1o2p3` vs `a4b5c6d7e8f9`).
La commande `alembic upgrade head` a résolu le problème.
Le script `docs/qa/scripts/verify_taxonomie_e2e.sh` a validé le fix.

## Symptôme
L'application mobile affiche un chargement infini au lancement. Le backend démarre sans erreur apparente, mais les requêtes semblent bloquer ou timeout.

## Diagnostic
1. **Backend Health**: `uvicorn` démarre sur le port 8001. `/api/health` n'a pas été testé mais le process est UP.
2. **Migrations**:
   - Local revisions: `a4b5c6d7e8f9` (Head)
   - DB revisions: `k8l9m0n1o2p3` (Current)
   - **Verdict**: La base de données est en retard d'au moins une migration.

## Cause Racine
Les migrations introduites par les stories Taxonomie (2a, 2b, 2c) n'ont pas été appliquées sur la base de données.
Le code backend tente probablement d'accéder à des colonnes inexistantes (`Content.topics`, `UserSubtopic` ou `Source.theme` normalisé), ce qui provoque des erreurs SQL ou des blocages transactionnels silencieux (ou non loggés par défaut).

## Résolution
Appliquer les migrations manquantes via `alembic upgrade head`.
