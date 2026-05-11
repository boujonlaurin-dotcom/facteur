# Bug: App très lente le dimanche soir (toutes requêtes)

## Statut
- [x] En cours d'investigation
- [ ] En cours de correction
- [ ] Corrigé

## Sévérité
🟠 Haute — dégradation perçue sur toute l'app aux heures de pointe

## Description

Dimanche 2026-05-10 au soir, l'app est rapportée comme « très lente dans toutes ses requêtes ». Le ralentissement n'est pas lié à un endpoint en particulier mais touche l'ensemble du backend, ce qui pointe vers une saturation système (DB, pool de connexions, ou worker bloquant l'event loop).

## Diagnostic

### Données collectées

**Snapshot DB (Supabase, project `ykuadtelnzavrqzbfdve`)**
- Postgres 17.6, instance EU-West-1, 60 max_connections
- Taille DB : 450 MB
- `idle_in_transaction_session_timeout = 60000` (60 s)
- `statement_timeout = 120000` (2 min)
- `work_mem = 2184` (2 MiB — très bas)

**Logs Postgres (1 dernière heure)**
- ⚠️ **Plusieurs `FATAL: terminating connection due to idle-in-transaction timeout`** (au moins 5 occurrences). Une connexion qui dépasse 60 s avec une transaction ouverte est tuée. À chaque kill : la session client (Supavisor pooler / Railway worker) reconnecte → cascade de réauths visibles dans les logs.

**Top requêtes par temps cumulé (`pg_stat_statements`)**

| # | Requête | Calls | Mean ms | Max ms | Total |
|---|---------|------:|--------:|-------:|------:|
| 1 | `SELECT contents.* WHERE guid = $1` (et variantes par id) | **7 845 556** | 1.3 | 1 178 | 10 356 s |
| 2 | `DELETE FROM daily_digest WHERE id = $1` | 2 867 | **1 411** | **116 441** | 4 047 s |
| 3 | `UPDATE contents SET extraction_attempted_at WHERE id = $1` | 2 984 184 | 1.2 | 4 982 | 3 630 s |
| 4 | `INSERT INTO source_search_cache … ON CONFLICT …` | 188 | **1 293** | **119 680** | 243 s |
| 5 | `INSERT INTO user_profiles …` | 125 | **6 119** | 86 276 | 765 s |
| 6 | `SELECT count(*) FROM contents WHERE published_at < … AND id NOT IN (bookmarks) AND id NOT IN (deep)` | 55 | 4 792 | 11 077 | 264 s |
| 7 | `DELETE FROM contents WHERE published_at < … AND id NOT IN (…) AND id NOT IN (…)` | 55 | **3 979** | 12 927 | 219 s |
| 8 | `SELECT daily_digest.items, format_version FROM daily_digest WHERE generated_at >= $1` | 22 | **9 845** | 18 449 | 217 s |

**Advisors performance (Supabase linter)**
- `unindexed_foreign_keys` (INFO, mais coûteux côté CASCADE) :
  - `user_content_status.content_id`, `daily_top3.content_id`, `curation_annotations.content_id`, `user_sources.source_id`, `user_interests.user_id`, `user_preferences.user_id`, `user_subtopics.user_id`
- `auth_rls_initplan` (WARN) sur **8 tables hot** (`user_sources`, `user_interests`, `user_content_status`, `user_profiles`, `user_preferences`, `user_streaks`, `user_topic_profiles`) — `auth.<fn>()` réévalué pour CHAQUE row → coût × N.
- `unused_index` × 21 — bruit (pas la cause).

**Tailles des tables sensibles**

| Table | Lignes | Taille totale | Bytes/row |
|-------|-------:|--------------:|----------:|
| `contents` | 38 310 | **314 MB** | ~8 KB |
| `daily_digest` | 5 491 | **64 MB** | **~12 KB** ⚠️ |
| `classification_queue` | 36 559 | 24 MB | <1 KB |

