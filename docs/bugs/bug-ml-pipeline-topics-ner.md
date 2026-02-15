# Bug: ML Pipeline (Topics + NER) cassé en production

## Statut
- [ ] En cours d'investigation
- [x] En cours de correction (date: 2026-02-15)
- [ ] Corrigé — en attente vérification post-deploy numpy

## Sévérité
- 🔴 Critique (source sync cassé, ML worker bloqué)

## Description

Le deploy de la branche `fix/ml-pipeline-topics-ner` (PR #77, squash merge `aa6a942`) a introduit 3 bugs qui cassent le ML pipeline ET le source sync en production.

**Impact observé:**
- Source sync: 206/207 sources en échec (toute la synchro RSS cassée)
- ML worker: traite des batches mais 100% des items échouent
- Queue stats dégradés: failed=1097, completed=14, success_rate=1.34%

---

## Bugs identifiés (3)

### Bug 1: Colonne `entities` dans l'ORM mais absente en DB
**Sévérité:** 🔴 Critique
**Commit fix:** `b80cabc`
**Status:** ✅ Déployé et fixé

**Cause racine:**
Le squash merge PR #77 a inclus le commit qui réactivait `Content.entities` dans l'ORM (`167d372`) mais a **perdu** le commit qui le re-commentait (`d1c6134`). Seul le fichier migration a été modifié dans le merge (1 file changed), pas `content.py`.

Résultat: SQLAlchemy génère `SELECT ... contents.entities ...` sur toute query Content, mais la colonne n'existe pas en DB → `ProgrammingError: UndefinedColumn` sur TOUTES les queries.

**Solution:** Re-commenter `entities` dans `packages/api/app/models/content.py` ligne 67.

**Fichiers concernés:**
- `packages/api/app/models/content.py`

---

### Bug 2: Lazy-loading async → MissingGreenlet
**Sévérité:** 🔴 Critique
**Commit fix:** `4018058`
**Status:** ✅ Déployé et fixé

**Cause racine:**
Le worker accède `item.content` (relationship lazy-loaded) et `content.source` dans un contexte async SQLAlchemy. En mode async, le lazy-loading synchrone lève `MissingGreenlet` (greenlet_spawn not called). L'exception est attrapée silencieusement par le worker et l'item est marqué `failed` sans log d'erreur visible.

**Solution:** Remplacer les accès lazy par des chargements explicites async:
```python
# Avant (crash MissingGreenlet):
content = item.content
# ...
topics = content.source.granular_topics or []

# Après (chargement async explicite):
content = await session.get(Content, item.content_id)
source = await session.get(Source, content.source_id) if content.source_id else None
# ...
topics = source.granular_topics or []
```

**Fichiers concernés:**
- `packages/api/app/workers/classification_worker.py`

---

### Bug 3: numpy manquant → mDeBERTa classification échoue
**Sévérité:** 🟠 Haute (fallback fonctionne)
**Commit fix:** `5a7304c`
**Status:** ⏳ Pushé, en attente deploy + vérification

**Cause racine:**
`numpy` n'est pas listé explicitement dans `requirements-ml.txt`. Il est une dépendance indirecte de `torch`/`transformers`, mais sur l'image Docker slim Python 3.12, la résolution pip peut ne pas l'installer correctement.

Le modèle mDeBERTa se charge (lazy imports) mais échoue à l'inférence avec `"Numpy is not available"`. Le worker tombe en fallback sur `source.granular_topics`.

**Solution:** Ajouter `numpy>=1.26.0,<2.0` en tête de `requirements-ml.txt`.

**Fichiers concernés:**
- `packages/api/requirements-ml.txt`

---

## Étapes de reproduction
1. Déployer le merge `aa6a942` (PR #77) sur Railway
2. Observer les logs: `column contents.entities does not exist` sur toutes les queries
3. Queue stats: `failed` monte, `completed` stagne, source sync cassé

---

## Vérification post-deploy

### Checklist agent suivant

Après deploy du commit `5a7304c` (numpy fix):

```bash
# 1. Vérifier le commit déployé
railway logs --service Facteur 2>&1 | grep "commit_sha"
# Attendu: commit_sha="5a7304c" (ou plus récent)

# 2. Vérifier absence d'erreurs entities
railway logs --service Facteur 2>&1 | grep "UndefinedColumn"
# Attendu: aucun résultat

# 3. Vérifier absence d'erreurs MissingGreenlet
railway logs --service Facteur 2>&1 | grep -i "greenlet\|MissingGreenlet"
# Attendu: aucun résultat

# 4. Vérifier que numpy est résolu
railway logs --service Facteur 2>&1 | grep "Numpy is not available"
# Attendu: aucun résultat (si numpy fix déployé)

# 5. Vérifier chargement du modèle mDeBERTa
railway logs --service Facteur 2>&1 | grep "classification_service.model_loaded"
# Attendu: présent (si ML_ENABLED=true sur Railway)

# 6. Vérifier que le worker traite des batches
railway logs --service Facteur 2>&1 | grep "classification_worker.processing_batch"
# Attendu: batches réguliers toutes les ~60s

# 7. Queue stats
curl -s https://facteur-production.up.railway.app/api/internal/admin/queue-stats | python3 -m json.tool
# Attendu: completed en hausse, 0 new failures, success_rate > 50%

# 8. Vérifier qu'un article a des topics
# Via Supabase Dashboard > Table contents > Filter: topics IS NOT NULL
# Attendu: articles récemment classifiés avec topics non-vides
```

### Variable d'environnement Railway

Vérifier que `ML_ENABLED=true` est configuré sur Railway:
```bash
railway variables --service Facteur | grep ML_ENABLED
```
Si absent ou `false`, le classifier mDeBERTa ne chargera pas. Le worker fonctionnera quand même en fallback (source topics), mais sans la classification ML fine.

---

## Supabase: migration `entities` column

### Contexte
La colonne `contents.entities` (TEXT[] + GIN index) ne peut pas être créée sur le tier gratuit Supabase (timeout ALTER TABLE sur table volumineuse ~35k rows).

### Options pour créer la colonne

| Option | Description | Recommandation |
|--------|-------------|----------------|
| **A** | Upgrade Supabase Pro (25$/mois) | ✅ Recommandé si budget OK |
| **B** | `ALTER TABLE` via Supabase Dashboard SQL Editor (pas de timeout CLI) | ⚠️ Tester d'abord |
| **C** | Créer via `CREATE INDEX CONCURRENTLY` (non-bloquant) | ✅ Si option B timeout |
| **D** | Table séparée `content_entities` | ❌ Sur-complexe pour le besoin |

### Procédure recommandée (Option B ou C)

```sql
-- Étape 1: Ajouter la colonne (rapide, ~1s même sur grosse table)
ALTER TABLE contents ADD COLUMN IF NOT EXISTS entities TEXT[];

-- Étape 2: Créer l'index (peut être lent, utiliser CONCURRENTLY)
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_contents_entities
ON contents USING gin (entities);
```

**Après la migration SQL:**
1. Dé-commenter `entities` dans `packages/api/app/models/content.py` ligne 67
2. Mettre la migration `p1q2r3s4t5u6` en mode actif (remplacer `pass` par le vrai DDL)
3. Commit + push + deploy
4. Vérifier: `railway logs | grep "entities_column_missing"` → aucun résultat
5. MAJ `docs/maintenance/maintenance-ner-disabled.md` → status "Réactivé"

---

## Fichiers concernés (tous commits)

| Fichier | Commit | Changement |
|---------|--------|------------|
| `packages/api/app/models/content.py` | `b80cabc` | Re-commenter `entities` |
| `packages/api/app/workers/classification_worker.py` | `4018058` | Fix async lazy-loading |
| `packages/api/requirements-ml.txt` | `5a7304c` | Ajouter numpy explicite |

## Timeline

| Heure (UTC) | Événement |
|-------------|-----------|
| ~18:30 | Deploy PR #77 (`aa6a942`) — production cassée |
| 18:36 | Erreurs `UndefinedColumn` massives, source sync 206/207 failed |
| 18:49 | Deploy hotfix entities (`b80cabc`) — source sync restauré |
| 18:49-19:07 | Worker traite mais 100% fail (lazy-loading async) |
| 19:11 | Deploy fix lazy-loading (`4018058`) — items commencent à compléter |
| 19:15 | Push fix numpy (`5a7304c`) — en attente deploy |

## Notes

- Les 1097 items en `failed` ont `retry_count >= 3` et ne seront pas retentés automatiquement. Un reset manuel peut être nécessaire si on veut les retraiter:
  ```sql
  UPDATE classification_queue
  SET status = 'pending', retry_count = 0, error_message = NULL
  WHERE status = 'failed';
  ```
- Le backlog de ~33,800 items prendra ~56h au rythme actuel (10 items/min). Considérer augmenter `batch_size` dans le worker si les ressources Railway le permettent.
- La feature NER extrait des entités mais ne les persiste pas (colonne absente). Voir `docs/maintenance/maintenance-ner-disabled.md`.
