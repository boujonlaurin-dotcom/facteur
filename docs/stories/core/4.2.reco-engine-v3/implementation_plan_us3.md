# Plan d'Implémentation - US 3: Intégration mDeBERTa dans le Worker

**Story:** 4.2-US-3 Integrate mDeBERTa in Worker  
**Date:** 2026-01-30  
**Branche:** `feature/us-3-mdeberta-worker`  
**Statut:** 🟡 En attente de validation

---

## 📊 Analyse du Code Existant (Phase MEASURE)

### ClassificationService (`packages/api/app/services/ml/classification_service.py`)
- ✅ Modèle mDeBERTa déjà configuré (`MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7`)
- ✅ 50 labels candidats en français avec mapping vers slugs
- ✅ Lazy loading si `ml_enabled=True`
- ✅ Méthode `classify()` synchrone existante
- ❌ Pas de wrapper async pour non-blocking
- ❌ Pas de métriques de performance
- ❌ Pas de gestion de fallback

### ClassificationWorker (`packages/api/app/workers/classification_worker.py`)
- ✅ Architecture async avec batch processing
- ✅ Retry automatique via `mark_failed()`
- ❌ Utilise mock extraction (`_extract_topics_from_content()`)
- ❌ N'appelle pas le ClassificationService
- ❌ Pas de fallback vers `source.granular_topics`
- ❌ Pas de métriques temps de traitement

### Configuration (`packages/api/app/config.py`)
- ✅ `ml_enabled: bool = False` (ligne 82)
- ❌ `ML_ENABLED` non défini dans `.env`

### Router Internal (`packages/api/app/routers/internal.py`)
- ✅ Endpoint `/admin/queue-stats` existe
- ❌ Pas d'endpoint pour statut ML

### Modèle Content (`packages/api/app/models/content.py`)
- ✅ Champ `topics: Mapped[Optional[list[str]]]` (ligne 56)
- ✅ Relation `source` disponible

---

## 🎯 Plan d'Implémentation (Phase DECIDE)

### Task 1: Activer ML Configuration (15 min)
**Fichier:** `packages/api/.env`

**Action:** Ajouter la variable d'environnement
```bash
# ML Classification (Story 4.2-US-3)
ML_ENABLED=true
TRANSFORMERS_CACHE=/tmp/transformers_cache
```

**Rollback:**
```bash
# Revenir à false si problème
ML_ENABLED=false
```

---

### Task 2: Enhancer ClassificationService (1h)
**Fichier:** `packages/api/app/services/ml/classification_service.py`

**Actions:**

1. **Ajouter méthode `classify_async()`**
   - Wrapper async utilisant `loop.run_in_executor()`
   - Non-blocking pour l'event loop FastAPI
   - Retourne `list[str]` (topics slugs)

2. **Ajouter métriques de performance**
   - Logger temps d'exécution (elapsed_ms)
   - Méthode `get_stats()` pour monitoring

3. **Exposer `get_classification_service()` dans `__init__.py`**

**Code attendu:**
```python
async def classify_async(
    self,
    title: str,
    description: str = "",
    top_k: int = 3,
    threshold: float = 0.3,
) -> list[str]:
    """Async wrapper - runs classifier in thread pool."""
    if not self.classifier:
        return []
    
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(
        None,
        self._classify_sync,
        title,
        description,
        top_k,
        threshold,
    )

def _classify_sync(self, title: str, description: str, top_k: int, threshold: float) -> list[str]:
    """Synchronous classification (runs in thread)."""
    # ... existing classify() logic with timing
```

**Impact:** Aucune modification cassante, méthode synchrone `classify()` conservée.

---

### Task 3: Intégrer dans ClassificationWorker (1.5h)
**Fichier:** `packages/api/app/workers/classification_worker.py`

**Actions:**

1. **Remplacer mock par ClassificationService**
   ```python
   from app.services.ml.classification_service import get_classification_service
   ```

2. **Modifier `_classify_item()` pour appeler mDeBERTa**
   - Appeler `classifier.classify_async()`
   - Fallback vers `source.granular_topics` si ML échoue ou retourne vide
   - Logger le mode utilisé (ML vs fallback)

3. **Ajouter métriques dans `_process_batch()`**
   - Temps moyen de classification
   - Nombre d'items traités/failed
   - Taux de fallback

**Code attendu:**
```python
async def _classify_item(self, session: AsyncSession, item: ClassificationQueue):
    """Classify content using mDeBERTa with fallback."""
    from app.services.ml.classification_service import get_classification_service
    
    classifier = get_classification_service()
    content = item.content
    
    topics = []
    used_fallback = False
    
    # Try ML classification
    if classifier.is_ready():
        topics = await classifier.classify_async(
            title=content.title,
            description=content.description or "",
            top_k=3,
            threshold=0.3,
        )
    
    # Fallback to source topics if ML fails or returns empty
    if not topics and content.source and content.source.granular_topics:
        topics = content.source.granular_topics[:3]
        used_fallback = True
        log.debug("worker.used_fallback", content_id=str(content.id))
    
    # Save topics to content
    content.topics = topics
    await session.commit()
    
    # Mark queue item completed
    service = ClassificationQueueService(session)
    await service.mark_completed(item.id, topics)
```

