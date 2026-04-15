# PR #402 — Smart search pipeline backend (PR 1/3)

Branche : `claude/smart-search-pr1-backend` → `main`
Commit : `9dcb80ac` feat(sources): smart search pipeline with Brave + Mistral fallback
16 fichiers, +1559 lignes

---

## Quoi

Pipeline de recherche intelligente multi-sources pour l'ajout de source. 3 nouveaux endpoints (`POST /smart-search`, `GET /by-theme/{slug}`, `GET /themes-followed`), cache Postgres 24h, et providers pour Brave Search, Reddit JSON, et Google News RSS. Mistral-small en fallback uniquement si < 3 résultats après les couches gratuites.

## Pourquoi

La recherche actuelle est un simple ILIKE sur `Source.name`/`Source.url` du catalogue curé. Si l'utilisateur tape un nom approximatif ("stratechery", "lenny newsletter") ou un sujet vague, il n'obtient rien et doit deviner l'URL exacte. Ce pipeline comble la zone grise entre "je connais l'URL exacte" et "c'est dans le catalogue curé".

## Fichiers modifiés

### Backend — Nouveaux fichiers
- `app/services/search/smart_source_search.py` — Orchestrateur du pipeline cascadé (548 lignes, le fichier central)
- `app/services/search/cache.py` — Cache Postgres 24h avec SHA-256 normalization
- `app/services/search/providers/brave.py` — Client Brave Search API (free tier)
- `app/services/search/providers/reddit_search.py` — Client Reddit JSON search
- `app/services/search/providers/google_news.py` — Extraction domaines depuis Google News RSS
- `alembic/versions/ss01_create_source_search_cache.py` — Migration table `source_search_cache`

### Backend — Fichiers modifiés
- `app/config.py` — +3 settings : `brave_api_key`, `brave_monthly_cap`, `mistral_monthly_cap`
- `app/routers/sources.py` — +3 endpoints + helper `_source_to_response()` + mapping `THEME_LABELS`
- `app/schemas/source.py` — +7 schemas Pydantic (SmartSearch*, Theme*)

### Tests (31 tests)
- `tests/services/search/test_smart_source_search.py` — 20 tests (classify, score, normalize, dedup)
- `tests/services/search/providers/test_brave.py` — 6 tests (mock HTTP, 429, timeout)
- `tests/services/search/providers/test_reddit_search.py` — 5 tests (mock JSON, errors)

## Zones à risque

1. **`smart_source_search.py`** — C'est le coeur du pipeline (548 lignes). La logique de court-circuit (≥3 résultats → stop) et l'ordre des couches déterminent le coût et la latence. Une erreur ici pourrait brûler le budget Brave/Mistral inutilement.

2. **Rate limiting en mémoire** — Les compteurs `_brave_calls_month`, `_mistral_calls_month`, `_user_daily_counts` sont des globales qui se reset au restart. Ce n'est pas idéal pour un déploiement multi-instance mais acceptable pour le volume actuel (100-200 users). Si ça devient un problème → migrer vers Postgres ou Redis.

3. **`by-theme/{slug}` fallback communauté** — Le fallback fait un `JOIN user_sources + GROUP BY + ORDER BY count`. Sur un gros volume de `user_sources`, ça pourrait être lent. À surveiller.

## Points d'attention pour le reviewer

1. **Pipeline order** — L'ordre catalog → YouTube → Reddit → Brave → Google News → Mistral est critique. Les couches gratuites passent en premier, Brave (limité à 1800/mois) et Mistral (2000/mois) en dernier. Vérifier que les short-circuits (`MIN_RESULTS_FOR_SHORTCIRCUIT = 3`) sont bien placés.

2. **`_compute_score`** — Le scoring composite (confidence × 0.40 + popularity × 0.25 + freshness × 0.15 + type_match × 0.10 + theme_affinity × 0.10) est codé en dur. Les poids sont arbitraires mais raisonnables. On ajustera en v1.1 si le ranking est mauvais en pratique.

3. **Feed validation séquentielle** — Chaque URL trouvée par Brave/Google News/Mistral passe par `RSSParser.detect()` (HTTP + feedparser). Pour Brave, on valide les top 5 URLs séquentiellement. On pourrait paralléliser avec `asyncio.gather()` plus tard si la latence P95 dépasse 4s.

4. **Cache SQL brut** — Le cache utilise `sa.text()` avec des requêtes SQL brutes plutôt qu'un modèle SQLAlchemy. C'est un choix délibéré pour éviter de polluer le namespace des models avec une table utilitaire. Le reviewer pourrait préférer un vrai modèle.

5. **`_source_to_response()` dans le router** — Helper local dans `sources.py` qui construit un `SourceResponse` sans contexte user (pas de `is_trusted`, `is_muted`, `priority_multiplier`). C'est suffisant pour `by-theme` et `themes-followed` car ces endpoints sont exploratoires (découverte, pas gestion d'abonnement).

6. **`datetime.now(datetime.UTC)`** — Les fichiers utilisent `datetime.now(datetime.UTC)` (linter auto-fix) au lieu de `datetime.now(timezone.utc)`. Les deux sont équivalents en Python 3.12+.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **`POST /sources/detect`** — L'endpoint existant est inchangé. `smart-search` est un nouvel endpoint parallèle, pas un remplacement.
- **`rss_parser.py`** — Réutilisé tel quel (`RSSParser.detect()`, `_resolve_youtube_channel_id()`), aucune modification.
- **`llm_client.py`** — Réutilisé tel quel (`chat_json()` avec `mistral-small-latest`), aucune modification.
- **`source_service.py`** — Non modifié. Le pattern ILIKE du catalog est re-implémenté inline dans l'orchestrateur (même logique, intégrée au pipeline).
- **Aucun changement mobile** — C'est PR 1/3, backend only.

## Comment tester

### Unit tests
```bash
cd packages/api
SKIP_STARTUP_CHECKS=true .venv/bin/python -m pytest tests/services/search/ -v
# 31 tests, ~1s
```

### Alembic
```bash
SKIP_STARTUP_CHECKS=true .venv/bin/python -m alembic heads
# Doit afficher: ss01_search_cache (head) — 1 seule head
```

### Smoke test (après déploiement staging + migration)
```bash
# Smart search
curl -X POST https://api-staging/api/sources/smart-search \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "lenny newsletter"}'

# By theme
curl https://api-staging/api/sources/by-theme/tech \
  -H "Authorization: Bearer $TOKEN"

# Themes followed
curl https://api-staging/api/sources/themes-followed \
  -H "Authorization: Bearer $TOKEN"
```

### Pré-requis avant déploiement
- `BRAVE_API_KEY` doit être définie dans Railway (staging + prod)
- Migration SQL `ss01_search_cache` exécutée manuellement via Supabase SQL Editor (JAMAIS Railway)
