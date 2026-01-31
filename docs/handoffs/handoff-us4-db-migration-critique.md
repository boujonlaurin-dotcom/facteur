# Handoff: Décision Critique US-4 - Migration DB & Coûts Supabase

## 🎯 Contexte

**Agent précédent :** Développement US-4 NER Service (spaCy)  
**Status :** Code complet mais tests E2E bloqués  
**Problème critique :** Impossibilité d'appliquer la migration DB sur Supabase

---

## ❌ Problèmes Identifiés

### 1. Timeout SQL sur Supabase (Gratuit)
- **Requête :** `ALTER TABLE contents ADD COLUMN entities TEXT[];`
- **Erreur :** Timeout après ~30s
- **Cause :** Table `contents` trop volumineuse pour le tier gratuit
- **Impact :** Migration impossible = colonne absente = NER sans stockage

### 2. Egress Limit Atteint
- **Symptôme :** Toutes les connexions CLI (Railway, alembic, scripts) timeout
- **Cause :** Quota de données sortantes dépassé
- **Impact :** Impossible de tester/valider depuis l'environnement local

### 3. Feed en Loading Infini (Reporté par utilisateur)
- **Hypothèse :** Lié aux modifications d'autres agents sur la même branche
- **Code US-4 :** Résilient (try/catch) mais non validé en conditions réelles

---

## ✅ Ce qui Fonctionne

1. **Code NER :** Service spaCy opérationnel (Python 3.13 + spaCy 3.8.11)
2. **Tests locaux :** Commande one-liner fonctionne
   ```bash
   bash docs/qa/scripts/test_ner_one_liner.sh
   ```
3. **Extraction :** Entities détectées (PERSON, ORG, etc.) correctement
4. **Branche Git :** `feature/us-4-ner-service` propre (fichiers parasites retirés)

---

## 🤔 Décisions à Prendre

### Option 1 : Upgrader Supabase (20$/mois)
**Avantages :**
- Migration DB possible
- Plus de ressources CPU/RAM
- Connexions CLI fonctionnelles

**Inconvénients :**
- Coût élevé pour un MVP
- Engagement mensuel

### Option 2 : Migration Manuelle Splitée
**Requêtes :**
```sql
-- Étape 1 (rapide) : Ajout colonne seul
ALTER TABLE contents ADD COLUMN IF NOT EXISTS entities TEXT[];

-- Étape 2 (plus tard) : Index en parallèle
CREATE INDEX CONCURRENTLY idx_contents_entities ON contents USING gin (entities);
```
**Risque :** Toujours risque de timeout sur l'étape 1 si table très grosse

### Option 3 : Contournement sans Migration
**Idée :** Ne pas stocker les entités en DB temporairement
- Extraction NER fonctionne
- Entités utilisées en mémoire uniquement
- Pas de persistance = pas besoin de colonne

**Limites :** Pas d'historique des entités, pas de recherche par entité

### Option 4 : Désactiver NER Temporairement
- Retirer l'intégration dans ClassificationWorker
- Garder le code mais ne pas l'utiliser
- Attendre upgrade/réduction de la table

### Option 5 : Réduire la Table Contents
- Purger les vieux contenus avant migration
- Complexe (relations FK, statuts utilisateurs)
- Risque de perte de données

---

## 📋 Questions pour l'Utilisateur

1. **Budget :** Les 20$/mois sont-ils acceptables ou non-négociables ?
2. **Priorité :** Le NER est-il critique pour le MVP ou une nice-to-have ?
3. **Table contents :** Combien de lignes environ ? (Dashboard Supabase → Table → Count)
4. **Alternatives :** Connaît-il d'autres hébergeurs PostgreSQL gratuits (Railway, Neon, etc.) ?
5. **Délai :** A-t-il besoin du NER immédiatement ou peut attendre ?

---

## 📁 Fichiers Clés

| Fichier | Description | Status |
|---------|-------------|--------|
| `packages/api/app/services/ml/ner_service.py` | Service NER complet | ✅ Testé |
| `packages/api/alembic/versions/p1q2r3s4t5u6_add_content_entities.py` | Migration | ❌ Non appliquée |
| `packages/api/app/workers/classification_worker.py` | Intégration NER | ⚠️ Non testé E2E |
| `packages/api/app/services/classification_queue_service.py` | Persistence | ⚠️ Try/catch ajouté |

---

## 🎯 Mission pour le Nouvel Agent

Aider l'utilisateur à :
1. **Analyser** la taille réelle de la table contents
2. **Évaluer** les options selon son budget et ses priorités
3. **Choisir** la meilleure stratégie (upgrade, contournement, désactivation)
4. **Exécuter** la décision (commit, revert, ou plan d'action)
5. **Documenter** la solution choisie

---

## ⚠️ Points d'Attention

- **Ne pas** pousser en prod sans décision claire
- **Tester** toute solution proposée avant validation
- **Vérifier** les conflits avec d'autres agents (branche propre demandée)
- **Coûts :** L'utilisateur est sensible aux coûts (MVP)

---

*Créé : 2026-01-30*  
*Agent précédent : US-4 NER Service Implementation*  
*Urgence : Haute (blocage déploiement)*
