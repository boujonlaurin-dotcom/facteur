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

## Post-mortem — investigation 2026-04-14 (en cours)

Après merge des PR #396 + #397, les users rapportent que les requêtes hangent
toujours.

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
