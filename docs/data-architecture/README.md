# Data Architecture — Facteur

> Point d'entrée pour comprendre l'architecture data de Facteur.
> Destiné aux ingénieurs data/backend rejoignant le projet.

## Qu'est-ce que Facteur ?

Facteur est une app mobile de **digest quotidien** : chaque matin à 8h, l'utilisateur reçoit 5-7 articles personnalisés. L'objectif produit est un "moment de fermeture" — l'utilisateur termine son digest en 2-4 minutes et se sent informé.

Du point de vue data, cela implique :
1. **Ingérer** des flux RSS/Atom/YouTube/Podcast en continu
2. **Classifier** chaque article (51 topics, sérénité) via LLM (Mistral API)
3. **Scorer** les articles par utilisateur (pertinence, source, fraîcheur, qualité)
4. **Générer** un digest quotidien personnalisé
5. **Apprendre** des interactions utilisateur (likes, bookmarks, dismisses)

## Stack Data

| Composant | Technologie | Rôle |
|-----------|------------|------|
| Base de données | PostgreSQL 15 (Supabase) | Stockage principal, JSONB, ARRAY |
| ORM | SQLAlchemy 2.0 | 20+ tables, mapped columns |
| Migrations | Alembic (47 fichiers) | Tracking DDL, exécution manuelle via Supabase SQL Editor |
| Classification | Mistral API (mistral-small-latest) | Tagging topics + sérénité, ~3000 articles/h |
| Extraction | trafilatura + readability-lxml | Contenu full-text pour lecture in-app |
| Scheduler | APScheduler (AsyncIO) | 4 jobs cron + 1 worker continu |
| Logging | structlog | JSON structuré |
| Monitoring | Sentry | Exception tracking |

## Documentation

| Document | Contenu |
|----------|---------|
| [Database Schema](database-schema.md) | Diagramme ER complet, 20+ tables par domaine |
| [Data Pipeline](data-pipeline.md) | Flux end-to-end : ingestion → classification → digest |
| [Recommendation Engine](recommendation-engine.md) | Scoring v2 (4 piliers), signaux d'apprentissage, taxonomie |
| [Scheduled Jobs](scheduled-jobs.md) | Jobs background, schedules, workers |

## Fichiers clés du code

```
packages/api/app/
├── models/                    # 17 fichiers SQLAlchemy (source de vérité du schéma)
├── services/
│   ├── recommendation/
│   │   └── scoring_config.py  # Tous les poids de l'algorithme
│   ├── ml/
│   │   ├── classification_service.py   # Mistral API classification
│   │   └── topic_theme_mapper.py       # 51 topics → 9 thèmes
│   ├── digest_service.py      # Génération digest quotidien
│   ├── recommendation_service.py       # Moteur de scoring
│   └── sync_service.py        # Ingestion RSS
├── workers/
│   ├── scheduler.py           # Orchestration des jobs
│   ├── rss_sync.py            # Worker RSS
│   ├── classification_worker.py        # Worker classification ML
│   └── storage_cleanup.py     # Nettoyage rétention
└── config.py                  # Variables d'environnement
```
