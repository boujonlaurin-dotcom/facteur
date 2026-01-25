# Plan d'implémentation : Fix healthcheck Railway (migrations Alembic)

## Status: IMPLÉMENTÉ - En attente de déploiement

## Diagnostic Systémique (25 janvier 2026)

### Problèmes racines identifiés

1. **`SET LOCAL statement_timeout` + PgBouncer = incompatible**
   - Le pooler Supabase (PgBouncer transaction mode) ne préserve pas les `SET LOCAL`
   - Le timeout Supabase (~60s) s'applique malgré les 5min configurées

2. **`DROP CONSTRAINT` prend un ACCESS EXCLUSIVE lock**
   - Bloque toutes les opérations sur la table
   - Avec du trafic concurrent, peut rester bloqué indéfiniment

3. **Boucle de mort startup/migrations**
   - check_migrations → crash → restart → migrations timeout → crash

## Solution Implémentée (4 axes)

### AXE 1 : Migration SAFE (non-bloquante) ✅
**Fichier**: `packages/api/alembic/versions/1a2b3c4d5e6f_fix_user_personalization_fk.py`

Pattern PostgreSQL sécurisé :
1. `ADD CONSTRAINT ... NOT VALID` (instantané, pas de scan)
2. `DROP CONSTRAINT` (rapide car nouvelle FK protège déjà)
3. `RENAME CONSTRAINT` (instantané)
4. `VALIDATE CONSTRAINT` (SHARE UPDATE EXCLUSIVE lock, non-bloquant)

### AXE 2 : Timeout via options de connexion ✅
**Fichier**: `packages/api/alembic/env.py`

Passage des timeouts via `-c options` au lieu de `SET LOCAL` :
```python
"options": "-c statement_timeout=600000 -c lock_timeout=120000"
```
Ces options sont passées au serveur PostgreSQL à la connexion, contournant PgBouncer.

### AXE 3 : Flag de bypass migrations ✅
**Fichier**: `packages/api/app/checks.py`

Variable d'environnement `FACTEUR_MIGRATION_IN_PROGRESS=1` :
- Permet à l'app de démarrer pendant que les migrations sont appliquées
- Usage temporaire uniquement

### AXE 4 : Healthcheck liveness/readiness séparés ✅
**Fichier**: `packages/api/app/main.py`

- `/api/health` → Liveness (Railway) : retourne 200 si l'app tourne
- `/api/health/ready` → Readiness : vérifie la DB, retourne 503 si pas prête

## Procédure de Déploiement

### Option A : Déploiement normal (recommandé)
```bash
git add -A && git commit -m "fix(migrations): safe FK migration + PgBouncer timeout bypass"
git push origin main
# Railway redéploie automatiquement
```

### Option B : Si migrations bloquent encore
```bash
# 1. Activer le bypass
railway variables set FACTEUR_MIGRATION_IN_PROGRESS=1

# 2. Redéployer (l'app démarre sans check migrations)
railway up

# 3. Appliquer les migrations manuellement
railway run -- alembic upgrade head

# 4. Désactiver le bypass
railway variables unset FACTEUR_MIGRATION_IN_PROGRESS

# 5. Redéployer pour restaurer les checks
railway up
```

## Vérification

```bash
./docs/qa/scripts/verify_railway_deployment.sh
```

Ou manuellement :
```bash
# Liveness (doit retourner 200)
curl -i https://facteur-production.up.railway.app/api/health

# Readiness (200 si DB OK, 503 sinon)
curl -i https://facteur-production.up.railway.app/api/health/ready
```

## Fichiers modifiés

| Fichier | Modification |
|---------|--------------|
| `packages/api/alembic/versions/1a2b3c4d5e6f_fix_user_personalization_fk.py` | Migration SAFE avec NOT VALID |
| `packages/api/alembic/env.py` | Timeout via options de connexion |
| `packages/api/app/checks.py` | Flag FACTEUR_MIGRATION_IN_PROGRESS |
| `packages/api/app/main.py` | Séparation liveness/readiness |
| `docs/qa/scripts/verify_railway_deployment.sh` | Script de vérification |

## Rollback

Si problème :
```bash
git revert HEAD
git push origin main
```
