# Plan d'implémentation : Fix healthcheck Railway (migrations Alembic)

## Status: En cours d'execution

## Problème identifié

Les deploiements Railway du service `facteur` echouent sur le healthcheck (`/api/health`) car `alembic upgrade head` plante au startup:
- Logs: `Can't locate revision identified by 'a8da35e3c12b'`.
- Le conteneur s'arrete avant le demarrage de l'API.

## Analyse (Measure & Analyze)

- Deploiement `1b7a7100-c4e2-4bcb-b67d-9ae7b344fe20` (commit `6e68ee2`) en FAILED.
- Logs Railway: revision Alembic `a8da35e3c12b` absente du code.
- Repository local: migrations `a8da35e3c12b`, `f7e8a9b0c1d2`, `b7d6e5f4c3a2`, `1a2b3c4d5e6f` non versionnees (git status).
- Healthcheck actuel: `curl -i https://facteur-production.up.railway.app/api/health` retourne 200 (mais `environment=development`).
- Nouveau echec de build: `pip install` timeout sur `torch` (download tres volumineux).
- Nouveau echec de demarrage CI/railway: `DATABASE_URL` absent -> `alembic upgrade head` plante.
- Nouveau echec de demarrage prod: timeout de pool DB pendant `alembic upgrade head` (pooler Supabase).

## Decision (Decide)

Fix minimal et sure: versionner les migrations Alembic manquantes pour que `alembic upgrade head` puisse s'executer et que l'API demarre.

## Plan d'action (Act)

1. Ajouter les migrations manquantes dans Git:
   - `packages/api/alembic/versions/a8da35e3c12b_merge_heads.py`
   - `packages/api/alembic/versions/f7e8a9b0c1d2_add_user_personalization_table.py`
   - `packages/api/alembic/versions/b7d6e5f4c3a2_add_daily_top3_unique_constraint.py`
   - `packages/api/alembic/versions/1a2b3c4d5e6f_fix_user_personalization_fk.py`
2. Push sur `main` pour declencher le redeploy.
3. Sur Railway, verifier que `alembic upgrade head` passe au startup.
4. Verifier le healthcheck en prod.
5. Ajouter un script de verification `docs/qa/scripts/verify_railway_healthcheck_migrations.sh`.
6. Stabiliser le build Docker avec un timeout/retries plus permissifs pour `pip install`.
7. Skipper les migrations si `DATABASE_URL` est absent (build container).
8. Ajouter un retry plus long sur les migrations pour absorber les timeouts DB transitoires.
9. Utiliser le host DB direct Supabase pour les migrations quand `SUPABASE_URL` est present.

## Risques / Rollback

- Risque faible: ajout de fichiers de migration existants (pas de changement de schema en dehors de `upgrade head` deja attendu).
- Rollback: revert du commit si un comportement inattendu apparait en prod.

## Verification (One-liner)

```bash
./docs/qa/scripts/verify_railway_healthcheck_migrations.sh
```

## Validation requise

GO recu, passage en phase ACT.
