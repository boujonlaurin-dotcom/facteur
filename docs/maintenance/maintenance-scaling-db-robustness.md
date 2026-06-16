# Maintenance — Robustesse DB (scaling phase 2, PR-S1 + hygiène G5)

## Contexte
Phase 2 scaling (cf. `docs/scaling/scaling-investigation-200-users.md`). Signal prod : `IdleInTransactionSessionTimeout` (Sentry) + sessions tuées par le `zombie_session_sweeper`. Le sweeper est un pansement ; cette PR corrige la cause racine et traite l'hygiène stockage connue du baseline.

## Cause racine identifiée (G1)
`classification_worker._process_batch()` (app/workers/classification_worker.py:174-368) : après le commit de `dequeue_batch`, les `session.get(Content/Source)` ouvrent une **nouvelle transaction qui reste idle pendant 90-180 s d'appels Mistral séquentiels** (classif batch + retries individuels + entités + good-news pass). Le timeout serveur `idle_in_transaction_session_timeout=60s` tue la session → écritures de résultats en échec, retries, et bruit sweeper/Sentry.

## Changements
1. **Worker classification** : `_process_batch` restructuré en 3 phases — session courte (dequeue + chargement batché des contents/sources, snapshot en dicts), appels Mistral **hors session**, session courte d'écriture des résultats. Bonus : suppression du N+1 (`session.get` par item → 2 `SELECT ... WHERE id IN`).
2. **DROP `ix_user_content_status_exclusion`** : index 5 colonnes jamais utilisé par le planner (EXPLAIN baseline 2026-06-04 §3) ; coût write-amplification sur chaque interaction. Migration idempotente (`IF EXISTS`), non destructive pour l'ancien code prod (un index en moins ne casse aucune requête). Retiré du modèle `Content`/`UserContentStatus`.
3. **Purge `classification_queue`** : les lignes `completed`/`failed` s'accumulent (26 MB d'index au baseline). Purge des lignes terminées depuis > 30 jours, ajoutée au job `storage_cleanup` (03:00 Paris). 30 j ≫ la fenêtre de requeue 48 h de `requeue_for_reclassification`.

## Hors périmètre
Right-size du pool (attendre les données de la sonde phase A) ; mode pooler transaction ; découplage worker (S2).

## Tests
- [ ] Unitaires worker : session fermée pendant les appels LLM (assertion sur le session_maker), résultats écrits, retries préservés.
- [ ] Migration : 1 head, upgrade/downgrade DB vide, idempotence.
- [ ] Purge : supprime les vieilles lignes terminées, préserve pending/processing et les récentes.
- [ ] `pytest -v` complet.

## Acceptation post-deploy
Zéro `IdleInTransactionSessionTimeout` lié au worker sur 48 h ; `zombie_session_sweeper_killed` silencieux ; taille `classification_queue` en baisse après le premier cleanup.
