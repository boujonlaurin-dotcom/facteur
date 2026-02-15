# Maintenance: NER Service Désactivé Temporairement

## 🎯 Contexte

**Date:** 2026-01-31  
**Décision:** Désactivation temporaire du NER (Option 4 choisie par l'utilisateur)  
**Raison:** Impossibilité d'appliquer la migration DB sur Supabase tier gratuit

---

## ❌ Pourquoi le NER est désactivé

### Problème Root Cause
La migration `p1q2r3s4t5u6_add_content_entities.py` tente d'ajouter :
```python
ALTER TABLE contents ADD COLUMN entities TEXT[];
CREATE INDEX ix_contents_entities ON contents USING gin (entities);
```

**Problème:** La table `contents` est trop volumineuse pour le tier gratuit Supabase :
- Timeout après ~30s sur `ALTER TABLE`
- Egress limit atteint (connexions CLI impossibles)

### Options Évaluées
| Option | Description | Choix |
|--------|-------------|-------|
| 1 | Upgrader Supabase (20$/mois) | ❌ Budget MVP |
| 2 | Splitter la migration | ❌ Risque timeout persistant |
| 3 | Table séparée | ⚠️ Complexe |
| 4 | **Désactiver temporairement** | ✅ **Choisi** |
| 5 | Réduire la table | ❌ Risqué |

---

## ✅ État Actuel (MAJ 2026-02-15)

### Code Préservé
Tout le code NER reste en place et fonctionnel :

| Fichier | Status | Note |
|---------|--------|------|
| `ner_service.py` | ✅ | Service spaCy complet, testé |
| `classification_worker.py` | ✅ | Intégration prête, fix lazy-loading async appliqué (`4018058`) |
| `classification_queue_service.py` | ✅ | Méthode `mark_completed_with_entities` avec try/catch |
| Migration `p1q2r3s4t5u6` | ⚠️ | **No-op** (pass), prête pour réactivation |
| Modèle `Content.entities` | ⚠️ | **Commenté** (ligne 67), colonne DB absente |

### Ce qui fonctionne en production
- **NER extraction**: ✅ fonctionne (entités extraites dans les logs: Giorgia Meloni, TF1, etc.)
- **Persistance entities**: ❌ colonne absente, entités ignorées silencieusement
- **Topics classification**: ⚠️ mDeBERTa échoue (numpy manquant), fallback `source.granular_topics`
- **Worker processing**: ✅ batches de 10 toutes les ~60s, items complètent

```bash
# Test local one-liner - FONCTIONNE
bash docs/qa/scripts/test_ner_one_liner.sh
```

Extraction d'entités opérationnelle (PERSON, ORG, LOCATION, etc.)

---

## 🔧 Comment le NER est désactivé

### 1. Worker - Extraction désactivée
Le `ClassificationWorker` utilise toujours `_extract_topics_and_entities()` mais :
- L'extraction NER fonctionne (code prêt)
- La persistance en DB est **désactivée** car la colonne n'existe pas
- Le try/catch dans `mark_completed_with_entities` log un warning silencieux

### 2. Service - Résilience
```python
# classification_queue_service.py
try:
    content.entities = [json.dumps(entity) for entity in entities]
except Exception as e:
    # Column might not exist yet - log but don't fail
    logger.warning("entities_column_missing", error=str(e), content_id=str(content.id))
```

**Résultat:** Le worker continue de fonctionner, les entités sont simplement ignorées.

---

## 📋 Plan de Réactivation

### Quand réactiver ?
**Critères:**
1. **Upgrade Supabase** vers un tier payant (25$/mois)
2. **OU** Migration vers un autre hébergeur PostgreSQL (Railway, Neon, etc.)
3. **OU** Application manuelle du DDL via Supabase Dashboard SQL Editor

### Étapes de réactivation

**Étape 1 — Créer la colonne en DB** (via Supabase Dashboard > SQL Editor):
```sql
-- Ajout colonne (rapide, ~1s même sur grosse table)
ALTER TABLE contents ADD COLUMN IF NOT EXISTS entities TEXT[];

-- Index GIN en mode non-bloquant
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_contents_entities
ON contents USING gin (entities);
```

**Étape 2 — Vérifier la colonne:**
```sql
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'contents' AND column_name = 'entities';
```

**Étape 3 — Réactiver dans le code:**
1. Dé-commenter `entities` dans `packages/api/app/models/content.py` ligne 67
2. Restaurer le DDL dans la migration `p1q2r3s4t5u6` (remplacer `pass` par le vrai upgrade)
3. Commit + push + deploy

**Étape 4 — Tester l'intégration E2E:**
```bash
bash docs/qa/scripts/verify_us4_ner.sh
```

**Étape 5 — Monitorer les logs:**
- Vérifier que `entities_column_missing` n'apparaît plus
- Confirmer que les entités sont bien stockées
- Vérifier un article en DB: `SELECT entities FROM contents WHERE entities IS NOT NULL LIMIT 5;`

---

## 🧹 Cleanup Effectué

### Bug corrigé
- **Fichier:** `classification_queue_service.py`
- **Problème:** Méthode `mark_completed_with_entities` dupliquée (lignes 90-118 et 120-155)
- **Solution:** Suppression de la première version, conservation de celle avec try/catch

### Tests validés
```bash
# Test NER local
bash docs/qa/scripts/test_ner_one_liner.sh

# Résultat: ✅ Extraction fonctionnelle
```

---

## 📊 Impact Utilisateur

### Avant la désactivation
- Feed en loading infini (potentiellement lié à d'autres changements)
- Impossible de tester E2E (egress limit)

### Après la désactivation
- **Classification ML:** Continue de fonctionner (topics mDeBERTa)
- **NER:** Exécuté mais non persisté (entités en mémoire uniquement)
- **Feed:** Ne devrait plus être affecté par les problèmes NER
- **Coûts:** Aucun coût supplémentaire

---

## 📝 Notes pour le Futur

### Alternatives considérées
1. **Table séparée `content_entities`:** Évite ALTER TABLE, mais plus complexe
2. **Stockage JSONB:** Une seule colonne, index GIN plus léger
3. **Cache Redis:** Pas besoin de migration DB du tout

### Optimisation possible
Si réactivation avec table volumineuse :
```sql
-- Étapes séparées pour éviter timeout
-- 1. Ajout colonne (rapide, pas d'index)
ALTER TABLE contents ADD COLUMN IF NOT EXISTS entities TEXT[];

-- 2. Index en parallèle (lent mais non-bloquant)
CREATE INDEX CONCURRENTLY idx_contents_entities ON contents USING gin (entities);
```

---

## 🔗 Références

- **Handoff original:** `docs/handoffs/handoff-us4-db-migration-critique.md`
- **Script test:** `docs/qa/scripts/test_ner_one_liner.sh`
- **Script vérification:** `docs/qa/scripts/verify_us4_ner.sh`
- **User Story:** US-4 NER Service Implementation

---

**Status:** NER désactivé temporairement, code conservé pour réactivation future
**Bug doc associé:** `docs/bugs/bug-ml-pipeline-topics-ner.md`
**Dernière mise à jour:** 2026-02-15
