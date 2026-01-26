# Plan d'implémentation : Fix echec API personnalisation (mute)

## Status: ACT - Implémentation terminée, en attente de test

## Contexte

- Le client Flutter echoue systematiquement sur `POST /api/users/personalization/*`.
- Le backend attend un `UUID` et persiste dans `user_personalization`.

## Hypotheses prioritaires (validees)

1. ✅ **Profil manquant** : pas de ligne dans `user_profiles` pour certains users (CORRIGE).
2. ⚠️ **FK non migree en prod** : a verifier en prod (migration `1a2b3c4d5e6f`).
3. ✅ **Erreur auth ou body** : logs ajoutes pour diagnostiquer.

## Actions realisees (ACT)

### 1) ✅ Mesurer et confirmer le code d'erreur
- ✅ Ajout de logs detailles dans `PersonalizationRepository` (DioException).
  - Status code HTTP, path, body envoye, response, type d'erreur.
- ⏳ Appel de test avec token valide (a faire apres deploy).

### 2) ⏳ Verifier l'etat de la FK en prod
- ⏳ Verifier la contrainte `user_personalization_user_id_fkey` dans Postgres.
- ⏳ Si la FK reference `user_profiles.id`, appliquer la migration `1a2b3c4d5e6f`.

### 3) ✅ Rendre l'endpoint tolerant
- ✅ Ajout de `get_or_create_profile()` avant chaque insertion.
  - Applique dans `mute_source`, `mute_theme`, `mute_topic`.
- ✅ Correction de `updated_at` : `func.now()` au lieu de `'now()'`.

### 4) ✅ QA / Verification
- ✅ Creation du script `docs/qa/scripts/verify_personalization_mute.sh`.
- ⏳ Verification UI (a faire apres deploy).

## Fichiers modifies

- `apps/mobile/lib/features/feed/repositories/personalization_repository.dart`
- `packages/api/app/routers/personalization.py`
- `docs/qa/scripts/verify_personalization_mute.sh` (nouveau)
- `docs/bugs/bug-personalization-api-failure.md` (mis a jour)

## Prochaines etapes

1. Deployer les changements en staging/prod.
2. Tester avec `./docs/qa/scripts/verify_personalization_mute.sh <TOKEN>`.
3. Verifier les logs client pour confirmer le code d'erreur exact.
4. Si FK incorrecte en prod, appliquer la migration `1a2b3c4d5e6f`.

---

# Plan d'implémentation : Fix healthcheck Railway (migrations Alembic)

## Status: EN COURS - Bypass migrations actif en prod

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

## État actuel en production

- API up avec bypass migrations : `FACTEUR_MIGRATION_IN_PROGRESS=1`
- `/api/health` → 200 (liveness OK)
- `/api/health/ready` → 200 (DB connectée)
- Migrations toujours bloquées sur `DROP CONSTRAINT` (lock concurrent)

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
# (railway run n'ouvre pas de shell distant, il injecte les vars locales)
railway run -- alembic upgrade head

# 4. Désactiver le bypass
railway variables unset FACTEUR_MIGRATION_IN_PROGRESS

# 5. Redéployer pour restaurer les checks
railway up
```

### Stratégie recommandée pour finaliser

1. Mettre en maintenance (scale à 0 ou fenêtre sans trafic).
2. Exécuter la migration avec `lock_timeout=0` (attendre le lock).
3. Vérifier que le head Alembic est correct.
4. Retirer le bypass `FACTEUR_MIGRATION_IN_PROGRESS`.
5. Redéployer et vérifier que le startup passe.

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