**Rollback:** Revenir à l'ancienne méthode mock si ML pose problème.

---

### Task 4: Ajouter Endpoints Admin (30 min)
**Fichier:** `packages/api/app/routers/internal.py`

**Actions:**

1. **Ajouter endpoint `/admin/ml-status`**
   - Statut du modèle (loaded/not loaded)
   - Nom du modèle
   - Stats du service

2. **Ajouter endpoint `/admin/classification-metrics`** (optionnel)
   - Stats de la queue (pending/processing/completed/failed)
   - Temps moyen de traitement (24h)

**Code attendu:**
```python
@router.get("/admin/ml-status")
async def get_ml_status():
    """Get ML classification status."""
    from app.services.ml.classification_service import get_classification_service
    
    classifier = get_classification_service()
    return {
        "enabled": classifier.is_ready(),
        "model_loaded": classifier._model_loaded,
        "model_name": "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7",
        "stats": classifier.get_stats(),
    }
```

---

### Task 5: Tests d'Intégration (1h)
**Fichier:** `packages/api/tests/ml/test_classification_integration.py`

**Tests à créer:**

1. **Test classification temps réel** (avec mock)
   - Vérifier que `classify_async()` retourne une liste
   - Vérifier format des slugs

2. **Test worker avec mDeBERTa** (avec mock)
   - Créer un article test
   - L'ajouter à la queue
   - Exécuter le worker
   - Vérifier que `content.topics` est rempli

3. **Test fallback**
   - Simuler échec ML
   - Vérifier fallback vers `source.granular_topics`

4. **Test performance**
   - Vérifier que classification < 300ms (avec mock rapide)

---

## ✅ Critères d'Acceptation

| AC | Test de Vérification | Statut |
|----|---------------------|--------|
| AC-1: mDeBERTa Activation | `GET /admin/ml-status` retourne `enabled: true` | ⬜ |
| AC-2: Article Classification | Article en queue → `content.topics` rempli | ⬜ |
| AC-3: Processing Time | Logs montrent elapsed_ms < 300ms | ⬜ |
| AC-4: Fallback Mechanism | Si ML vide, utilise `source.granular_topics` | ⬜ |
| AC-5: Error Recovery | Retry 3x puis fallback | ⬜ |

---

## 🚀 Checklist de Déploiement

1. **Pré-déploiement:**
   - [ ] Vérifier 500MB+ RAM disponible
   - [ ] Tester `ML_ENABLED=true` en local
   - [ ] Lancer tests: `pytest tests/ml/ -v`

2. **Déploiement:**
   - [ ] Ajouter `ML_ENABLED=true` dans env production
   - [ ] Déployer branche
   - [ ] Vérifier `/admin/ml-status`
   - [ ] Monitorer logs classification

3. **Post-déploiement:**
   - [ ] Vérifier 100 premières classifications
   - [ ] Confirmer temps moyen < 300ms
   - [ ] Check taux de fallback < 20%

---

## ⚠️ Risques Identifiés

| Risque | Probabilité | Impact | Mitigation |
|--------|------------|--------|------------|
| OOM (RAM 500MB) | Moyen | Élevé | Monitorer mémoire, fallback automatique |
| Model load failure | Faible | Élevé | try/except avec fallback source.topics |
| Latence >300ms | Moyen | Moyen | Thread pool, batch size ajustable |
| Accuracy faible | Moyen | Moyen | Seuil 0.3 ajustable, fallback si vide |

---

## 📝 Commande de Vérification (One-Liner)

```bash
./docs/qa/scripts/verify_us3_mdeberta.sh
```

**Output attendu:**
```
🧪 Vérification US-3: mDeBERTa Worker Integration
=================================================
✅ ML_STATUS: Model loaded and ready
✅ CLASSIFICATION: 10 articles processed
✅ PERFORMANCE: Avg 180ms (target <300ms)
✅ FALLBACK: 2 articles used source.topics (20%)
✅ TESTS: All integration tests passed
=================================================
✅ US-3 Terminée avec succès!
```

---

## 🔄 Rollback Plan

Si problème critique en production:

```bash
# 1. Désactiver ML
export ML_ENABLED=false
# ou modifier .env et restart

# 2. Redeploy avec ancien code
git checkout HEAD~1 -- packages/api/app/workers/classification_worker.py
# Remettre la méthode mock

# 3. Restart API
systemctl restart facteur-api  # ou docker restart
```

---

*Plan créé: 2026-01-30*  
*En attente de validation GO pour phase ACT*
