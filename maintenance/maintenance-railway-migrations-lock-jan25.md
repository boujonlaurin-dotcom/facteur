# Maintenance : Migrations Alembic bloquées (lock FK user_personalization)

**Date** : 2026-01-25  
**Auteur** : BMAD Agent  
**Type** : Infra / Database  

---

## Contexte

Les déploiements Railway échouaient à cause d'une migration Alembic bloquée sur
`DROP CONSTRAINT` de `user_personalization`. Le pooler Supabase (PgBouncer) en
mode transaction ne respecte pas `SET LOCAL`, déclenchant `statement_timeout`.

## Diagnostic

- `DROP CONSTRAINT` nécessite un `ACCESS EXCLUSIVE lock`.
- En présence de trafic, le lock peut rester bloqué indéfiniment.
- `SET LOCAL statement_timeout` est perdu via PgBouncer.

## Actions réalisées

1. **Migration rendue safe et idempotente**
   - Ajout FK `NOT VALID`
   - Drop ancienne contrainte
   - Rename
   - Validate
   - Checks d'existence pour éviter `DuplicateObject`
   - Retry via `autocommit_block` + `lock_timeout` + `statement_timeout=0`

2. **Timeouts via options de connexion**
   - Passage des timeouts dans `options` côté Alembic pour contourner PgBouncer.

3. **Healthcheck dissocié**
   - `/api/health` → liveness (ne touche pas la DB)
   - `/api/health/ready` → readiness (check DB)

4. **Bypass migrations en prod**
   - Flag `FACTEUR_MIGRATION_IN_PROGRESS=1` pour éviter le crash au startup.

## État actuel (prod)

- API up, bypass migrations actif.
- `/api/health` → 200
- `/api/health/ready` → 200
- Migrations toujours bloquées sur lock concurrent.

## Stratégie recommandée pour finaliser

1. Mettre en maintenance (scale à 0 ou fenêtre sans trafic).
2. Exécuter la migration avec `lock_timeout=0` (attendre le lock).
3. Vérifier que le head Alembic est correct.
4. Retirer le bypass `FACTEUR_MIGRATION_IN_PROGRESS`.
5. Redéployer et vérifier le startup.

## Fichiers impactés

| Fichier | Rôle |
|---------|------|
| `packages/api/alembic/versions/1a2b3c4d5e6f_fix_user_personalization_fk.py` | Migration FK safe |
| `packages/api/alembic/env.py` | Timeouts via options |
| `packages/api/app/checks.py` | Bypass migrations |
| `packages/api/app/main.py` | Liveness / readiness |
| `packages/api/Dockerfile` | Skip migrations si bypass |
| `packages/api/requirements.txt` | Dépendances ML sorties |
| `packages/api/requirements-ml.txt` | Dépendances ML optionnelles |

## Vérification

```bash
curl -i https://facteur-production.up.railway.app/api/health
curl -i https://facteur-production.up.railway.app/api/health/ready
```
