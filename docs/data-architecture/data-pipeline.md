# Data Pipeline

> Source de vérité : `packages/api/app/workers/scheduler.py`, `packages/api/app/services/sync_service.py`

## Vue d'ensemble

> **Important** : il y a deux surfaces utilisateur distinctes avec deux architectures différentes.
> - **Feed** (`GET /api/feed`) — computation **temps réel** à chaque requête. C'est la surface principale aujourd'hui.
> - **Digest** (`GET /api/digest`) — généré une fois par jour à 08:00 par un job batch. En cours de refonte.

```mermaid
flowchart TB
    subgraph INGESTION["① Ingestion RSS (every N min)"]
        S[Sources actives<br>RSS / Atom / YouTube / Podcast] -->|httpx async| F[feedparser<br>thread pool]
        F -->|max 50 entries/source| PW[Paywall<br>detection]
        PW -->|upsert| DB_C[(contents)]
        PW -->|enqueue| Q[(classification_queue)]
    end

    subgraph CLASSIFICATION["② Classification ML (continu)"]
        Q -->|batch 5, SELECT FOR UPDATE SKIP LOCKED| W[Classification Worker]
        W -->|title + description + source| M[Mistral API<br>mistral-small-latest]
        M -->|topics + is_serene| DB_C
        M -->|theme inference| TM[topic_theme_mapper]
        TM -->|theme slug| DB_C
    end

    subgraph ENRICHMENT["③ Enrichissement (inline)"]
        DB_C -->|on-demand| TR[trafilatura +<br>readability-lxml]
        TR -->|html_content +<br>content_quality| DB_C
    end

    subgraph DIGEST["④ Digest Generation (08:00 Paris)"]
        DB_C --> CAND[Candidate Selection<br>7 derniers jours]
        CAND -->|filter: followed sources,<br>interests, exclude seen/hidden| CLUSTER[Topic Clustering<br>Jaccard ≥ 0.45]
        CLUSTER --> SCORE[Scoring v2<br>4 piliers pondérés]
        SCORE --> SELECT[Topic Selector<br>N topics = weekly_goal]
        SELECT -->|5-7 articles| DG[(daily_digest)]
    end

    subgraph CLEANUP["⑤ Storage Cleanup (03:00 Paris)"]
        DB_C -->|older than N days| DEL[DELETE]
    end

    style INGESTION fill:#e8f4f8,stroke:#2196F3
    style CLASSIFICATION fill:#fff3e0,stroke:#FF9800
    style ENRICHMENT fill:#f3e5f5,stroke:#9C27B0
    style DIGEST fill:#e8f5e9,stroke:#4CAF50
    style CLEANUP fill:#fce4ec,stroke:#f44336
```

---

## ① Ingestion RSS

**Worker** : `workers/rss_sync.py` → `SyncService`
**Schedule** : `IntervalTrigger(minutes=settings.rss_sync_interval_minutes)` (default: 30 min)

```mermaid
sequenceDiagram
    participant Scheduler
    participant SyncService
    participant Source DB
    participant HTTP
    participant Parser
    participant Content DB
    participant Queue

    Scheduler->>SyncService: sync_all_sources()
    SyncService->>Source DB: SELECT sources WHERE is_active
    loop Pour chaque source (semaphore=5)
        SyncService->>HTTP: GET feed_url (httpx async)
        HTTP-->>SyncService: XML/HTML response
        SyncService->>Parser: feedparser (thread pool)
        Parser-->>SyncService: entries (max 50)
        loop Pour chaque entry
            SyncService->>Content DB: CHECK guid exists
            alt Nouveau contenu
                SyncService->>Content DB: INSERT content
                SyncService->>Queue: INSERT classification_queue (status=pending)
            end
        end
        SyncService->>Source DB: UPDATE last_synced_at
    end
```

### Détection de feed

Le `RSSParser` suit une cascade de 5 stratégies :

| Étape | Stratégie | Exemple |
|-------|-----------|---------|
| 0 | Transforms plateforme | Substack → `/feed`, Medium → `/feed/publication` |
| 1 | Parsing direct de l'URL | URL pointe directement vers un feed XML |
| 2 | Auto-discovery HTML | `<link rel="alternate" type="application/rss+xml">` |
| 3 | Scraping `<a href>` | Liens ressemblant à des feeds dans la page |
| 4 | Suffixes fallback | `/feed`, `/rss`, `/atom.xml`, `/feed.xml` |

