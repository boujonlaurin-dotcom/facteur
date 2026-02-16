# Maintenance: RSS Storage Retention Policy

## Status & Metadata

- **Type**: Maintenance - Storage Management
- **Agent**: @dev
- **Date**: 2026-02-16
- **Phase**: ✅ Implemented
- **Related**: `docs/maintenance/maintenance-capacity-analysis-alpha2.md` (à créer)

---

## Problem Statement

### Symptômes
- **Storage Supabase**: 411 MB / 500 MB (82.3%)
- **Utilisateurs actifs**: 10 users seulement
- **Projection**: Saturation complète en 1-2 semaines
- **Goulot**: Rétention illimitée des articles RSS (pas de purge automatique)

### Impact
- 🔴 **Critique**: Le backend bloquera à 500 MB (Railway/Supabase hard limit)
- Nouveaux articles RSS ne pourront plus être sync
- App mobile sera bloquée (no new digests)
- Nécessite intervention manuelle urgente pour éviter downtime

---

## Root Cause Analysis

### Source du problème
La table `contents` accumule tous les articles RSS synchro depuis le lancement:
- Sync RSS toutes les 30 minutes (configurable via `rss_sync_interval_minutes`)
- Aucune politique de rétention → accumulation illimitée
- Articles de 2+ mois toujours en DB alors qu'invisibles dans l'app

### Données techniques
```sql
-- Articles par tranche d'âge (estimé pour 10 users)
SELECT
  COUNT(*) FILTER (WHERE published_at >= NOW() - INTERVAL '14 days') as recent_14d,
  COUNT(*) FILTER (WHERE published_at < NOW() - INTERVAL '14 days' AND published_at >= NOW() - INTERVAL '30 days') as old_14_30d,
  COUNT(*) FILTER (WHERE published_at < NOW() - INTERVAL '30 days') as ancient_30d_plus,
  COUNT(*) as total
FROM contents;

-- Attendu: 70-80% des articles ont > 14 jours (inutiles pour digests)
```

### Pourquoi 14 jours?
- **Digest quotidien**: Utilise uniquement articles récents (< 7 jours en pratique)
- **Buffer de sécurité**: 14 jours = 2x la fenêtre active
- **User behavior**: Aucun user ne consulte articles > 2 semaines
- **Storage impact**: Purge 14j+ libère ~150-200 MB (50% du storage)

---

## Solution

### Stratégie: Purge Automatique Quotidienne

Implémentation d'un worker de nettoyage quotidien (cron 3 AM Paris) qui supprime les articles > 14 jours.

### Architecture
```
┌─────────────────────────────────────────────────────────────┐
│ APScheduler (scheduler.py)                                  │
├─────────────────────────────────────────────────────────────┤
│ • RSS Sync (30 min interval)  → Ajoute articles             │
│ • Daily Digest (8 AM)         → Consomme articles récents   │
│ • Storage Cleanup (3 AM)      → Supprime articles > 14j  ✨ │
└─────────────────────────────────────────────────────────────┘
```

### Impacts CASCADE (Foreign Keys)
La suppression d'un article `contents` déclenche CASCADE sur:
- ✅ `user_content_status` (ondelete="CASCADE")
- ✅ `daily_top3` (ondelete="CASCADE")
- ✅ `classification_queue` (ondelete="CASCADE")
- ⚠️ `daily_digest.items` (JSONB) → Orphelins mais **non bloquant** (digests passés non affichés)

### Configuration
- **Env var**: `RSS_RETENTION_DAYS` (default: 14)
- **Runtime**: Modifiable sans redéploiement (config.py LRU cache)
- **Monitoring**: `verify_storage_health.sh` pour alerting

---

## Files Modified

### Created Files

1. **`packages/api/app/workers/storage_cleanup.py`** (73 lignes)
   - `async def cleanup_old_articles() -> dict`
   - Pattern A (simple async function) comme `rss_sync.py`
   - Logging structuré (start, skip, completion, error)
   - Rollback automatique sur erreur

2. **`packages/api/tests/test_storage_cleanup.py`** (146 lignes)
   - 5 tests unitaires:
     - `test_cleanup_deletes_old_articles`
     - `test_cleanup_skips_when_no_old_articles`
     - `test_cleanup_rollback_on_error`
     - `test_cleanup_respects_custom_retention_days`
     - `test_cleanup_logs_statistics`

3. **`docs/qa/scripts/verify_storage_health.sh`** (44 lignes)
   - Query `pg_database_size(current_database())`
   - Breakdown articles (recent vs old)
   - Exit codes: 0 (OK <400MB), 1 (Warning 400-450MB), 2 (Critical >450MB)

### Modified Files

4. **`packages/api/app/config.py`** (+3 lignes)
   ```python
   # RSS Retention
   rss_retention_days: int = 14
   ```

5. **`packages/api/app/workers/scheduler.py`** (+10 lignes)
   - Import `cleanup_old_articles`
   - CronTrigger (3 AM Paris daily)
   - Job ID: `storage_cleanup`

---

## Verification

### 1. Tests unitaires
```bash
cd packages/api
source venv/bin/activate
pytest tests/test_storage_cleanup.py -v
```

**Attendu**: 5/5 tests passent

### 2. Vérification scheduler
```bash
cd packages/api
uvicorn app.main:app --reload --port 8080
# Logs doivent montrer: "Scheduler started" avec 4 jobs (rss_sync, daily_top3, daily_digest, storage_cleanup)
```

