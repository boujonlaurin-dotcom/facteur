# Handoff Frontend — Epic 11 : Custom Topics (Partie 1 - Data & Logic)

Tu es un agent d'implémentation Frontend Flutter/Riverpod. Ta mission est d'implémenter la **logique métier, les modèles de données et l'intégration API** de l'Epic "Custom Topics", tout en créant une base saine de tests unitaires/mocks.

## Contexte
La feature "Custom Topics" permet aux utilisateurs de sélectionner des sujets précis (ex: "Voiture électrique") et de configurer leur priorité via un curseur 3 crans (×0.5 / ×1.0 / ×2.0). 
Pour limiter la complexité du contexte IA, cette tâche est scindée en deux. **Ceci est la Partie 1 (Logique seule).** Un autre agent fera l'UI.

**Stack :**
- Flutter / Riverpod / Freezed
- Dio / Retrofit (ou client API maison)
- Flutter Test (Mocks)

**Documents à lire absolument :**
1. `docs/stories/core/11.custom-topics.story.md` (Spécifications fonctionnelles)
2. `docs/stories/core/11.custom-topics/convergence.md` (Décisions récentes d'UX)

---

## 📋 Tâches (Plan de travail)

### 1. Modèles de données (Freezed)
- Créer ou mettre à jour le modèle `UserTopicProfile` (id, user_id, topic_name, slug_parent, keywords, priority_multiplier).
- Mettre à jour `FeedArticle` (ou équivalent) pour y inclure le support des clusters : `cluster_topic` (slug ou null), `cluster_hidden_count` (int), `cluster_hidden_articles` (List).

### 2. Repositories et API Client
- Implémenter `TopicRepository` avec les appels réseau :
  - `Future<List<UserTopicProfile>> getFollowedTopics()`
  - `Future<UserTopicProfile> followTopic(String name)`
  - `Future<UserTopicProfile> updateTopicPriority(String id, double priorityMultiplier)`
  - `Future<void> unfollowTopic(String id)`
  - `Future<List<String>> getSuggestedTopics(String themeSlug)`
- Mettre à jour `FeedRepository` pour qu'il gère les clusters dans la payload JSON retournée par le `/feed`.

### 3. Providers Riverpod (State Management)
- Créer `customTopicsProvider` (AsyncNotifier) pour gérer la liste des topics suivis, avec des méthodes mutables (add, update, remove) effectuant un optimistic update de l'UI.
- Créer `topicSuggestionsProvider(String theme)` pour fetch les suggestions in-situ.

### 4. Tests Logiciels
- Créer `topic_repository_test.dart` avec des mocks réseau clairs.
- Créer `custom_topics_provider_test.dart` pour vérifier que les updates optimistes fonctionnent et rollback en cas d'erreur HTTP.

## 🛑 Guardrails
1. Ne **code pas l'UI finale** (les écrans Feed, Explorer, Settings). Cet handoff s'arrête strictement à la coche des données et state Riverpod.
2. Utilise `json_serializable` et `freezed` selon les standards du projet.
3. Vérifie que tes tests unitaires passent tous via `flutter test` avant de handoff.