**Anti-bot** : Fallback `curl-cffi` avec TLS fingerprinting pour bypass Cloudflare.

---

## ② Classification ML

**Worker** : `workers/classification_worker.py`
**Mode** : Boucle continue (check toutes les 10 secondes)

```mermaid
flowchart LR
    Q[(classification_queue<br>status=pending)] -->|SELECT FOR UPDATE<br>SKIP LOCKED<br>batch=5| W[Worker]
    W -->|title + description<br>+ source_name| API[Mistral API]
    API -->|JSON response| P[Parse]
    P -->|topics: list str| C[(contents.topics)]
    P -->|is_serene: bool| C
    P -->|infer_theme_from_topics| C2[(contents.theme)]
    W -->|on success| Q2[status=completed]
    W -->|on failure, retry<3| Q3[status=pending<br>retry_count++]
    W -->|on failure, retry≥3| Q4[status=failed]
```

### Taxonomie

**51 topics** classifiés par le LLM, regroupés en **9 thèmes** :

| Thème | Topics |
|-------|--------|
| `tech` | ai, tech, cybersecurity, gaming, privacy |
| `science` | space, science |
| `politics` | politics |
| `economy` | economy, startups, finance, realestate, entrepreneurship, marketing |
| `society` | work, education, health, justice, immigration, inequality, feminism, lgbtq, religion, wellness, family, relationships, factcheck |
| `environment` | climate, environment, energy, biodiversity, agriculture, food |
| `culture` | cinema, music, literature, art, media, fashion, design, travel, gastronomy, history, philosophy |
| `international` | geopolitics, europe, usa, africa, asia, middleeast |
| `sport` | sport |

Le mapping complet est dans `packages/api/app/services/ml/topic_theme_mapper.py`.

### Output classification

Chaque article reçoit :
- `topics` : ARRAY de 1-3 slugs (par score ML décroissant)
- `theme` : slug dérivé du `topics[0]` via le mapper
- `is_serene` : booléen (article positif/constructif vs conflit/catastrophe)

---

## ③ Enrichissement contenu

**Service** : `ContentExtractor` (inline, déclenché à la demande)

| Étape | Outil | Output |
|-------|-------|--------|
| Extraction full-text | trafilatura + readability-lxml | `html_content` |
| Qualité | Heuristique longueur | `content_quality` = "full" / "partial" / "none" |
| Anti-retry | Timestamp | `extraction_attempted_at` |

---

## ④ Digest Generation

**Job** : `jobs/digest_generation_job.py` → `DigestService`
**Schedule** : `CronTrigger(hour=8, minute=0, timezone=Europe/Paris)`

```mermaid
flowchart TB
    START[Pour chaque user actif] --> CAND[Candidate Selection]
    CAND -->|"contents des 7 derniers jours<br>filtrés par sources suivies<br>+ intérêts + excl. seen/hidden"| POOL[Pool ~100-500 articles]
    POOL --> CLUSTER[Clustering Universel<br>Jaccard ≥ 0.45 sur tokens titre]
    CLUSTER --> TOPIC_SCORE[Score par cluster/topic]

    TOPIC_SCORE --> |"followed_source_bonus: +40<br>trending_bonus: +50<br>une_bonus: +35<br>theme_match: +45"| TOPIC_SELECT[Sélection N topics<br>N = weekly_goal, 3-7]

    TOPIC_SELECT --> ART_SELECT[Sélection articles par topic<br>max 3/topic, diversité sources]
    ART_SELECT --> SCORE_V2[Scoring v2 piliers<br>+ Gumbel noise 0.08]
    SCORE_V2 --> DIGEST[(daily_digest<br>5-7 articles JSONB)]

    style CLUSTER fill:#fff3e0
    style SCORE_V2 fill:#e8f5e9
```

### Completion tracking

