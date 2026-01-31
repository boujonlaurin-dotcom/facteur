# Plan d'Implémentation: US-4 NER Service

## 🎯 Objectif
Implémenter un service de Named Entity Recognition (NER) utilisant spaCy pour extraire des entités nommées (personnes, organisations, produits, événements) des articles.

## 📋 Référence
- **User Story**: [US-4 NER Service](../../../docs/stories/core/4.2.reco-engine-v3/us-4-ner-service.story.md)
- **Branche**: `feature/us-4-ner-service`
- **Dependencies**: US-2 (Async Queue Architecture) - ✅ Complétée

---

## 🏗️ Architecture

### Pipeline NER
```
Article Text
    │
    ▼
┌─────────────────────┐
│ spaCy NER Pipeline  │
│ fr_core_news_md     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Entity Filter       │
│ (remove common      │
│  words, duplicates) │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Store in DB         │
│ content.entities    │
└─────────────────────┘
```

---

## 📁 Fichiers à Modifier/Créer

### 1. Dépendances
**Fichier**: `packages/api/requirements-ml.txt`
- ✅ Existe déjà avec transformers et torch
- **Action**: Ajouter spaCy

### 2. Service NER
**Fichier**: `packages/api/app/services/ml/ner_service.py`
- **Action**: Créer le service NER complet
- **Features**:
  - Chargement du modèle `fr_core_news_md`
  - Extraction asynchrone d'entités
  - Filtrage des mots communs
  - Mapping des labels (PER→PERSON, GPE→LOCATION, etc.)
  - Singleton pattern

### 3. Migration Base de Données
**Fichier**: `packages/api/alembic/versions/xxx_add_entities_to_content.py`
- **Action**: Créer migration Alembic
- **Changes**:
  - Ajouter colonne `entities` (JSONB) à la table `contents`
  - Créer index GIN pour requêtes rapides

### 4. Modèle Content
**Fichier**: `packages/api/app/models/content.py`
- **Action**: Ajouter champ `entities` au modèle SQLAlchemy

### 5. Worker de Classification
**Fichier**: `packages/api/app/workers/classification_worker.py`
- **Action**: Intégrer le service NER dans le worker existant
- **Features**:
  - Extraction d'entités après la classification de topics
  - Stockage des entités dans la base
  - Méthode `mark_completed_with_entities` pour le queue service

### 6. Queue Service
**Fichier**: `packages/api/app/services/classification_queue_service.py`
- **Action**: Ajouter méthode pour marquer complété avec entités

### 7. Tests Unitaires
**Fichier**: `packages/api/tests/ml/test_ner_service.py`
- **Action**: Créer tests complets
- **Tests**:
  - Extraction de personnes
  - Extraction d'organisations
  - Filtrage des mots communs
  - Test de performance (<50ms)

### 8. Script d'Installation
**Fichier**: `scripts/install_spacy_model.sh`
- **Action**: Créer script pour télécharger le modèle fr_core_news_md

---

## 🧪 Tests et Vérification

### Tests Unitaires
```bash
cd packages/api
pytest tests/ml/test_ner_service.py -v
```

### Test d'Intégration
```bash
cd packages/api
python -c "
from app.services.ml.ner_service import NERService
import asyncio
ner = NERService()
result = asyncio.run(ner.extract_entities('Elon Musk launches Tesla'))
print('Entities:', result)
"
```

### Vérification Base de Données
```bash
# Vérifier migration
cd packages/api
alembic current
alembic history
```

---

## 📊 Critères d'Acceptation

| Critère | Target | Méthode de Vérification |
|---------|--------|------------------------|
| Extraction d'entités | Fonctionnelle | Test unitaire avec "Elon Musk" |
| Types d'entités | 6 types | Vérifier PERSON, ORG, PRODUCT, LOCATION, EVENT, WORK_OF_ART |
| Performance | <50ms/article | Test benchmark avec 500 mots |
| Support Français | Opérationnel | Test avec "Emmanuel Macron" |
| Stockage DB | JSONB | Vérifier colonne `entities` |

---

## ⚠️ Points d'Attention

1. **Modèle spaCy**: Le modèle `fr_core_news_md` doit être téléchargé séparément
2. **RAM**: ~100MB supplémentaires, vérifier en environnement de prod
3. **Performance**: Utiliser thread pool pour ne pas bloquer l'event loop
4. **Fallback**: Si NER échoue, continuer avec topics uniquement

---

## 🚀 Plan d'Exécution

### Phase 1: Setup (30 min)
1. Ajouter spaCy à requirements-ml.txt
2. Créer script d'installation du modèle
3. Télécharger et vérifier le modèle

### Phase 2: Développement Core (2h)
1. Créer `ner_service.py`
2. Créer migration Alembic
3. Mettre à jour modèle Content

### Phase 3: Intégration (1h)
1. Intégrer NER dans ClassificationWorker
2. Mettre à jour ClassificationQueueService
3. Mettre à jour __init__.py pour export

### Phase 4: Tests (30 min)
1. Créer tests unitaires
2. Vérifier performance
3. Tester avec articles français

### Phase 5: Documentation (30 min)
1. Créer script de vérification QA
2. Mettre à jour la User Story (status)

---

## 📈 Définition de "Done"

- [ ] Service NER fonctionnel avec spaCy
- [ ] Migration DB appliquée (colonne `entities`)
- [ ] ClassificationWorker met à jour les entités
- [ ] Tests unitaires passent
- [ ] Performance <50ms/article vérifiée
- [ ] Support Français validé
- [ ] Script QA créé et fonctionnel

---

**Créé**: 2026-01-30  
**Auteur**: Agent BMAD  
**Status**: En attente approbation
