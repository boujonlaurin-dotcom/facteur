# Handoff Backend — Epic 11 : Custom Topics

Tu es un agent Dev Backend (Python, FastAPI, SQLAlchemy). Ta mission est d'implémenter l'Epic 11 "Custom Topics" côté serveur, de A à Z, avec une couverture de tests E2E maximale (unitaires + intégration).

## Contexte
L'utilisateur peut désormais suivre des "topics libres". Le backend doit gérer ce CRUD, faire le lien via LLM, et modifier l'algorithme de recommandation du feed principal et du Digest.

**Stack :**
- Python 3.12 / FastAPI
- SQLAlchemy (Async) / PostgreSQL
- Pytest (Tests E2E obligatoires)
- Mistral API (pour la classification)

**Documents à lire absolument avant d'écrire du code :**
1. `docs/stories/core/11.custom-topics.story.md` (La bible fonctionnelle)
2. `docs/stories/core/11.custom-topics/vulgarisation-backend.md` (Explications techniques détaillées)

---

## 📋 Tâches d'implémentation (Plan de travail)

### 1. Modélisation DB (SQLAlchemy & Alembic)
- Créer le modèle `UserTopicProfile`.
  - Attributs: `user_id` (UUID, ForeignKey), `topic_name` (Str), `slug_parent` (Str), `keywords` (Array[Str]), `intent_description` (Str), `source_type` (Enum: explicit/implicit), `priority_multiplier` (Float: 0.5, 1.0, 2.0), `composite_score` (Float).
  - UniqueConstraint sur `(user_id, slug_parent)`.
- Générer la migration Alembic auto et la vérifier (*Ne jamais run d'upgrade sans valider le code SQL*).

### 2. Services ML & LLM (Création de Topic)
- Créer un service (ou étendre `ClassificationService`) pour l'appel LLM "One-Shot" lors de la création d'un topic.
- **Prompt :** Demander au LLM (Mistral) de prendre la query utilisateur (ex: "Voiture électrique") et de la mapper sur un des slugs de `VALID_TOPIC_SLUGS` exclusif, en générant 5-10 keywords et une phrase d'intention.
- Gérer le timeout et fallback élégamment.

### 3. API Endpoints (`/personalization/topics`)
- Créer le router et les schémas Pydantic.
- `GET /personalization/topics` : Liste des topics (ouverts).
- `POST /personalization/topics` : Reçoit `{ "name": "..." }`, appelle l'agent LLM, et store en base.
- `PUT /personalization/topics/{id}` : Met à jour le `priority_multiplier` (0.5, 1.0, 2.0).
- `DELETE /personalization/topics/{id}` : Supprime le topic.
- `GET /personalization/suggestions?theme={slug}` : Retourne 3-4 suggestions basées sur les lectures récentes de l'utilisateur qui ne sont pas encore dans ses `UserTopicProfile`.

### 4. Algorithme de Scoring (`scoring_config.py` et layers)
- **Le Feed :** Modifier ou créer une layer (`user_custom_topics.py`) pour appliquer le `priority_multiplier` si l'article matche. Un article matche si :
  `UserTopicProfile.slug_parent` est dans `article.topics` OR un `keyword` matche le titre/description.
- **Le Freshness Tweak :** Modifier `recency_base` dans `scoring_config.py` (le remonter significativement, ex: 100) pour s'assurer que les vieux articles avec gros topics custom n'écrasent pas l'actualité fraîche de la journée.
- **Clustering :** Implémenter le regroupement natif côté API (`get_feed()`). Grouper les articles ≥3 par custom topic. Ne retourner que le "représentant" dans les items, et mettre les infos ("▸ 4 articles") dans metadata pour le front.

### 5. Tests E2E (Obligatoires)
- Écrire des **tests d'intégration** (dans `tests/`) qui bootent une base de test, créent un User, postent un topic, mockent l'API Mistral, puis simulent un call `GET /feed` pour valider que le score de l'article ciblé est bien boosté, et qu'il est clusterisé si ≥3 articles de ce slug parent existent.

## 🛑 Guardrails
1. **Pas de `cat` dans le shell**. Utilise python/pytest pour les assertions.
2. Ne modifie les fichiers existants de `ScoringEngine` qu'avec une grande prudence, les tests actuels doivent continuer de passer.
3. Toujours faire tes modifications par étapes courtes, tester (`pytest tests/test_...`), et commit.

**Action immédiate :** Lis le `11.custom-topics.story.md` et commence par créer le modèle SQLAlchemy.
