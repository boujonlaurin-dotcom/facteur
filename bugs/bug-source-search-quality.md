# Bug — Recherche de sources : listicles SEO + observabilité cassée

**Date** : 2026-04-26
**Statut** : Fix en review (branche `boujonlaurin-dotcom/source-search-fix`)
**Impact** : Élevé — la feature "Ajouter une source" était inutilisable sur les requêtes thématiques.

## Symptômes

1. Sur une requête comme `political news`, l'écran "Ajouter une source" remontait des **listicles SEO** ("60 Best Political News RSS Feeds…") plutôt que de vraies sources.
2. La pipeline longue (Brave / Google News / Mistral) se déclenchait même sur des sources évidentes (`mediapart`, `arret sur images`).
3. La table `failed_source_attempts` était vide en prod (0 ligne) malgré 80 entrées de cache → impossible d'itérer offline.

## Cause racine

- `BraveSearchProvider.search` envoyait `f"{query} RSS feed site blog"` : la requête **demande explicitement à Google/Brave** des listes "Best of RSS". Combinée à l'absence de filtre sur `feed_url`, on retournait des articles listicles dont le titre Brave brut servait de "nom de source".
- `MIN_RESULTS_FOR_SHORTCIRCUIT = 3` exigeait 3 hits curated avant de couper Brave. Or les requêtes les plus courantes (1 source précise) tombent à 1 hit.
- Catalog ILIKE en simple substring + sans `unaccent` : `arret sur images` ratait `Arrêt sur Images`.
- Observabilité : seul `/sources/search-abandoned` (déclenché à `dispose()` mobile, swallow erreurs) écrivait dans `failed_source_attempts`. Les recherches utiles (avec ajout) n'étaient jamais loggées.

## Résolution

### Backend — `packages/api/app/services/search/`

**Localisation FR** (post-revue PO 2026-04-26)
- `BraveSearchProvider` envoie `country=fr`, `search_lang=fr`, `ui_lang=fr-FR`. Sans cela, `politis` ramenait Politis Cyprus en premier.
- `GoogleNewsProvider` extrait le publisher via `entry.source.href` (les `<link>` sont devenus des redirects opaques `news.google.com/rss/articles/CB...`). Avant : 0 host extrait sur toutes les requêtes ; après : 5 hosts/requête.

**Latence bornée**
- `FEED_DETECT_TIMEOUT_S = 5.0` via `asyncio.wait_for` sur chaque détection RSS. Worst-case ~10s/requête (5s × root fallback en parallèle), au lieu de 40-50s sur des domaines lents.



1. **Drop des résultats sans feed détecté** dans `_search_brave` / `_search_google_news` / `_search_mistral` (`smart_source_search.py`). Une "source" sans feed n'est pas une source (validé par le PO). Garde de finalisation aussi dans `_finalize`.
2. **Fallback root host** : `_detect_with_root_fallback` retente la détection sur `scheme://host` quand l'URL article rate (Brave renvoie souvent `lemonde.fr/article-123.html` au lieu de `lemonde.fr`).
3. **Filtres listicle** : nouveau `providers/denylist.py` (hosts type `feedspot.com`, `floridapolitics.com`, `votersselfdefense.org` et titres `^(Top|Best) \d+`).
4. **Reformulation Brave** : query envoyée brute (suppression de `RSS feed site blog`) + `result_filter=web`.
5. **Catalog accent-insensible + fuzzy** : `_search_catalog` utilise `unaccent(lower(name))` ILIKE + `pg_trgm.similarity ≥ 0.30`. `normalize_query` strip aussi les accents Unicode côté Python (cohérent avec DB).
6. **Court-circuit** : `MIN_RESULTS_FOR_SHORTCIRCUIT` 3 → **1**. Un seul hit curated suffit (validé empiriquement sur 9 requêtes types).
7. **Observabilité refondue** : nouvelle table `source_search_logs` (modèle `app/models/source_search_log.py`, migration `ssq01_create_source_search_logs.py`). Toutes les recherches (cache hit + miss) sont persistées avec `query_raw`, `query_normalized`, `layers_called`, `top_results jsonb`, `latency_ms`, `cache_hit`, `abandoned`. Insert via session indépendante (best-effort, ne bloque jamais la réponse).
8. **`/sources/search-abandoned`** déclenche maintenant `mark_search_abandoned` (UPDATE sur le dernier log) en plus de l'insert legacy `failed_source_attempts` (rétrocompat).

### Migration manuelle requise (Supabase SQL Editor)