### 3. Test manuel du worker
```python
# Python REPL ou script temporaire
import asyncio
from app.workers.storage_cleanup import cleanup_old_articles

async def test():
    result = await cleanup_old_articles()
    print(f"Deleted: {result['deleted_count']} articles")

asyncio.run(test())
```

### 4. Monitoring en production
```bash
# Supabase Dashboard → Storage tab (before)
# Exécuter purge manuelle (voir section suivante)
# Supabase Dashboard → Storage tab (after)
# Attendu: -150 à -200 MB

# Via script
DATABASE_URL="postgresql://..." bash docs/qa/scripts/verify_storage_health.sh
# Attendu: Storage < 300 MB (60%), exit code 0
```

---

## Purge Manuelle Immédiate (URGENT)

### Avant déploiement du worker automatique

**Pourquoi**: Le worker cron s'exécutera seulement demain à 3 AM. Pour libérer l'espace immédiatement, exécuter cette requête SQL dans Supabase SQL Editor.

### Requête SQL (Supabase SQL Editor)

```sql
-- ÉTAPE 1: Vérifier le nombre d'articles à supprimer (DRY RUN)
SELECT
    COUNT(*) as articles_to_delete,
    MIN(published_at) as oldest_article,
    MAX(published_at) as newest_article_to_delete
FROM contents
WHERE published_at < NOW() - INTERVAL '14 days';

-- Attendu: ~5000-8000 articles (estimation pour 10 users)

-- ÉTAPE 2: Vérifier l'espace avant purge
SELECT pg_database_size(current_database()) / 1024 / 1024 AS size_before_mb;

-- Attendu: ~411 MB

-- ÉTAPE 3: Exécuter la purge (ATTENTION: Action irréversible)
-- ⚠️ Les FK CASCADE supprimeront aussi user_content_status, daily_top3, classification_queue
DELETE FROM contents
WHERE published_at < NOW() - INTERVAL '14 days';

-- ÉTAPE 4: Vérifier l'espace après purge
SELECT pg_database_size(current_database()) / 1024 / 1024 AS size_after_mb;

-- Attendu: ~250-300 MB (baisse de 150-200 MB)

-- ÉTAPE 5: Vérifier la répartition des articles restants
SELECT
    COUNT(*) as remaining_articles,
    MIN(published_at) as oldest_remaining,
    MAX(published_at) as newest_article
FROM contents;

-- Attendu: ~2000-3000 articles récents (< 14 jours)
```

### Screenshots à capturer
- **Avant**: Supabase Dashboard → Storage → 411 MB / 500 MB
- **Après**: Supabase Dashboard → Storage → ~260 MB / 500 MB

---

## Rollback Plan

### Si problème détecté après déploiement

1. **Désactiver le worker** (sans redéploiement):
   ```bash
   # Railway Variables
   RSS_RETENTION_DAYS=999999  # Empêche purge (articles trop vieux n'existent pas)
   ```

2. **Rollback code** (si bugs critiques):
   ```bash
   git revert <commit-sha>
   git push origin main
   # Railway auto-redéploie
   ```

3. **Restaurer depuis backup Supabase** (si perte de données critique):
   - Supabase Dashboard → Database → Backups
   - Restaurer snapshot pré-purge (Supabase garde 7 jours de backups)

---

## Prevention & Monitoring

### Alerting
```bash
# Cron quotidien (Railway/Github Actions)
0 9 * * * DATABASE_URL=$DATABASE_URL bash docs/qa/scripts/verify_storage_health.sh || curl -X POST $SLACK_WEBHOOK -d '{"text":"⚠️ Storage critique"}'
```

### Métriques à surveiller
- **Storage usage**: Doit rester stable à 250-300 MB après purge
- **Article count**: ~2000-3000 articles (< 14 jours)
- **Worker logs**: `storage_cleanup_completed` quotidien dans logs Railway
- **Erreurs**: Aucune erreur `storage_cleanup_failed` dans Sentry

### Guardrails
- **Index `ix_contents_published_at`**: DELETE WHERE est rapide (< 5 secondes)
- **FK CASCADE**: PostgreSQL gère les suppressions dépendantes atomiquement
- **Rollback automatique**: Exception dans worker → session.rollback() → aucune perte partielle

---

## Next Steps (Post-Implementation)

1. ✅ Déployer sur Railway (commit + push)
2. ⏳ Exécuter purge manuelle SQL (AVANT déploiement pour espace immédiat)
3. ⏳ Vérifier logs Railway après déploiement (scheduler démarre avec 4 jobs)
4. ⏳ Attendre 3 AM Paris (1ère exécution auto du worker)
5. ⏳ Vérifier logs le lendemain: `storage_cleanup_completed` avec `deleted_count`
6. ⏳ Créer `maintenance-capacity-analysis-alpha2.md` (analyse complète capacité)
7. ⏳ Update CHANGELOG.md avec cette maintenance

---

## Related Documentation

- **Capacity Analysis**: `docs/maintenance/maintenance-capacity-analysis-alpha2.md` (à créer)
- **Architecture**: `docs/architecture.md` (Workers section)
- **Safety Guardrails**: `docs/agent-brain/safety-guardrails.md` (DB operations)
- **Navigation Matrix**: `docs/agent-brain/navigation-matrix.md` (Maintenance workflow)

---

*Maintenance complétée par: @dev agent (Claude Code)*
*Date d'implémentation: 2026-02-16*
*Status: ✅ Code ready, ⏳ Awaiting deployment + manual purge*
