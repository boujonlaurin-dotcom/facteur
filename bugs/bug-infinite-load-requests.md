# Bug — Requêtes qui loadent indéfiniment en prod

**Statut** : En cours
**Branche** : `claude/fix-infinite-load-requests-oSPYQ`
**Sévérité** : 🔴 Critique (prod)
**Fichiers critiques** :
- `packages/api/app/routers/digest.py`
- `packages/api/app/main.py`
- `packages/api/app/database.py`
- `packages/api/app/routers/health.py`
- `apps/mobile/lib/features/digest/providers/digest_provider.dart`

## Symptôme

Les utilisateurs rapportent que les requêtes API "loadent à l'infini". Aucune
réponse n'arrive, ni 2xx ni erreur propre. Le mobile finit par timeout (45s côté
client) mais le serveur ne libère pas ses ressources.

## Diagnostic — cascade de hangs non bornés

### #1 — `/digest/both` sans timeout serveur (cause racine)

`packages/api/app/routers/digest.py:308-311`

```python
normal, serein = await asyncio.gather(
    _gen_variant(False),
    _gen_variant(True),
)
```

`asyncio.gather` sans `asyncio.wait_for`. Si une dépendance en aval bloque
(LLM Mistral, fetch Google News RSS pour perspective analysis, Supabase lent),
la requête hang indéfiniment. Chaque `_gen_variant` ouvre sa propre
`async_session_maker()` → 2 connexions DB gelées par requête hangée.

Introduit par PR #367 (commit `1a1c34c`) qui a parallélisé la génération sans
wrapper de timeout.

### #2 — Pool DB saturable rapidement

`packages/api/app/database.py:50-53` : `pool_size=10`, `max_overflow=10`,
`pool_timeout=30s`. Le feed consomme déjà ~3 conns/req. Avec seulement 3-4
requêtes `/digest/both` bloquées on sature les 20 connexions max. **Toutes
les autres requêtes attendent 30s** avant d'obtenir une connexion, d'où
l'impression "tout charge à l'infini".

### #3 — Startup catchup sans timeout ni lock