> Le `daily_digest.items` JSONB embarque les 5 articles complets (titre + html_content + thumbnails) → chaque DELETE/SELECT déplace beaucoup de heap.

**Autovacuum tardif**
- `user_sources` : dernier autovacuum **2026-04-16** (24 j)
- `user_subtopics` : 2026-04-23 (17 j)
- `user_topic_profiles` : **jamais autovacuumé**

### Cause racine (synthèse)

Le ralentissement perçu dimanche soir est la conséquence visible de **4 causes structurelles** qui s'additionnent au moment du pic d'usage :

#### 1. Transactions RSS qui restent ouvertes ≥ 60 s (déclenchent les kills)

`SyncService.process_source()` (`packages/api/app/services/sync_service.py:97-158`) :
- Ouvre une transaction côté `self.session`.
- Boucle sur **jusqu'à 50 entries** par feed.
- Pour chaque entry :
  - `_fetch_html_head(url)` — fetch HTTP synchrone à l'intérieur de la transaction (paywall detect).
  - `_save_content` → `SELECT contents WHERE guid = $1` (le **N+1 #1** : 7.8 M appels cumulés).
  - `_enrich_content` → trafilatura via `asyncio.wait_for(..., timeout=20)` — fetch HTTP + extraction en thread pool.
  - `_enqueue_for_classification` (insert dans `classification_queue`).
- COMMIT seulement après les 50 entries (ligne 156).

→ Dès qu'une poignée d'URLs lentes est rencontrée, la transaction dépasse 60 s et Postgres la kill. Sous le `Semaphore(5)`, **jusqu'à 5 transactions à la fois** vivent ainsi pendant la fenêtre de sync (toutes les 30 min).

#### 2. N+1 massifs côté workers

- **7.8 M `SELECT Content WHERE guid = $1`** (1.3 ms × ce volume = 10 356 s cumulés). Origine : `_save_content` ligne 474.
- **2.98 M `UPDATE contents SET extraction_attempted_at`** (ligne 560) — un `UPDATE` par article extrait, sans batching.

À chaque tour de sync RSS, tous ces hits s'accumulent et entrent en concurrence avec les requêtes user.

#### 3. Cascades DELETE non-indexées + bloat

`storage_cleanup.cleanup_old_articles()` (3 h Paris) supprime ~67 k articles via **deux `NOT IN (subquery)`** (notoirement lents en Postgres) puis le DELETE déclenche **8 `ON DELETE CASCADE`**. Trois des FK enfants n'ont **pas d'index** (`user_content_status.content_id`, `daily_top3.content_id`, `curation_annotations.content_id`) → seq scan complet × 67 k itérations.

Conséquences observées :
- DELETE moyen 4 s, max 13 s → bloat important laissé après vacuum.
- **`DELETE FROM daily_digest WHERE id = $1` mean 1.4 s, max 116 s** : cohérent avec une table à 64 MB pour 5 k lignes (heap fetch très lourd à cause du JSONB items).
- L'autovacuum n'a pas tenu sur certaines tables RLS (`user_topic_profiles` jamais).

#### 4. RLS + FK + work_mem trop bas amplifient sous charge

- 8 tables hot avec `auth.<fn>()` réévalué par row (advisor `auth_rls_initplan`) — chaque endpoint user paye une re-eval par ligne renvoyée.
- `work_mem = 2 MiB` → tout tri/hash sur les requêtes feed/digest spille rapidement sur disque (les SELECT contents qui retournent 100 k+ lignes en pg_stat le confirment).

**Pourquoi spécifiquement dimanche soir ?** C'est le pic d'usage user (lecture du digest, feed, sources) qui se superpose à un sync RSS toutes les 30 min. Les 4 causes ci-dessus consomment connexions, locks et CPU en continu — au pic, la file d'attente du pool Supavisor et les kills de transactions deviennent visibles côté mobile sous forme de latences globales.

## Plan d'action proposé (PLAN — confirmation requise avant CODE)

L'objectif est de réduire la pression DB **sans toucher aux zones fragiles** (Auth/Router/Migrations) avant validation. Phasage du moins risqué au plus impactant :

### Phase 0 — Mesure immédiate (no-op)
1. Activer `log_min_duration_statement = 500ms` (déjà ?) et capturer 1 h de pic dimanche prochain pour confirmation chiffrée.
2. Instrumenter Sentry transactions sur `/api/digest/`, `/api/feed/`, `/api/sources/` côté backend (mesurer p50/p95).

### Phase 1 — Quick wins (faible risque, gros gain)

| # | Action | Fichier | Gain attendu |
|---|--------|---------|--------------|
| 1.1 | **Sortir les fetchs HTTP de la transaction** : pré-charger les 50 entries en mémoire, fermer l'extraction trafilatura (déférer au worker classification), ne garder en transaction que les SELECT/INSERT/UPDATE rapides. | `services/sync_service.py:97-158`, `_enrich_content` | Plus de transactions > 60 s, fin des FATAL. |
| 1.2 | **Indexes manquants sur FK CASCADE** : `CREATE INDEX CONCURRENTLY ix_user_content_status_content_id`, `ix_daily_top3_content_id`, `ix_curation_annotations_content_id`. | SQL Editor (CLAUDE.md : pas via Alembic sur Railway) | DELETE contents : −80 % temps + locks réduits. |
| 1.3 | **Batcher l'`UPDATE extraction_attempted_at`** : un seul `UPDATE … WHERE id = ANY(:ids)` par feed au lieu d'un par article. | `services/sync_service.py:560` | Diviser ~3 M UPDATE par 50. |
| 1.4 | **Réécrire le cleanup `NOT IN` en `LEFT JOIN … WHERE NULL` ou `EXCEPT`** + ajouter `LIMIT … RETURNING` pour batches de 5 k. | `workers/storage_cleanup.py` | Cleanup 4 s → < 500 ms, plus de pic 12 s. |

### Phase 2 — Réduire les lectures inutiles

| # | Action | Fichier |
|---|--------|---------|
| 2.1 | Remplacer `SELECT Content WHERE guid = $1` par `INSERT … ON CONFLICT (guid) DO UPDATE … RETURNING (xmax = 0) AS is_new` (un seul round-trip au lieu de SELECT puis INSERT). | `services/sync_service.py:_save_content` |
| 2.2 | Charger `daily_digest.items` à la demande (lazy) ou splitter `items` en table `daily_digest_items` pour ne pas trimballer 12 KB/row. Au minimum, ajouter un index partiel sur `generated_at` et restreindre les SELECT. | `models/daily_digest.py`, `services/digest_*` |
| 2.3 | Optimiser les RLS `auth.<fn>()` → `(select auth.<fn>())` sur `user_sources`, `user_content_status`, `user_profiles`, `user_preferences`, `user_interests`, `user_streaks`, `user_topic_profiles`. | SQL Editor (RLS policies) |

### Phase 3 — Capacité

| # | Action | Notes |
|---|--------|-------|
| 3.1 | Augmenter `work_mem` à 8–16 MB côté Supabase. | Validation requise (impact mémoire instance). |
| 3.2 | Évaluer la taille d'instance Supabase au pic (CPU + connections). | Décider après mesures Phase 0. |
| 3.3 | Stratégie de connexion Auth en %, pas en absolu (advisor `auth_db_connections_absolute`). | Une fois la pression DB redescendue. |

### Phase 1 — Implémentation (état)

| # | Statut | Détail |
|---|--------|--------|
| 1.1 | ✅ Déjà fait dans `main` (autre archi) | `process_source` a été refactoré dans une PR antérieure (refactor « P2 » ref `bug-infinite-load-requests.md`) : pattern « session courte par entry » via `_short_session()`, HTTP fetches hors session. Résout le même problème (transactions > 60 s) par une architecture différente de celle planifiée ici. Pas de re-implémentation nécessaire. |
| 1.2 | ✅ Appliqué en prod + scripté | 3 `CREATE INDEX IF NOT EXISTS` exécutés via Supabase MCP : `ix_user_content_status_content_id`, `ix_daily_top3_content_id`, `ix_curation_annotations_content_id`. SQL archivé : `packages/api/sql/014_fk_cascade_indexes.sql`. |
| 1.3 | ✅ Implémenté | Cooldown 24h (`_EXTRACTION_RETRY_DELAY`) ajouté dans `sync_service._is_extraction_stale()` + gate dans le `needs_enrich` de `_save_content`. Un article dont l'extraction a échoué dans les 24h n'est plus re-tenté à chaque sync (30 min), ce qui élimine la majorité des ~3 M UPDATE/jour sur `extraction_attempted_at`. |
| 1.4 | ✅ Implémenté | `storage_cleanup` : `~Content.id.in_(subquery)` → `not_(exists().where(...))` sur bookmarks + deep sources. Bénéficie directement des index de 1.2. La protection digest-refs (90 j) reste intacte (déjà sur main, on ne touche pas). |

### Phase 2 — Implémentation (état)

| # | Statut | Détail |
|---|--------|--------|
| 2.1 | ⏳ Reporté à une PR séparée | Architecture des PRs précédentes (main) utilise un pattern per-entry avec `_short_session()` ; la première tentative bulk-load (commit `3637cac`, archivée sur `backup/fix-app-slowness-ce5r9-before-rebase`) reposait sur un pattern incompatible. Il faut redo en `INSERT … ON CONFLICT (guid) DO UPDATE … RETURNING (xmax = 0) AS is_new` directement dans `_save_content` pour éliminer le `SELECT WHERE guid = $1`. |
| 2.2 | ⏳ Non démarré | `daily_digest.items` lazy / splitter en table. |
| 2.3 | ✅ Appliqué en prod + scripté | 20 policies sur 7 tables (`user_content_status`, `user_sources`, `user_profiles`, `user_preferences`, `user_interests`, `user_streaks`, `user_topic_profiles`) ré-écrites avec `(SELECT auth.uid())` pour init-plan caching (1 éval par requête au lieu de 1 par row). Appliqué via Supabase MCP `apply_migration` (nom : `rls_auth_uid_optimization`). SQL archivé : `packages/api/sql/015_rls_auth_uid_optimization.sql`. Vérifié post-déploiement : toutes les policies ont `qual`/`with_check` wrappés. |

## Fichiers concernés

- `packages/api/app/services/sync_service.py` (transaction, N+1, batch UPDATE)
- `packages/api/app/workers/storage_cleanup.py` (NOT IN, cascade)
- `packages/api/app/models/daily_digest.py` (taille JSONB items)
- SQL via Supabase SQL Editor : index FK manquants, RLS optimisés
- `packages/api/app/workers/scheduler.py` (à n'ajuster qu'après mesures)

## Notes / hypothèses à confirmer

- L'API tourne sur Railway (pas Edge Functions Supabase) — les logs API (latences endpoints, p95) doivent être récupérés côté Railway/Sentry pour finaliser la corrélation Sunday-evening peak ↔ kills.
- Aucun job hebdomadaire spécifique « dimanche » n'a été trouvé dans `scheduler.py` : le ralentissement est bien lié au pic user × pression de fond constante, pas à un cron weekly.
- Le SELECT lent `SELECT items, format_version FROM daily_digest WHERE generated_at >= $1` (mean 9.8 s) mérite une lecture du code appelant (`services/briefing/`, `digest_selector`) pour vérifier qu'il n'est pas appelé par un endpoint user — sinon c'est un quick win additionnel.
