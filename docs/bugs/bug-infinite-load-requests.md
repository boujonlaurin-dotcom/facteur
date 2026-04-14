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

## Post-mortem — cause racine confirmée (2026-04-14)

Après merge des PR #396 + #397, les users rapportent que les requêtes hangent
toujours. Investigation : **la cause racine n'est pas dans `/digest/both` ni
dans le startup catchup**. C'est un thread executor leak systémique.

### Root cause : `feedparser.parse(url)` avec urllib sans timeout

Deux sites passent une **URL** (pas du contenu) à `feedparser.parse`, dans un
`run_in_executor` :

- `packages/api/app/services/digest_selector.py:1526`
  ```python
  feed = await loop.run_in_executor(None, fp.parse, url)
  ```
- `packages/api/app/services/briefing_service.py:274`
  ```python
  feed = await loop.run_in_executor(None, feedparser.parse, url)
  ```

Quand feedparser reçoit une URL, il utilise `urllib.request.urlopen()`
**en interne, de façon synchrone, sans timeout** (timeout=None par défaut,
aucun `socket.setdefaulttimeout()` n'est posé ailleurs). Si l'host du
`une_feed_url` d'une source est lent ou ne répond pas (TCP blackhole, TLS
handshake qui stalle, redirect loop, serveur surchargé), **le thread reste
vivant pour toujours**.

### Pourquoi c'est systémique (pas juste digest)

1. Le **default asyncio thread executor** est partagé par toute l'app. Sa
   taille par défaut est `min(32, os.cpu_count() + 4)` — typiquement 5-6
   threads sur un container Railway petit.
2. `_fetch_une_guids` fait `asyncio.gather(*[parse_feed(s.une_feed_url)])`
   → N tâches parallèles, N sources avec `une_feed_url` non-nul. Quelques
   hôtes lents suffisent à remplir l'executor.
3. Une fois l'executor saturé de threads zombies, **tout autre
   `run_in_executor` queue indéfiniment** :
   - La DNS check ajoutée par PR #397 (`socket.gethostbyname` in executor)
   - SQLAlchemy AsyncAdaptedQueuePool (sync driver operations)
   - Tout logger/librairie qui offload du blocking I/O
4. `asyncio.wait_for(..., timeout=25s)` autour de `_gen_variant` (PR #396)
   **annule la coroutine mais pas le thread**. `wait_for` est impuissant
   sur du code qui tourne dans un thread — la socket reste ouverte, le
   thread continue, il ne sera libéré que quand urllib rendra la main
   (jamais, pour un TCP blackhole).

### Chaîne d'appel complète

```
GET /api/digest                       (pas borné par PR #396, seul /both l'est)
  └─ DigestService.get_or_create_digest
       └─ DigestSelector.select_digest
            └─ if mode == "pour_vous" and not precomputed:
                 _build_global_trending_context        ← appelé aussi en batch job
                   └─ _fetch_une_guids
                        └─ asyncio.gather([parse_feed(url) for each source])
                             └─ run_in_executor(fp.parse, url)   🔴 HANG forever
```

Le **même hang** est présent dans le job batch quotidien (`top3_job.py` →
`BriefingService._build_global_context` → `briefing_service.py:274`) → les
catchups startup ne finissent pas avant 300s (timeout PR #396), mais
pendant ces 300s ils ont déjà pourri le thread pool.

### Amplificateur : session DB détenue pendant le hang

`_build_global_trending_context` tient la session SQLAlchemy pendant toute
la durée de `_fetch_une_guids`. Quand ça hang, la conn reste checkée-out.
Quelques requêtes coincées → pool à 20 saturé → toute nouvelle requête
attend `pool_timeout=30s` → 503 pour tout le monde → **symptôme "tout
charge à l'infini"**.

### Preuves

- **Code** : 2 sites concernés (grep ci-dessus), aucun `socket.setdefaulttimeout`
  ailleurs. Le pattern correct existe déjà à `rss_parser.py:149-171`
  (`await self.client.get(url)` puis `feedparser.parse(content)`).
- **Pourquoi #396/#397 n'ont rien changé** : les deux agissent *autour* du
  hang (timeout sur la coroutine, DNS déplacé), jamais *dedans* (annuler
  le thread bloqué est impossible en pur Python).
- **Pourquoi ça peut empirer avec #397** : mettre la DNS check dans l'executor
  est correct pour unblock uvicorn, mais elle queue derrière les threads
  feedparser zombies. Sous charge, ça dégrade le startup health.

### Décision commit `3d4ec06` (middleware request-budget 60s)

**Merger en défense en profondeur, oui.** Raisons :
- Il donnera la preuve logs `request_budget_exceeded` avec `path=/api/digest`
  (ou `/api/digest/generate`) qui confirme le site sur prod.
- Il libère les sessions DB des requêtes hangées (via cancel du handler).
- **Mais** il ne libère pas les threads executor — donc même avec lui, le
  thread pool continuera à se poisoner jusqu'à ce qu'on règle
  `_fetch_une_guids`.

→ Merger `3d4ec06` dans une PR séparée, puis attaquer le vrai fix juste
après.

### Fix root cause à faire

Remplacer les deux `feedparser.parse(url)` par le pattern async existant :

```python
async def parse_feed(url: str) -> list[str]:
    try:
        async with httpx.AsyncClient(timeout=7.0, follow_redirects=True) as client:
            resp = await client.get(url)
            resp.raise_for_status()
        feed = await asyncio.get_event_loop().run_in_executor(
            None, feedparser.parse, resp.content
        )
        return [entry.id if hasattr(entry, "id") else entry.link
                for entry in feed.entries[:5]]
    except Exception as e:
        logger.warning("une_feed_parse_failed", url=url, error=str(e))
        return []
```

Bornes complémentaires recommandées :
1. **Semaphore de concurrence** sur `_fetch_une_guids` (ex. `asyncio.Semaphore(5)`)
   pour éviter qu'un pic de sources lentes sature le loop en même temps.
2. **Cache 15-30 min** des résultats : le contenu "À la Une" ne change pas
   à chaque requête utilisateur — inutile de refetch 100× par heure.
3. (défense en profondeur) Poser `socket.setdefaulttimeout(15)` au top du
   module `main.py` pour couper net toute librairie sync qui oublierait
   un timeout — ceinture + bretelles.

### Vérification live recommandée une fois 3d4ec06 déployé

- Sentry : `message:"request_budget_exceeded"` groupé par `path`
  → attendu : `/api/digest` et `/api/digest/generate` en tête, éventuellement
  `/api/digest/both` résiduel.
- `curl https://<prod>/api/health/pool` en boucle pendant une minute :
  `checked_out` devrait retomber dès que les 60s budget auto-cancel
  libèrent les sessions (sans ça, `checked_out` restait coincé jusqu'à
  `pool_timeout`).
- Railway logs : chercher `une_feed_parse_failed` → liste les hôtes coupables
  (à corréler avec les sources actives en DB pour désactiver/fixer les
  feeds morts).