`packages/api/app/main.py:168-228` : `_startup_digest_catchup()` lancé via
`asyncio.create_task()` exécute `run_digest_generation()` pour tous les users
si couverture < 90 %. Aucun timeout, aucune limite. Sur un redéploiement
Railway (ex. après le deploy bloqué par PR #394), ça peut :
- bouffer le pool au démarrage
- bloquer toute requête entrante
- s'empiler à chaque restart

### Amplificateurs mobiles

1. **Pyramide de retries** — `retry_interceptor.dart` (maxRetries=2) × 4
   tentatives dans `digest_provider.dart:103-108` (5/10/15s) × 45s timeout
   par appel. Worst case ≈ 9 minutes avant erreur visible, pendant que le
   backend accumule des conns zombies.

2. **Auth DB check par requête** — `dependencies.py:78-116` :
   `_check_email_confirmed_with_retry` ajoute jusqu'à 3,5s bloqué sur auth
   quand le pool est saturé. Cache positif 1h → premier appel de l'heure
   toujours à la DB.

## Plan de fix

### Fix 1 — Timeout serveur sur `/digest/both` (critique)

`packages/api/app/routers/digest.py:308`

- Wrapper `asyncio.wait_for(asyncio.gather(...), timeout=30.0)`
- Sur `TimeoutError` → HTTPException 503 `digest_generation_timeout`
- Timeout interne de 25s sur chaque `_gen_variant` pour borner individuellement
- Libère les sessions DB même si l'upstream est lent

### Fix 2 — Timeout + lock sur startup catchup

`packages/api/app/main.py:168-228`

- `asyncio.wait_for(run_digest_generation(...), timeout=300.0)`
- Module-level `asyncio.Lock` pour éviter la double exécution si Railway relance
- Log propre si timeout

### Fix 3 — Observabilité pool DB

- Nouveau endpoint `GET /api/health/pool` → `{checkedout, overflow, checkedin}`
- Log `warning` + breadcrumb Sentry si `checkedout > 15` (via middleware asyncio
  task toutes les 30s)

### Fix 4 — Retries mobile bornés sur timeout serveur

`apps/mobile/lib/features/digest/providers/digest_provider.dart`

- Distinguer 503 `digest_generation_timeout` (pas la peine de retry beaucoup) vs
  202 `preparing` (retry légitime)
- Retries sur timeout réduits de 3 → 1

## Ce que ça règle / ne règle pas

✅ **Règle** : cascade hang → pool saturé → tout hang
✅ **Règle** : startup catchup qui peut geler pour toujours
✅ **Règle** : mobile qui retente 9 min un 503 "permanent"
⚠️ **Ne règle pas la cause racine amont** (qui fait hanger Mistral/Google
News/Supabase ?). Les logs structlog existants + le nouveau endpoint pool
donneront le signal pour identifier le vrai coupable sans bloquer la prod.

## Tests

- `packages/api/tests/test_digest_router.py::test_digest_both_timeout_returns_503`
- `packages/api/tests/test_main.py::test_startup_catchup_respects_timeout`
- `packages/api/tests/test_main.py::test_startup_catchup_lock_prevents_double_run`
- `packages/api/tests/test_health.py::test_pool_endpoint_returns_metrics`

## Post-mortem — investigation 2026-04-14 (root cause confirmée)

Après merge des PR #396 + #397, les users rapportent que les requêtes hangent
toujours. Investigation en 2 temps : une première hypothèse invalidée, puis
la vraie cause trouvée via probe `pg_stat_activity` sur prod.

### 🎯 Root cause confirmée — sessions SQLAlchemy tenues trop longtemps

**Preuve live** (`/api/health/pool` + `pg_stat_activity` sur prod, 2026-04-14) :

```
/api/health/pool :
  size: 10, overflow: 10, checked_out: 16, usage_pct: 80%
  → 80% du pool consommé en observation statique
```

```
pg_stat_activity (WHERE state='idle in transaction') :
  14 connexions coincées, wait_event=ClientRead
  Ages: de 717s à 7090s (12 min à 2 heures)
  Queries: 10 × SELECT contents.id, ...  |  4 × SELECT sources.id, ...
```

**Signature "idle in transaction + ClientRead"** = le client Python a ouvert
une transaction, exécuté un SELECT, puis est parti `await` quelque chose qui
n'est jamais revenu. Postgres attend passivement la prochaine commande. La
transaction reste ouverte, la connexion reste checkée-out du pool.

**Distribution des ages en pyramide** (plusieurs à 12-15 min, quelques-unes
à 1-2h) = fuite **incrémentale** — chaque cycle de travail laisse derrière
lui une ou deux sessions qui ne se referment jamais. Le pool se remplit au
fil du temps jusqu'à saturation → `pool_timeout=30s` se déclenche pour
chaque nouvelle requête → "tout charge à l'infini" côté mobile.

**Driver asyncpg** (confirmé dans `database.py:31-62`) → les sessions ne
sont pas bloquées par un thread pool saturé : c'est bien le code Python qui
`await` sur une chaîne de dépendances trop longue tout en gardant la session
ouverte.

### Deux sites coupables

Les signatures des queries matchent deux code paths qui **tiennent la session
pendant une longue cascade d'`await`s externes** :

#### Site A — `SyncService.process_source` (RSS sync, `sync_service.py:97-400+`)

Patron :
```python
async def process_source(self, source):
    # Session.session déjà ouverte
    response = await self.client.get(source.feed_url)         # httpx 30s
    feed = await loop.run_in_executor(..., feedparser.parse, content)
    for entry in feed.entries[:50]:                           # ← 50 itérations
        content_data = self._parse_entry(entry, source)
        html_head = await self._fetch_html_head(...)          # 5s × 50 = 250s max
        await self._save_content(data)                        # commits? non
        # ContentEnricher._enrich_content :
        await asyncio.wait_for(
            run_in_executor(None, trafilatura.extract, url),  # 20s × 50 = 1000s max
            timeout=20.0,
        )
```

**Session tenue pendant 50 entries × ~5-25s = 4 à 20 min par source**.
Semaphore=5 parallèle → 5 sessions simultanées pendant chaque cycle de sync
(intervalle défaut : quelques minutes). Match parfait avec les ages 12-30 min
observés sur les `SELECT sources.id, ...`.

Pourquoi certaines montent à 1-2h : si `_enrich_content`'s `wait_for` cancel
ne libère pas proprement la session (exception avalée, boucle continue), ou
si un bug de sémantique empêche un rollback, la session peut rester active
au-delà d'un cycle RSS. À investiguer spécifiquement.

#### Site B — Pipeline éditoriale (`digest_service.get_or_create_digest` → `editorial/pipeline.py`)

Patron :
```python
async def get_or_create_digest(self, user_id, ...):
    # db session injectée par get_db()
    profile = await user_service.get_or_create_profile(...)
    # SELECT content candidates (grosse requête) ← c'est notre SELECT contents.*
    digest_items = await selector.select_for_user(...)
      # → EditorialPipeline.compute_global_context:
      #   - cluster building
      #   - LLM curation (Mistral) × 2-3           ← 30s × 3 = 90s
      #   - perspective analysis per subject
      #     × search_perspectives (Google News)    ← 10s × 5 = 50s
      #     × analyze_divergences (Mistral)        ← 30s × 5 = 150s
      #   - writing LLM × 5 subjects               ← 30s × 5 = 150s
      #   - pepite + coup_de_coeur LLM             ← 30s × 2 = 60s
```

**Session tenue pendant 5 à 10 min dans le pire cas**. Match avec les ages
5-15 min observés sur les `SELECT contents.*`. Pas borné côté handler pour
`/api/digest` (seul `/digest/both` l'est via PR #396).

### Pourquoi PR #396 + #397 n'ont pas suffi

- PR #396 borne **seulement** `/digest/both` (25s/30s). Laisse `/api/digest`,
  `/api/digest/generate`, et surtout **le scheduler RSS sync** totalement
  non bornés.
- PR #397 déplace la DNS en executor. Indépendant du problème de sessions
  longues — corrige uniquement le healthcheck startup.
- Aucun des deux n'adresse le pattern "session longue + await externe" qui
  est la cause racine.

### Fix architectural recommandé

Par ordre de priorité (les 1-3 adressent la cause racine, les 4-6 sont
defensive-in-depth) :

1. **Scoper les sessions par unité de travail atomique** (site A) :
   dans `process_source`, commit + close immédiatement après le SELECT initial
   des sources. Pour chaque entry : ouvrir une session éphémère juste le
   temps de l'INSERT + commit. Les appels httpx/trafilatura se font **hors
   transaction**. C'est l'anti-pattern classique "transaction autour du world".

2. **Même traitement pour la pipeline éditoriale** (site B) :
   les appels LLM/Google News sont des I/O externes, ils ne doivent **jamais**
   être dans un `with session:` bloc. Refactor : fetch contents, fermer la
   session, faire les LLM appels, rouvrir une session pour le write final.

3. **Request-budget middleware (commit `3d4ec06`) en filet de sécurité** :
   même avec sessions courtes, un endpoint peut rester lent côté perçu.
   Mérite d'être mergé pour borner tout à 60s + donner les logs
   `request_budget_exceeded` pour visibilité.

4. **Remplacer `trafilatura.fetch_url(url)` par httpx + `trafilatura.extract`** :
   pattern identique à `rss_parser.py`. Évite le thread executor hang.

5. **Remplacer les `feedparser.parse(url)` dormants** (`digest_selector.py:1526`
   et `briefing_service.py:274`) par le même pattern httpx+parse(content).
   Dormant aujourd'hui (0 rows `une_feed_url`), landmine demain.

6. **`socket.setdefaulttimeout(15)`** en top de `main.py` comme ceinture+bretelles.

### Probe additionnelle (à faire avant de coder)

Pour départager site A vs site B en volume, cette query discrimine par
signature de colonnes :

```sql
SELECT
  CASE
    WHEN query ILIKE 'SELECT sources.id, sources.name%' THEN 'sync_service (A)'
    WHEN query ILIKE 'SELECT contents.id, contents.source_id%' THEN 'digest_or_sync (B or A)'
    ELSE 'other'
  END AS likely_site,
  count(*),
  round(avg(extract(epoch from now() - query_start))::numeric, 1) AS avg_age_s,
  max(extract(epoch from now() - query_start))::int AS max_age_s
FROM pg_stat_activity
WHERE datname = 'postgres'
  AND state = 'idle in transaction'
  AND backend_type = 'client backend'
GROUP BY 1
ORDER BY count(*) DESC;
```

Si `sync_service (A)` domine en volume **et** en age max → prioriser fix #1.
Si `digest_or_sync (B or A)` domine → probablement pipeline éditoriale, donc
fix #2 d'abord.

### ⚠️ Hypothèse #1 INVALIDÉE — `feedparser.parse(url)` sur `une_feed_url`

**Ce qu'on pensait** : deux sites passent une URL (pas du contenu) à
`feedparser.parse` dans un `run_in_executor` (`digest_selector.py:1526` et
`briefing_service.py:274`). feedparser utilise alors `urllib` en interne
*sans timeout*, et `asyncio.wait_for` ne peut pas tuer un thread bloqué →
thread pool poisoning systémique.

**Pourquoi c'est faux en pratique** : vérifié en DB — `SELECT count(*) FROM
sources WHERE une_feed_url IS NOT NULL` renvoie **0**. Les deux fonctions
`_fetch_une_guids` concernées early-return `set()` sans jamais atteindre le
`run_in_executor`. Le code est un pattern dangereux (à corriger pour éviter
une régression future), mais il **n'est pas exécuté en prod** → il ne peut
pas être la cause racine du hang observé aujourd'hui.

### Ce qui a été écarté

| Piste                                     | Vérification                                                                                  | Statut                      |
|-------------------------------------------|-----------------------------------------------------------------------------------------------|-----------------------------|
| `feedparser.parse(url)` via `une_feed_url`| 0 rows en DB (`sources.une_feed_url IS NOT NULL`)                                             | ❌ écartée                  |
| `rss_parser.py` sync-feedparser leaks     | Tous les appels fetchent d'abord via `self.client.get(url)` (httpx) puis parsent `resp.text`  | ❌ écartée                  |
| `perspective_service.search_perspectives` | `httpx.AsyncClient(timeout=self.timeout)` avec `self.timeout=10.0` (default)                  | ❌ écartée                  |
| `editorial/llm_client.py` (Mistral)       | `httpx.AsyncClient(timeout=30.0)` explicite, bornée par appel                                 | ❌ écartée                  |
| `sync_service._fetch_html_head`           | `timeout=5.0` explicite sur le `client.get`                                                   | ❌ écartée                  |
| `socket.setdefaulttimeout` globalement    | Aucune occurrence trouvée (mais pas nécessaire si chaque client borné individuellement)       | neutre                      |

### Suspects actifs (non écartés, ordonnés par probabilité)

#### S1 — `GET /api/digest` (variante simple) sans timeout handler — **priorité haute**

`packages/api/app/routers/digest.py:163-264`

Contrairement à `/digest/both` (PR #396), le handler simple `GET /api/digest`
n'a **aucun timeout autour de `service.get_or_create_digest`**. Mêmes
upstream que `/both` :
- `UserService.get_or_create_profile`
- `DigestSelector.select_for_user` → pour un user sans digest existant (ni
  aujourd'hui ni hier), déclenche la pipeline éditoriale complète : clusters,
  LLM curation, perspective analysis (Google News RSS), writing LLM, pépites,
  coup de cœur. **Chaque LLM call est borné à 30s mais ils sont séquentiels —
  6 à 10+ appels possibles = 3 à 5 min dans le pire cas.**

Pendant tout ce temps la session SQLAlchemy reste checked-out. 10-15 requêtes
dans cet état saturent le pool (20 max) → toute autre requête attend
`pool_timeout=30s` → 503 pour tout le monde → "tout charge à l'infini".

`/api/digest/generate` (`digest.py:503-541`) a le même problème — pas de
wrapper `wait_for`.

Pourquoi PR #396 n'a rien changé sur ce front : le timeout a été ajouté
*uniquement* autour de `/digest/both`, pas sur `/digest` ni `/digest/generate`.

#### S2 — ContentExtractor (trafilatura) via `GET /api/contents/{id}` — priorité moyenne

`packages/api/app/routers/contents.py:76-83` et
`packages/api/app/services/sync_service.py:558-565`

```python
result = await asyncio.wait_for(
    asyncio.get_event_loop().run_in_executor(None, extractor.extract, url),
    timeout=15.0,
)
```

- `trafilatura.fetch_url` est synchrone, s'exécute dans le default executor.
- `asyncio.wait_for` cancel la coroutine mais **pas le thread** (même pattern
  anti-wait_for que l'hypothèse #1, mais ici réellement utilisé en prod).
- `trafilatura` configure bien `DOWNLOAD_TIMEOUT=10-15s` via urllib3, **mais**
  si un site reply lentement byte-par-byte sans jamais EOF, le read timeout
  urllib3 peut lui-même stall — rare mais pas impossible. En pratique,
  trafilatura est mieux bordé que feedparser.
- Un cooldown de 6h empêche le retry storm par article, mais pas la pression
  cumulative si plusieurs users ouvrent différents articles lents en même temps.

Probabilité modérée : la fréquence (ouverture d'article) est haute, mais la
protection par DOWNLOAD_TIMEOUT rend le hang infini moins plausible qu'un
vrai blackhole.

#### S3 — APScheduler sur le même event loop que FastAPI — priorité moyenne

`packages/api/app/workers/scheduler.py` + `run_digest_generation` exécuté à
06h00 Paris via `AsyncIOScheduler`.

- `AsyncIOScheduler` partage l'event loop de l'API. Pendant le run batch, le
  job tient des connexions DB et fait des `await` sérialisés pendant plusieurs
  minutes.
- Si le batch s'enchaîne sur le watchdog (07h30) et qu'un user request arrive
  entre les deux, la pipeline éditoriale par user tire encore sur le pool.
- Le lock anti-double-run existe pour le **startup catchup** (`_STARTUP_CATCHUP_LOCK`)
  mais pas pour le scheduler lui-même (qui a `coalesce=True` toutefois).

À confirmer : est-ce que le symptôme est corrélé aux fenêtres 06h-08h Paris ?

#### S4 — Amplification côté mobile — priorité basse (mais visible)

`apps/mobile/lib/features/digest/providers/digest_provider.dart`

Jusqu'à 4 tentatives × 45s = 3 minutes de perçu "chargement infini" même
pour un backend qui réponse en erreur rapide. Post-#396 le timeout côté
backend répond 503 en 30s mais le provider retente quand même. Si la cause
racine est S1/S2/S3, S4 ne l'aggrave que du côté UX — mais pour les users
c'est indiscernable d'un backend cassé.

### Décision commit `3d4ec06` (middleware request-budget 60s)

**Mergeer en défense en profondeur, oui — mais *d'abord pour collecter les
preuves*, pas comme fix final.**

- Le log `request_budget_exceeded` avec `path` + `method` donnera
  **immédiatement** la réponse à "quel endpoint hang ?". C'est le signal
  manquant pour trancher entre S1, S2, S3.
- Il libère la session DB sur cancel → protège le pool.
- **Ne règle pas** les threads executor (si S2 est le vrai coupable) : un
  trafilatura bloqué en thread survit à la cancellation de la coroutine.
- **Ne règle pas** un upstream LLM qui prend 5 min à répondre (S1) — il
  coupe juste proprement à 60s au lieu de laisser `pool_timeout` trancher.

→ Merger `3d4ec06` dans une PR séparée, laisser tourner **24-48h**, puis
   relire :
   1. `request_budget_exceeded` groupé par `path` dans Sentry
   2. `/api/health/pool` snapshots à intervalles réguliers
   3. Corrélation avec les fenêtres scheduler (06h/07h30/08h Paris)

### Probes à poser AVANT de coder un fix

1. **Sentry** : filtrer `message:"request_budget_exceeded"` (post-déploiement
   `3d4ec06`). Groupé par `path` → réponse directe à "S1 vs S2 vs S3".
2. **Sentry** : chercher `message:"content_extractor_error"` et
   `message:"content_extractor_fetch_failed"` groupés par `url` →
   identifie si trafilatura a des hosts lents récurrents.
3. **Railway logs** : chercher `digest_generating_new` +
   `digest_step_selection` pour voir les `duration_ms` de la pipeline.
   Si on voit régulièrement > 30 000 ms → S1 confirmé.
4. **`/api/health/pool`** : boucle `curl` pendant 5 min, noter `checked_out`
   pic et `status`. Si on voit `status:"saturated"` → mode pool-épuisé.
   Si `checked_out` reste haut pendant > 60s post-`request_budget_exceeded`
   → thread executor encore vivant → S2.
5. **DB** : `SELECT count(*), avg(extract(epoch from now() - started_at))
   FROM digest_generation_state WHERE status='running'` → combien de
   générations fantômes en cours.
6. **Corrélation temporelle** : superposer les heures Paris des spikes avec
   les cron schedules (06h, 07h30, 08h, 3h) → test S3.

### Fix root cause NON codé à ce stade

Pas de patch tant que S1/S2/S3 ne sont pas départagés par les probes ci-dessus.
Coder "dans le vide" risque d'ajouter du bruit sans résoudre la cause réelle.

Pistes préparées (à dégainer *après* tri) :

- **Si S1 gagne** : wrapper `asyncio.wait_for(service.get_or_create_digest(...), timeout=30)`
  dans `/api/digest` et `/api/digest/generate`, même pattern que `/both`.
- **Si S2 gagne** : remplacer `trafilatura.fetch_url(url)` par un
  `httpx.AsyncClient.get(url, timeout=10)` + `trafilatura.extract(resp.text)`,
  même pattern que `rss_parser.py`. Plus marquer `extraction_attempted_at`
  *avant* l'appel (pas juste après/en erreur) pour garantir le cooldown même
  si le thread hang.
- **Si S3 gagne** : sortir `run_digest_generation` de l'AsyncIOScheduler vers
  un worker process dédié (Railway service séparé), ou au minimum poser un
  `asyncio.wait_for` global sur le job avec un budget < 15 min.
- **Ceinture + bretelles transverses (à considérer quel que soit le gagnant)** :
  - `socket.setdefaulttimeout(15)` en top de `main.py`.
  - Augmenter `max_workers` du default executor (`loop.set_default_executor`)
    pour donner plus de marge avant saturation.
  - Semaphore + cache court sur les fan-outs upstream (Google News RSS,
    trafilatura) pour cap la parallélisation.

---

## Résolution — 2026-04-15 (branche `claude/fix-infinite-loading-requests-dKoY8`)

Après vérification `pg_stat_activity` sur prod : **4 sessions idle in
transaction, age moyen 53 min**, signature de queries pointant sur Site B
(~57 % de la fuite) et Site A (~36 %). Fix architectural codé selon le plan
1-3 + hygiène transverse, dans cet ordre :

### P1 — Pipeline éditoriale (Site B)

Pattern : **session_maker injecté + short sessions** pour toute opération DB
à l'intérieur de la pipeline, avec **commit explicite de la session injectée
AVANT l'appel LLM** pour libérer la connexion au pool.

Services modifiés (chacun accepte désormais `session_maker=None` optionnel +
helper `_short_session()` qui délègue au maker si présent, sinon retombe sur
la session injectée — 100 % rétro-compatible) :

- `app/services/editorial/deep_matcher.py` — `_load_deep_articles` ouvre
  une session courte le temps du SELECT puis la ferme, les appels LLM
  (`match_for_topics`) tournent **hors transaction**.
- `app/services/editorial/writer.py` — `_recent_highlight_content_ids`,
  `record_highlight` (commit=True), `get_coup_de_coeur` (2 queries) et
  `select_actu_decalee` → short sessions.
- `app/services/perspective_service.py` — `resolve_bias` + `search_internal_perspectives`
  → short sessions. Les calls Google News / Mistral restent hors transaction.
- `app/services/editorial/pipeline.py` — propage `session_maker` aux trois
  services ci-dessus ; SELECT logos encapsulé en short session.
- `app/services/digest_selector.py` — reçoit `session_maker`, le passe à
  `EditorialPipelineService`, **commit la session injectée juste avant
  `compute_global_context`** pour rendre la connexion au pool.
- `app/services/digest_service.py` — expose `session_maker` sur le
  constructeur et le passe à `DigestSelector`.

Call sites mis à jour :
- `app/routers/digest.py` : `get_digest`, `_gen_variant`, `generate_digest`
  instancient `DigestService(db, session_maker=async_session_maker)`.
- `app/jobs/digest_generation_job.py` : 3 sites (l. 168, 595, 865) passent
  `session_maker=async_session_maker` à `EditorialPipelineService` et
  `DigestSelector`.

Test ajouté :
`tests/editorial/test_deep_matcher.py::test_uses_session_maker_and_does_not_touch_injected_session`
— verrouille l'invariant "quand un maker est fourni, la session injectée
n'est JAMAIS touchée" (échec = régression directe vers le leak).

### P2 — RSS sync (Site A)

Pattern : **short session par entry**, I/O externes (httpx, trafilatura,
_fetch_html_head) **hors session**. `_save_content` renvoie désormais un
tuple `(is_new, content_id, needs_enrich, url)` pour que l'enrichissement
trafilatura se fasse après commit+close. Fichier : `app/services/sync_service.py`
(~400 lignes impactées). Test `test_save_content_deduplication` adapté au
nouveau contrat de retour.

### P3 — Hygiène transverse

- `app/main.py` — `socket.setdefaulttimeout(30)` posé très tôt. Filet contre
  un thread executor bloqué byte-par-byte par un upstream stall.
- `app/services/briefing_service.py:269-290` — `feedparser.parse(url)`
  remplacé par pattern `httpx.AsyncClient.get(...) + feedparser.parse(content)`
  (timeout=10s explicite). Même landmine corrigée à `digest_selector.py:1526`.

### Validation

- `pytest tests/editorial/ tests/test_sync_service.py -q` → 100 passed
- `pytest tests/editorial/test_deep_matcher.py -q` → 11 passed (dont le test
  session_maker ajouté)
- Full non-DB suite (462 passed, 13 skipped). Les tests DB-dépendants
  échouent uniquement parce que le Postgres local n'est pas disponible —
  indépendant de ce fix.

### À suivre post-merge

1. Observer `pg_stat_activity` pendant 48 h. Les sessions idle in transaction
   de + de 5 min doivent disparaître.
2. **Nettoyage P0** (PR séparée) : retirer le scheduled restart 01h/09h/17h
   Paris une fois la pg_stat_activity clean confirmée sur 48 h.

---

## Round 3 — 2026-04-16 (analyse Sentry live)

### Constat

Round 2 deployé (release Sentry `654588e3…`, alembic `ln01`). Crash persistant
malgré :
- Site F OK (logs `digest_generation_timeout` tracés correctement 01:20-01:22
  Paris, 5 événements d'affilée).
- Request-budget middleware actif, mais **pas déclenché** : le pool saturé
  tue la requête avec `QueuePool limit … reached` avant que le budget 60s
  ne soit atteint.

Traces Sentry du 2026-04-15 au 2026-04-16, 1 seul user testant (UA `Dart/3.10`,
IP `86.252.7.47`) :

| UTC | Sentry | Culprit | Signature |
|-----|--------|---------|-----------|
| 23:00 | PYTHON-4 | `apscheduler.executors.default` | `OperationalError: server closed the connection unexpectedly` |
| 23:11 | PYTHON-5 | `app.database.init_db` | `InternalError: DbHandler exited` sur `SELECT pg_catalog.version()` |
| 23:11 | PYTHON-6 | `app.main.readiness_check` | `PendingRollbackError: Can't reconnect until invalid transaction is rolled back` |
| 23:35 | PYTHON-E | `app.routers.feed.get_personalized_feed` | `QueuePool limit of size 10 overflow 10, connection timed out` |
| 23:37 | PYTHON-M | `app.routers.digest.get_both_digests` | idem |

### Cause racine (R1 / R2 / R3)

**R1 — Supabase/PgBouncer tue les connexions de façon asynchrone.** Les
signatures `DbHandler exited`, `server closed the connection unexpectedly`,
`consuming input failed` n'étaient PAS classées comme `is_disconnect=True`
par SQLAlchemy. Résultat : le slot restait dans le pool en état invalide,
toutes les requêtes suivantes levaient `PendingRollbackError`, le pool
se remplissait de zombies jusqu'à `QueuePool limit reached`.

**R2 — `_scheduled_restart` (01/09/17h Paris) amplifiait la fuite.** SIGTERM
sur un process avec un job APScheduler en cours → connexion DB coupée brutalement
côté pooler → `server closed the connection unexpectedly`. Au redémarrage,
Supabase renvoyait parfois un pooler dans un état dégradé (`DbHandler exited`
dès le `SELECT pg_catalog.version()` d'`init_db`).

**R3 — Sessions partagées entre users dans `top3_job.py`.** Une seule
session ouverte pour tout le batch : échec sur user N → session en
`PendingRollbackError` → tous les users N+1 à N+M échouaient en cascade.
Contribution directe à la saturation du pool.

### Fixes Round 3 (ce document)

**F0.1 — Table manquante `source_search_cache`** (SQL via Supabase SQL Editor).
Non liée aux crashes, mais fait du bruit dans Sentry (PYTHON-S, PYTHON-1).

**F0.2 — Coercion `DigestTopic.divergence_analysis`**
(`app/services/editorial/pipeline.py`, `app/services/digest_service.py`).
Le LLM renvoyait parfois un dict, le schéma Pydantic attendait une string.
Erreur de validation qui cassait `get_both_digests` (PYTHON-R) indépendamment
du pool.

**F0.3 — Parse défensif `DailyDigest.items`**
(`app/services/recommendation_service.py:269+`). Si `items` est stocké en
string JSON au lieu de list, `feed_digest_exclusion_failed` loggait un
warning et le feed n'excluait pas les articles déjà dans le digest.

**F1.1 — Listener SQLAlchemy `handle_error` pour invalidation pool**
(`app/database.py`). `event.listens_for(engine.sync_engine, "handle_error")`
détecte les signatures Supabase-kill (`server closed the connection`,
`dbhandler exited`, `consuming input failed`, etc.) et force
`is_disconnect=True`. SQLAlchemy évacue alors le slot au lieu de le
remettre dans le pool avec une connexion morte.

**F1.2 — Hardening `get_db()`** (`app/database.py`). `rollback()` et
`close()` maintenant wrappés en try/except pour que l'échec d'un
cleanup sur connexion déjà morte ne masque pas l'exception originale du
handler (plus de cascade confuse de `PendingRollbackError` dans Sentry).

**F1.3 — Isolation session par user dans `top3_job.py`**
(`app/workers/top3_job.py`). Chaque user ouvre maintenant sa propre
session courte via `async_session_maker()` avec rollback explicite sur
exception. Une erreur sur user N n'empoisonne plus le reste du batch.
- `sync_all_sources` déjà conforme depuis P2.
- `run_digest_generation::_process_batch` déjà conforme (session fresh
  par user dans `process_with_limit`).
- `_digest_watchdog` déjà conforme.

**F2.3 — Semaphore trafilatura** (`app/routers/contents.py`).
`asyncio.Semaphore(3)` module-level qui borne à 3 extractions concurrentes.
Empêche `get_content_detail` / `get_perspectives` / `update_content_status`
(PYTHON-F/H/J) de saturer l'executor + le pool quand plusieurs articles
sont ouverts en parallèle.

### À ne PAS retirer encore

- `_scheduled_restart` à conserver pendant la validation 48 h des fixes
  F1.x. S'il se confirme que Sentry ne remonte plus `QueuePool limit` ni
  `PendingRollbackError`, on pourra proposer un retrait en PR séparée.

### Validation attendue

- Sentry : 0 événement `QueuePool limit` sur 24 h.
- Sentry : `DbHandler exited` rare (< 5/jour) et sans cascade
  `PendingRollbackError`.
- `/api/health/pool` : `checked_out` < 10 en steady state.
- Test solo 01:35 Paris post-restart : pas de reproduction du crash.

---

## Round 4 — 2026-04-16 (burst /api/feed/ web app)

### Constat

Round 3 deployé (release `0a7aa275`, merge `2026-04-16 08:52 UTC`).
Quatre heures plus tard (`12:50–12:51 UTC`, release `9eade82e` = main +
PR #415/#416), Sentry remonte un nouveau pic massif **NON couvert par
Round 3** :

| Sentry ID | Type | Culprit | Events |
|-----------|------|---------|--------|
| PYTHON-1C/D/E/F/G/H/J/M | `QueuePool limit … overflow 10 reached` | `feed.get_personalized_feed` (×6), `users.get_streak`, `custom_topics.list_topics`, `digest.get_both_digests` | 8 issues |
| PYTHON-Y/1B/1K/1M/1N/15/16 | `InternalError: DbHandler exited` | `feed.get_personalized_feed` (×3), `users.get_streak`, `custom_topics.list_topics`, `sources.get_sources`, `collections.list_collections` | 7 issues |
| PYTHON-14 | `PendingRollbackError` | `community.get_community_recommendations` | 1 issue |

User unique `61140df7-1029-4d46-811e-7f309574c556`, **Chrome 147 web**
(pas iPhone/Dart — handoff précédent erroné). 16 issues distinctes en
~70 secondes — burst de requêtes parallèles depuis l'app web.

### Cause racine (R4)

**`/api/feed/` tient 3 connexions DB simultanées par requête** :
- `db: AsyncSession = Depends(get_db)` (session principale, vivante toute
  la requête)
- `_batch_user_context()` ouvre une short session dédiée
- `_batch_personalization()` ouvre une autre short session dédiée
- Les deux short sessions tournent en parallèle via `asyncio.gather`.

Pool config (Round 1/2) : `pool_size=10 + max_overflow=10 = 20` max.
À 3 conn/req, le plafond effectif est **~6-7 requêtes feed concurrentes**.
Un burst d'ouverture d'app web (Chrome ouvre `/api/feed/`,
`/api/users/streak`, `/api/digest/both`, `/api/sources/`,
`/api/collections/`, etc. en parallèle) sature le pool en quelques
secondes. Les requêtes suivantes attendent `pool_timeout=30s` puis
remontent `QueuePool limit reached`. Pendant que le pool est saturé,
Supabase peut tuer des connexions idle → `DbHandler exited` cascade.

Round 3 (listener `_invalidate_on_supabase_kill` + per-user session
`top3_job` + semaphore trafilatura) ne touchait pas `/api/feed/` —
le listener invalide les slots morts mais ne réduit pas la pression
de connexions vivantes tenues trop longtemps.

### Fix Round 4

**F4.1 — `/api/feed/` : 3 sessions → 2 sessions** (`app/services/recommendation_service.py::RecommendationService.get_feed`).

Le batch `_batch_user_context()` (3 SELECTs profile + sources + subtopics)
réutilise désormais `self.session` au lieu d'ouvrir une nouvelle short
session. `_batch_personalization()` reste sur sa propre short session
parallèle. `asyncio.gather` préserve le parallélisme entre les deux
batches (sessions distinctes, pas de "concurrent operations on same
session").

Net : **2 conn/req** (au lieu de 3), plafond ~10 feeds concurrents
(au lieu de ~6). Aucun changement sur `pool_size`/`max_overflow`/
`pool_timeout`/`pool_recycle`.

### À ne PAS faire (refusé pour cette PR)

- Augmenter `pool_size`/`max_overflow` : interdit sans diff métrique
  solide (cf. handoff). Masquerait l'amplification.
- Retirer `_scheduled_restart` : conserver pendant 48 h post-F1.1.
- Ajouter un nouvel endpoint pool-stats : `/api/health/pool` existe déjà
  (`app/main.py:455`) avec `status`/`usage_pct`/Sentry warning à 75 %.
- Ajouter `wait_for` budgets endpoint-level sur `/feed/`, `/streak/`,
  etc. : changerait la nature du timeout sans réduire la cause
  (saturation). À envisager seulement si le burst persiste post-F4.1.

### Validation attendue (post-déploiement)

- Sentry : 0 événement `QueuePool limit` sur `feed.get_personalized_feed`
  pendant 24 h.
- `/api/health/pool` pendant un burst Chrome (rapid tab switches) :
  `checked_out + overflow ≤ 14` (vs ~20 avant).
- Log `feed_phase1_context` `duration_ms` : régression acceptable
  (< +200ms p50).
- 48 h Sentry watch : pas de récurrence des signatures Round 3
  (`db_connection_invalidated_by_signature` reste rare).

---

## Round 5 — PLAN (en attente GO utilisateur)

**Statut** : PLAN — pas encore implémenté
**Branche** : `claude/debug-infinite-load-Lnryd`
**PR cible** : `main`

### Hypothèse cause racine R5 — amplification des appels `/api/feed/`

Les Rounds 1-4 ont tous été **tactiques** (timeout/gather, listener, sessions
courtes, 3→2 conn/req). La récurrence suggère un problème de **volume** pas
de latence unitaire :

1. **PR #423** (preload + stale-while-revalidate) déclenche `feed_preload_provider`
   dès `isAuthenticated && isEmailConfirmed && !needsOnboarding`, puis
   `_scheduleSilentRevalidation()` re-tape `/api/feed/?page=1` immédiatement
   après chaque cache hit. Résultat observable (`feed_provider.dart:140`) :
   **2-3 appels `/api/feed/` par session utilisateur là où il y en avait 1**.
2. **PR #426** (pull-to-refresh mode chrono) ajoute un chemin supplémentaire.
3. **PR #425** (recovery 403) relance les retries plus souvent.

Hot-path `/api/feed/` (analyse `recommendation_service.py`) tient **2 conns
pendant 1,5-5 s** : 500 candidats scorés + `_build_carousels` fait 7-12
SELECTs **séquentiels** sur la session principale (L1036 consumed_ids, L167-196
perspectives ×2, L1209 decale, L1283-1297 new_source, L1361 community,
L1443 saved). Aucune protection cache applicative côté backend.

À +100 DAU, 2-3× le volume d'appels sature le plafond effectif (~10 feeds
concurrents après R4). Les tunes pool ne tiennent plus la croissance.

### Approche

**Deux leviers complémentaires** : (1) réduire côté mobile les appels
redondants à l'intérieur d'une même fenêtre de 30-60 s ; (2) casser côté
backend la règle « chaque `/api/feed/` = full recompute DB » via un cache
applicatif court keyé par user, TTL 30 s, invalidé aux writes.

---

### R5.1 — Quick wins mobile (debounce + dedupe)

**Objectif** : supprimer les doubles appels `/api/feed/?page=1` déclenchés
en cascade par preload + silent revalidation dans la même fenêtre courte.

**Fichiers** :
- `apps/mobile/lib/features/feed/providers/feed_provider.dart:140`
- `apps/mobile/lib/features/feed/providers/feed_preload_provider.dart:33`
- `apps/mobile/lib/features/feed/repositories/feed_repository.dart:86`

**Changements** :

1. **Skip silent revalidation si cache < 60 s** (`feed_provider.dart:140`).
   Si `cached.savedAt` est récent (< 60 s), ne pas relancer `_fetchPage(1)`
   en background — la donnée vient d'être écrite, probablement par le
   preload. Garde la stale-while-revalidate intacte au-delà de 60 s.

2. **Gate preload sur dernier fetch** (`feed_preload_provider.dart`). Ajouter
   une vérification `cache.readRaw(userId)?.savedAt` > `now - 60s` : si le
   cache est très frais, le preload est inutile (le user vient juste de
   fermer/rouvrir l'app, les données sont déjà là).

3. **Debounce applicatif `/api/feed/?page=1`** (`feed_repository.dart`).
   `static DateTime? _lastDefaultFetchAt` + `static Future<FeedResponse>?
   _inflight` au niveau `FeedRepository`. Sur `getFeedWithRaw(page:1, default)`:
   - si un fetch est in-flight, retourner le même future (dedupe)
   - si le dernier fetch a < 5 s, retourner la future déjà résolue via cache
   
   **Scope** : page=1 + serein off + pas de filtre (seule vue pertinente pour
   le cache). Pas de debounce sur les autres fetch (filtre, loadMore, refresh
   explicite via pull-to-refresh qui doit rester responsive).

**Note sur le pull-to-refresh** : l'appel via `refresh()` et
`refreshArticlesWithSnapshot` doit **bypasser** le debounce (geste user
explicite). Une variante `getFeedWithRaw(..., forceFresh: true)` permet ça.

**Gain attendu** : -40 à -60 % du volume `/api/feed/` par session.

---

### R5.2 — Big fix backend : cache applicatif per-user feed page-1 TTL 30 s

**Objectif** (≥90 % confiance sur la cause racine) : neutraliser l'effet de
l'amplification mobile **et** protéger le backend contre tout futur PR qui
déclencherait plus d'appels `/api/feed/`. Un cache 30 s TTL avec invalidation
aux writes rend le pool DB insensible au volume d'ouvertures feed.

**Pourquoi >90 % confiance sur la racine** :
- Les 4 rounds précédents ont réduit conns/req (3→2), timeouts, sessions
  courtes — mais jamais attaqué **« pourquoi recomputer identique »** à chaque
  ouverture. Dans une fenêtre de 30 s, l'output est identique à 99 %
  (même scoring, même candidats, même user state). Le cache est conceptuellement
  gratuit.
- Sentry Round 3-4 confirme le mode de panne : pool saturé par `feed.get_personalized_feed`
  × N, pas par latence unitaire. Si N effectif devient ~N/10 (cache hit rate
  attendu), la saturation disparaît mécaniquement.
- Pas de risque de staleness visible : 30 s est invisible pour l'UX (le user
  vient de voir le feed il y a < 30 s de toute façon), et toute écriture
  user (save/like/hide/mute/impress/refresh) invalide immédiatement sa clé.

**Fichier** : nouveau `packages/api/app/services/feed_cache.py` + wiring dans
`packages/api/app/routers/feed.py`.

**Implémentation** :

```python
# feed_cache.py
import asyncio
import time
from dataclasses import dataclass
from uuid import UUID

@dataclass
class _Entry:
    expires_at: float
    payload: bytes  # orjson-serialized FeedResponse

class FeedPageCache:
    """In-memory per-user cache for /api/feed/ page 1 default view.

    TTL 30 s. Single-flight via per-user asyncio.Lock to avoid thundering herd
    on cache miss. Invalidation API for write handlers."""

    def __init__(self, ttl_seconds: float = 30.0) -> None:
        self._ttl = ttl_seconds
        self._entries: dict[UUID, _Entry] = {}
        self._locks: dict[UUID, asyncio.Lock] = {}

    def _lock(self, user_id: UUID) -> asyncio.Lock:
        lock = self._locks.get(user_id)
        if lock is None:
            lock = asyncio.Lock()
            self._locks[user_id] = lock
        return lock

    def get(self, user_id: UUID) -> bytes | None:
        e = self._entries.get(user_id)
        if e is None or e.expires_at < time.monotonic():
            return None
        return e.payload

    def put(self, user_id: UUID, payload: bytes) -> None:
        self._entries[user_id] = _Entry(
            expires_at=time.monotonic() + self._ttl, payload=payload
        )

    def invalidate(self, user_id: UUID) -> None:
        self._entries.pop(user_id, None)

FEED_CACHE = FeedPageCache()
```

**Wiring dans `/api/feed/`** (feed.py:61) :

- **Scope d'éligibilité** cache : `offset == 0 and limit == 20 and not any filter
  (mode, theme, topic, source_id, entity, keyword) and not serein and not saved_only`.
  Exactement la vue par défaut mobile.
- Sur hit : `return Response(content=payload, media_type="application/json")`
  (bypass Pydantic serialization).
- Sur miss : prendre `FEED_CACHE._lock(user_uuid)`, re-check (double-check
  pattern), sinon compute normalement, `orjson.dumps(response.model_dump())`
  → `FEED_CACHE.put(user_uuid, payload)` → return.

**Invalidation hooks** (appels explicites `FEED_CACHE.invalidate(user_uuid)`) :
- `POST /api/feed/refresh` (feed.py:228)
- `POST /api/feed/refresh/undo` (feed.py:302)
- `POST /api/contents/{id}/impress` (contents.py:374)
- `PATCH /api/contents/{id}` status/saved/liked (routers/contents.py)
- `POST /api/contents/{id}/hide` + `unhide`
- `POST /api/personalization/mute-source|mute-topic|mute-theme|mute-content-type`

**Mesures et garde-fous** :
- Métrique simple : counter stderr `feed_cache hit=N miss=M` toutes les 60 s.
- Pas de limite dure sur la taille (une entrée ≈ 150 KB × 100 DAU = 15 MB max).
- Si un bug de fraîcheur est détecté : **feature flag** via env var
  `FEED_CACHE_TTL_SECONDS=0` désactive le cache sans redéploiement.

**Gain attendu** :
- DB calls `/api/feed/` : -70 à -90 % (hit rate attendu ~80 % sur la fenêtre).
- `/api/health/pool` `checked_out` p95 : < 10 au lieu de 14-18 lors des
  bursts Chrome.
- Latence p50 hit : ~5-20 ms vs 1,5-5 s (facteur ×100-200).

---

### R5.3 — Tests

**Backend** :
- `tests/services/test_feed_cache.py` : TTL expiry, invalidation, single-flight
  (10 tâches concurrentes → 1 seul compute).
- `tests/routers/test_feed_cache.py` : hit retourne payload identique, miss
  populate, écritures invalidante (refresh/impress/save/mute/hide).
- Non-regression : filtres (theme/topic/source) **bypass** le cache.

**Mobile** :
- `test/features/feed/providers/feed_provider_silent_reval_test.dart` : cache
  < 60 s → pas de silent reval ; cache > 60 s → silent reval appelé.
- `test/features/feed/repositories/feed_repository_debounce_test.dart` : 3
  appels simultanés `getFeedWithRaw(page:1, default)` → 1 seul réseau.
- `test/features/feed/providers/feed_preload_provider_test.dart` : cache
  récent → pas de preload.

### R5.4 — Critères d'acceptation

- [ ] Hit rate cache backend ≥ 70 % sur la fenêtre 30 s (métrique stderr).
- [ ] Sentry : 0 `QueuePool limit` sur `/api/feed/` pendant 72 h post-deploy.
- [ ] `/api/health/pool` `checked_out` p95 ≤ 10 pendant les heures de pic.
- [ ] Aucun ticket support « feed obsolète » (sanity check staleness).
- [ ] Volume `/api/feed/` par session mobile divisé par ≥ 2 (Sentry perf).

### R5.5 — Hors-scope Round 5

- Split `_build_carousels` en endpoint séparé `/api/feed/carousels` (gain
  marginal comparé au cache, ajoute complexité client).
- Offline precompute des feeds (option B de l'analyse systémique — ROI élevé
  mais refonte de 5-7 j).
- Read replica Supabase (option G — à évaluer après mesure R5.2).
- Augmentation `pool_size` — toujours interdite sans preuve métrique.