```mermaid
sequenceDiagram
    participant User
    participant API
    participant DigestCompletion
    participant Streaks

    User->>API: Action sur article (read/save/dismiss)
    API->>DigestCompletion: UPDATE counters
    Note over DigestCompletion: articles_read++<br>ou articles_saved++<br>ou articles_dismissed++
    alt 5 actions sur 7 articles
        API->>DigestCompletion: SET completed_at = now()
        API->>Streaks: UPDATE closure_streak++
    end
```

---

## ⑤ Feed (on-demand — surface principale)

**Router** : `routers/feed.py` → `RecommendationService.get_feed()`
**Déclenchement** : À chaque ouverture du feed par l'utilisateur (pas de batch)

> Le feed n'a **pas de table dédiée**. C'est une requête scorée en temps réel sur `contents` + `user_content_status` + profil utilisateur.

```mermaid
sequenceDiagram
    participant App as App Flutter
    participant API as GET /api/feed
    participant Reco as RecommendationService
    participant DB as PostgreSQL

    App->>API: GET /api/feed?limit=20&mode=recent&theme=tech
    API->>Reco: get_feed(user_id, filters...)
    Reco->>DB: SELECT contents + user_content_status + user_sources
    Reco->>DB: SELECT user_interests + user_subtopics + user_personalization
    Note over Reco: Scoring v2 (4 piliers)<br>+ pénalités impressions<br>+ Gumbel noise 0.15
    Reco-->>API: articles triés par score
    API->>Reco: build_clusters(custom_topics)
    API-->>App: FeedResponse {items, clusters, pagination}

    App->>API: POST /api/feed/refresh {content_ids: [...]}
    API->>DB: UPSERT user_content_status.last_impressed_at = now()
    Note over DB: Déclenche le malus<br>d'impression au prochain scoring
```

### Filtres disponibles

| Paramètre | Valeurs | Effet |
|-----------|---------|-------|
| `mode` | `RECENT`, `INSPIRATION`, `PERSPECTIVES`, `DEEP_DIVE` | Modifie les filtres de scoring |
| `theme` | `tech`, `society`, `environment`... | Filtre par thème macro |
| `type` | `article`, `podcast`, `youtube`, `reddit` | Filtre par type de contenu |
| `saved` | `true` | Uniquement les articles bookmarkés |
| `has_note` | `true` | Uniquement les articles annotés |
| `source_id` | UUID | Filtre par source |

### Ce que le feed écrit en base

Chaque interaction utilisateur dans le feed met à jour `user_content_status` :

| Action | Colonne mise à jour | Impact scoring suivant |
|--------|---------------------|----------------------|
| Scroll sans cliquer | `last_impressed_at` | Malus temporel (-100 à -20 pts) |
| "Déjà vu" manuel | `manually_impressed = true` | Malus permanent -120 pts |
| Ouvrir un article | `status = seen`, `seen_at` | Article sort du pool "nouveau" |
| Lire jusqu'au bout | `status = consumed`, `time_spent_seconds` | +0.03 sur `user_subtopics.weight` |
| Like | `is_liked = true` | +0.15 sur `user_subtopics.weight` |
| Bookmark | `is_saved = true` | +0.05 sur `user_subtopics.weight` |
| Dismiss | `is_hidden = true` | -0.10 sur `user_subtopics.weight` |

---

## ⑥ Storage Cleanup

**Worker** : `workers/storage_cleanup.py`
**Schedule** : `CronTrigger(hour=3, minute=0, timezone=Europe/Paris)`

Supprime les articles plus anciens que `RSS_RETENTION_DAYS` (default: 20 jours).
Les `user_content_status` associés sont supprimés en cascade (FK `ON DELETE CASCADE`).

---

## Flux de données simplifié

```
RSS Feeds ──[30min]──> contents ──[continu]──> classification (topics, theme, serene)
                           │
                           ├──[on-demand]──> extraction (html_content)
                           │
                           ├──[temps réel]──> FEED ──> user interactions ──┐
                           │                                                │
                           └──[08:00]──> DIGEST ──> user interactions ──┐  │
                                                                         ↓  ↓
                                                              user_content_status
                                                                         │
                                                              weight learning (subtopics)
                                                                         │
                                                              feedback loop (scoring)
```

> Le **feed** est la boucle la plus rapide et la plus fréquente. C'est lui qui génère la majorité des données d'apprentissage. Le **digest** est une sélection quotidienne statique — la boucle la plus lente.
