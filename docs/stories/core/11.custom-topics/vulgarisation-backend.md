# Epic 11 — Vulgarisation Backend : Custom Topics

**Pour :** Ingé data junior
**Objectif :** Comprendre les choix techniques backend de l'Epic 11 sans jargon inutile

---

## 🎯 Le problème en une phrase

Aujourd'hui, le feed est trié par des "thèmes macro" (Tech, Éco, Société…). L'utilisateur ne peut pas dire "je veux voir plus d'articles sur l'IA" de façon fine. On veut lui donner ce pouvoir.

---

## 1. Le modèle de données : `UserTopicProfile`

### Qu'est-ce que c'est ?

Une **nouvelle table** en base de données qui stocke les sujets personnalisés de chaque utilisateur. C'est le cœur de la feature.

### Structure simplifiée

```
UserTopicProfile
├── user_id          → Quel utilisateur
├── topic_name       → "Intelligence Artificielle" (texte libre)
├── slug_parent      → "ai" (parmi les 50 slugs Mistral existants)
├── keywords[]       → ["GPT", "LLM", "OpenAI", "machine learning", ...]
├── intent_desc      → "Actualités et avancées en IA" (description sémantique)
├── composite_score  → -100 à +100 (synthèse de tous les signaux)
├── priority_mult    → 0.25 à 2.5 (ce que l'utilisateur règle avec le slider)
└── source           → "explicit" ou "implicit" (comment le topic a été créé)
```

### Pourquoi un "score composite" ?

Avant, on avait des signaux partout : likes dans une table, bookmarks dans une autre, temps de lecture dans une troisième… Le `UserTopicProfile` **unifie tout ça** en un seul score. C'est plus simple à requêter et plus facile à débugger.

**Formule simplifiée :**
```
composite_score = (like_signal × 3) + (bookmark_signal × 1) + (read_time_signal × 2) + (explicit_follow × 5)
```

Plus le score est haut, plus l'algo considère que l'utilisateur aime ce sujet.

---

## 2. Le LLM One-Shot : Comment on catégorise un sujet libre

### Le problème

L'utilisateur tape "Mobilité douce". Comment notre système comprend-il de quoi il s'agit ?

### La solution

On fait **un seul appel** à un LLM (type Mistral/GPT) au moment de la **création** du topic. Pas à chaque chargement de feed — ça serait trop lent et trop cher.

### Ce que le LLM reçoit (prompt)

```
L'utilisateur veut suivre le sujet : "Mobilité douce"
Voici les 50 catégories possibles : [ai, climate, economy, ...]
Retourne :
1. La catégorie parent la plus proche
2. 5-10 mots-clés de recherche associés
3. Une description d'intention (1 phrase)
Format : JSON
```

### Ce que le LLM retourne

```json
{
  "slug_parent": "climate",
  "keywords": ["vélo", "transport en commun", "urbanisme", "ZFE", "mobilité durable", "trottinette"],
  "intent_description": "Suivi des actualités sur les modes de transport doux et la mobilité urbaine"
}
```

### Pourquoi "one-shot" et pas en temps réel ?

| Approche | Coût | Latence | Risque |
|----------|------|---------|--------|
| LLM à chaque requête feed | 💰💰💰 | 2-3s par appel | Timeout, incohérence |
| **LLM one-shot à la création** | 💰 | 1-2s une seule fois | Quasi nul |
| Pas de LLM (matching texte) | 0 | 0 | Mauvaise qualité de matching |

Le one-shot est le meilleur rapport qualité/coût. On paye 1 appel par topic créé (quelques centimes), et les keywords sont stockés en base pour un matching rapide ensuite.

---

## 3. Le matching : Comment un article "matche" un topic

### Court terme (MVP)

On compare les **keywords du topic** avec les **topics de l'article** (`content.topics[]`).

```python
def article_matches_topic(article, user_topic):
    # Les topics de l'article (ajoutés par le classifieur Mistral existant)
    article_topics = set(article.topics)
    
    # Le slug parent du custom topic
    if user_topic.slug_parent in article_topics:
        return True
    
    # Les keywords dans le titre ou la description
    for keyword in user_topic.keywords:
        if keyword.lower() in article.title.lower():
            return True
        if keyword.lower() in (article.description or "").lower():
            return True
    
    return False
```

