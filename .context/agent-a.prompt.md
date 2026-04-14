# 🤖 Agent A — PR 1 : Backend smart-search

Tu es dev backend Python sur le projet Facteur (FastAPI + PostgreSQL/Supabase + Railway).
Repo : /home/user/facteur — branch de travail : claude/smart-search-pr1-backend (à créer depuis main).

## MISSION
Implémenter le backend de la story "Smart Source Search" (PR 1 sur 3) :
pipeline de recherche multi-sources + endpoints + cache + instrumentation.

## LECTURES OBLIGATOIRES (dans cet ordre)
1. CLAUDE.md — règles absolues (branche main, Python 3.12, Alembic manuel, etc.)
2. docs/stories/core/12.1.smart-source-search.story.md — contexte + AC
3. docs/stories/core/12.1.smart-source-search.tech.md — spec technique complète
4. docs/stories/core/12.1.smart-source-search.prs.md — section "PR 1 — Backend"
5. packages/api/app/services/rss_parser.py — fonction detect_source() à réutiliser
6. packages/api/services/editorial/llm_client.py — EditorialLLMClient.chat_json() pour Mistral
7. packages/api/app/services/perspective_service.py:300-400 — Google News RSS
8. packages/api/app/models/source.py — Source.is_curated
9. packages/api/app/routers/sources.py — endpoints existants

## SCOPE
- Migration Alembic source_search_cache (SQL manuelle via Supabase SQL Editor)
- Services packages/api/app/services/search/ :
  - providers/brave.py
  - providers/reddit_search.py
  - providers/google_news_search.py (extract desde perspective_service)
  - cache.py (Postgres, TTL 24h)
  - smart_source_search.py (pipeline orchestrator)
- 3 endpoints dans routers/sources.py :
  - POST /api/sources/smart-search
  - GET /api/sources/by-theme/{slug}
  - GET /api/sources/themes-followed
- Config brave_api_key + plafonds dans app/config.py
- .env.example : BRAVE_API_KEY=
- Instrumentation + logs
- Tests ≥ 80% couverture

## HORS SCOPE
- AUCUN changement mobile
- AUCUNE modification rss_parser.py ni llm_client.py (réutilisation seulement)
- PAS de curation automatique

## CONTRAINTES CRITIQUES
- Python 3.12 : list[], dict[], X | None natifs (jamais from typing import)
- Alembic 1 head uniquement — NE PAS exécuter sur Railway
- Mistral appelé UNIQUEMENT si catalog + YouTube + Reddit + Brave + Google News < 3 résultats
- Plafonds : Brave 1800/mois, Mistral 2000 calls/mois, 30 req/jour/user
- Cache 24h : clé = sha256(lowercase.trim.collapse(query))

## WORKFLOW
1. CODE : implémente selon tech.md
2. TESTS : pytest -v, alembic heads (1 seule)
3. PR vers main (--base main obligatoire)
4. STOP et notifie l'utilisateur : "PR créée #XX. Migration SQL manuelle + déploiement staging requis avant Agent B"

## NE PAS faire
- Ne pas merger toi-même
- Ne pas exécuter alembic sur Railway
- Ne pas toucher au mobile