`CLAUDE.md` interdit Alembic sur Railway. À exécuter dans Supabase Studio avant déploiement :

```sql
CREATE EXTENSION IF NOT EXISTS unaccent;
-- Puis appliquer le DDL produit par alembic upgrade head depuis ssq01.
```

## Fichiers impactés

- `packages/api/app/services/search/smart_source_search.py`
- `packages/api/app/services/search/cache.py` (accent strip)
- `packages/api/app/services/search/providers/brave.py` (query brute)
- `packages/api/app/services/search/providers/denylist.py` (nouveau)
- `packages/api/app/models/source_search_log.py` (nouveau)
- `packages/api/app/models/__init__.py`
- `packages/api/alembic/versions/ssq01_create_source_search_logs.py` (nouveau)
- `packages/api/app/routers/sources.py` (search-abandoned)
- `packages/api/tests/services/search/test_smart_source_search.py` (nouveaux tests)

## Validation

- Tests unitaires : 42 cas dans `test_smart_source_search.py`, tous verts.
- Suite backend : 725 passed, 13 skipped, 44 errors (tous pré-existants : OperationalError sur Postgres local non démarré, inchangés par cette PR).
- Validation E2E : à faire via `/validate-feature` (handoff QA à rédiger) après application de la migration sur staging.

## Hors scope (story dédiée)

Catalog reste mince (~200 actives) : sources cibles encore manquantes (Hugo Décrypte, The Generalist, Arrêt sur Images en curated, etc.). Voir `docs/stories/core/7.7.sources-catalog-expansion.md`.

---

## Optimisation latence — phase 2 (2026-04-26)

Probe phase 1 : qualité 9/9 mais latence cold ~10s/requête (Brave). Cible : <4s cold, <1s warm.

### Optimisations

1. `_detect_with_root_fallback` (smart_source_search.py) : tente le host root en premier, supprime le fallback article-URL (doublait la latence pire-cas pour zéro recall mesurable). Liste `_PATH_LEVEL_PLATFORMS` pour les sites où le feed vit au path-level (YouTube channels, Substack, Medium).
2. Nouvelle table `host_feed_resolutions` (migration `ssq02_create_host_feed_cache.py`, modèle `app/models/host_feed_resolution.py`) : cache host → feed_url avec TTL 30 j positif / 7 j négatif. Best-effort, session indépendante via `async_session_maker()`.
3. `rss_parser.py` : la boucle séquentielle `for suffix in COMMON_SUFFIXES` devient un `asyncio.as_completed` avec `Semaphore(4)` ; on court-circuite au 1er feed valide et `cancel()` les pending.
4. `_detect_candidates` (smart_source_search.py) : parallélisation des détections, court-circuit à 3 feeds collectés OU "grace window" de 1.5 s après le 1er hit (borne le pire-cas batch).
5. `search()` orchestrateur : Brave + Google News en parallèle quand `expand=True` (`asyncio.gather`).
6. Pré-tri des candidats Brave (top 5) par fréquence host + boost `.fr` si query FR (`_looks_french`).
7. `FEED_DETECT_TIMEOUT_S` : 5.0 → 4.0 s.

### Résultats (probe v6, cold cache)

- Brave médiane 10.6 s → 3.3 s (~7 s gagnés).
- Google News médiane 4.1 s → 3.3 s.
- 9/9 feeds FR pertinents (qualité préservée).

Le cache warm (`host_feed_resolutions`) descend les hits répétés à <500ms, à valider sur staging après application de la migration.

### Migration manuelle requise (Supabase SQL Editor)

```sql
CREATE TABLE host_feed_resolutions (
  host VARCHAR(255) PRIMARY KEY,
  feed_url TEXT NULL,
  type VARCHAR(20) NULL,
  title VARCHAR(255) NULL,
  logo_url TEXT NULL,
  description TEXT NULL,
  resolved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_host_feed_resolutions_expires_at
  ON host_feed_resolutions (expires_at);
```

### Fichiers ajoutés / modifiés (phase 2)

- `packages/api/app/services/search/smart_source_search.py` (orchestrateur, cache hook, ranking)
- `packages/api/app/services/rss_parser.py` (parallélisation suffixes)
- `packages/api/app/models/host_feed_resolution.py` (nouveau)
- `packages/api/app/models/__init__.py`
- `packages/api/alembic/versions/ssq02_create_host_feed_cache.py` (nouveau)
- `packages/api/scripts/probe_external_search.py` (mirror de la nouvelle logique)
- `packages/api/tests/services/search/test_smart_source_search.py` (tests root-first, cache key, looks_french)