C'est simple, rapide, et suffisant pour le MVP.

### Long terme (V2+)

On passera aux **embeddings vectoriels** : chaque article et chaque topic seront représentés par un vecteur numérique, et on calculera une **similarité cosinus** entre eux. C'est plus précis mais demande une infra dédiée (pgvector ou similaire).

---

## 4. L'Explicit Boost : Comment le slider de priorité change le feed

### Le scoring actuel (simplifié)

```
score_article = (match_thème × 0.35) + (fraîcheur × 0.25) + (format × 0.20) + (source × 0.15)
```

### Ce qu'on ajoute

Un **multiplicateur** basé sur la priorité que l'utilisateur a choisie via le slider :

```
score_final = score_article + (topic_bonus × priority_multiplier)

où :
- topic_bonus = 10 points si l'article matche un custom topic
- priority_multiplier = le cran du slider (0.25 / 0.6 / 1.0 / 1.5 / 2.5)
```

**Exemple concret :**
- Article sur l'IA, score de base = 65 points
- L'utilisateur suit "IA" au cran 4 (Prioritaire)
- Bonus = 10 × 1.5 = +15 points
- Score final = 80 → il monte dans le feed 📈

---

## 5. Le clustering : Comment on regroupe les articles

### Le problème

Si un utilisateur suit "IA" et qu'il y a 8 articles sur l'IA aujourd'hui, le feed serait dominé par un seul sujet. Pas cool.

### La solution

Le backend **regroupe** les articles du même topic en "clusters" :

```python
def build_clusters(feed_articles, min_articles=3, max_clusters=3):
    # Compter les articles par topic
    topic_counts = defaultdict(list)
    for article in feed_articles:
        for topic in article.matched_topics:
            topic_counts[topic].append(article)
    
    clusters = []
    for topic, articles in topic_counts.items():
        if len(articles) >= min_articles:
            # Garder le best-scored comme "représentant"
            representative = max(articles, key=lambda a: a.score)
            others = [a for a in articles if a != representative]
            
            clusters.append({
                "topic": topic,
                "representative": representative,
                "hidden_articles": others,
                "count": len(others)
            })
    
    # Max 3 clusters par page
    return sorted(clusters, key=lambda c: c["count"], reverse=True)[:max_clusters]
```

### Ce que le frontend reçoit

```json
{
  "items": [...],
  "clusters": [
    {
      "topic_slug": "ai",
      "topic_name": "Intelligence Artificielle",
      "representative_id": "uuid-article-1",
      "hidden_count": 4,
      "hidden_ids": ["uuid-2", "uuid-3", "uuid-4", "uuid-5"]
    }
  ]
}
```

Le frontend utilise ces métadonnées pour afficher la chip "▸ 4 autres articles sur l'IA" et masquer les articles regroupés.

---

## 6. L'endpoint API : `/personalization/topics`

### CRUD classique

| Méthode | Route | Action |
|---------|-------|--------|
| `GET` | `/personalization/topics` | Liste les topics de l'utilisateur |
| `POST` | `/personalization/topics` | Crée un topic (déclenche le LLM) |
| `PUT` | `/personalization/topics/{id}` | Modifie la priorité (slider) |
| `DELETE` | `/personalization/topics/{id}` | Supprime un topic |

### Exemple de création

**Request :**
```json
POST /personalization/topics
{
  "name": "Mobilité douce"
}
```

**Traitement backend :**
1. Reçoit le nom libre
2. Appelle le LLM one-shot → obtient slug + keywords + intent
3. Crée l'entrée `UserTopicProfile` en base
4. Retourne le topic complet au frontend

**Response :**
```json
{
  "id": "uuid",
  "name": "Mobilité douce",
  "slug_parent": "climate",
  "keywords": ["vélo", "transport en commun", ...],
  "priority_multiplier": 1.0,
  "composite_score": 0,
  "created_at": "2026-03-02T..."
}
```

---

## 7. Résumé visuel du flux de données

```
┌──────────────────────────────────────────────────────┐
│                    CRÉATION D'UN TOPIC                │
│                                                      │
│  User tape "IA"  ──→  API POST  ──→  LLM one-shot   │
│                                          │            │
│                                     slug: "ai"        │
│                                     keywords: [...]   │
│                                          │            │
│                                     INSERT DB         │
│                                     UserTopicProfile  │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│                    CHARGEMENT DU FEED                  │
│                                                      │
│  GET /feed  ──→  Fetch articles  ──→  Score chaque   │
│                      │                   article      │
│                      │                     │          │
│                  Fetch UserTopicProfiles    │          │
│                      │                     │          │
│                      └──→ Explicit Boost   │          │
│                           (si match)       │          │
│                                            │          │
│                                       Clustering      │
│                                       (≥3 articles)   │
│                                            │          │
│                                       Response JSON   │
│                                       avec clusters   │
└──────────────────────────────────────────────────────┘
```

---

## 8. Questions Techniques (Itération v2)

### 1. Robustesse du lien Topics ↔ Sources
**La solution :** Les sources externes (curées ou non) possèdent déjà un champ `granular_topics` (array de strings) ajouté lors des précédentes Epics. Le worker Mistral (`classification_worker.py`) utilise déjà ce champ en **fallback** propre : s'il n'arrive pas à classifier un article, il récupère les `granular_topics` de la source de l'article, et les **filtre stricto sensu** contre notre `VALID_TOPIC_SLUGS`. On est donc robuste et synchronisé. L'endpoint `/personalization/suggestions` utilisera ce même mapping natif.

### 2. Évolution de la Taxonomie Mistral
**La solution :** Contrairement au hardcoding mobile initial, l'API gère la taxonomie de manière centralisée dans `classification_service.py` (`VALID_TOPIC_SLUGS`) et `topic_theme_mapper.py` (`TOPIC_TO_THEME`).
- Le thème "Sport" **existe déjà** dans notre mapping backend !
- Les ajustements ("Robotique", "Physique", "Art", etc.) nécessiteront simplement une PR pour modifier le dictionnaire `VALID_TOPIC_SLUGS` et `SLUG_TO_LABEL` du backend. L'API Mistral s'adaptera immédiatement car ces labels lui sont passés dans le prompt système en temps réel.

### 3. Rééquilibrage du Score de Fraîcheur (Recency)
**L'anomalie :** Actuellement, le score de base de fraîcheur (formula V1) max à **30 points** pour un article de la dernière heure, et descend à ~2 points pour un article vieux de 15 jours. Mais à l'inverse, un perfect match d'intérêt rapporte **90 pts** (`TOPIC_MATCH`) + **50 pts** (`THEME_MATCH`) + **35 pts** (`TRUSTED_SOURCE`). 
**Conséquence :** La personnalisation écrase totalement la fraîcheur (175 pts vs 30 pts max). Un très vieil article d'une source ultra-suivie passera toujours devant de la fresh news.
**Action :** Lors de l'implémentation de la Phase 3, il faudra caper les bonus maximums de personnalisation, ou rehausser drastiquement le `recency_base` à ~100 dans `scoring_config.py` pour que l'actualité puisse rivaliser avec les niches, afin de régler le problème des feeds dominés par des vieux contenus.

### 4. Désynchronisation des Slugs (Matching Article ↔ Topic)
**La solution :** Nous utilisons exactement la même source de vérité. Le LLM générant les topics de l'article (`classification_worker.py`) utilise la constante `VALID_TOPIC_SLUGS` injectée dans son prompt.
Pour la création de Topics Custom (`/personalization/topics`), on fournira et validera le `slug_parent` avec cette même constante `VALID_TOPIC_SLUGS`. Impossible qu'un article soit poolé sur "tech-ai" pendant que l'utilisateur suit "ia-news". Ils utiliseront tous les deux "ai".

---

## 8. Stack technique utilisée

| Composant | Technologie | Pourquoi |
|-----------|-------------|----------|
| Table `UserTopicProfile` | PostgreSQL (Supabase) | Cohérent avec le reste de la DB |
| LLM one-shot | Mistral API (ou OpenAI fallback) | Low-cost, rapide, bon français |
| Endpoint CRUD | FastAPI + Pydantic | Validation auto, docs Swagger |
| Matching keywords | SQL LIKE + array overlap | Suffisant MVP, pas d'infra supplémentaire |
| Scoring boost | Python (service `scoring.py` existant) | Ajout d'un layer dans le pipeline existant |

---

*Document produit le 2026-03-02 dans le cadre de l'Epic 11 — Custom Topics.*
