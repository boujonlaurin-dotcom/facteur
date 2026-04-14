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

### Fix 5 — DNS/TCP startup checks non bloquants (PR #397)

`packages/api/app/database.py:init_db()`

`socket.gethostbyname()` et `socket.create_connection()` sont synchrones et
peuvent prendre 5-30s sur Railway au démarrage. Appelés directement dans une
coroutine du `lifespan`, ils bloquaient l'event loop et empêchaient uvicorn
de servir `/api/health` → Railway healthcheck timeout → redémarrage en
boucle. Désormais wrappés dans `loop.run_in_executor()`.

### Fix 6 — Budget global par requête HTTP (PR courante)

`packages/api/app/main.py:_REQUEST_BUDGET_S = 60.0`

Middleware qui borne **chaque** requête HTTP non-health à 60 s via
`asyncio.wait_for(call_next(request), ...)`. Au-delà :
- La task handler est annulée → sa session DB est libérée via le context
  manager de `get_db` → la connexion retourne au pool
- Le client reçoit `503 {"detail": "request_timeout"}` au lieu de hang
- Log `request_budget_exceeded` avec `path` + `method` → Sentry voit
  immédiatement quel endpoint est coupable

Pourquoi 60 s : `pool_timeout` est à 30 s, et `/digest/both` peut
légitimement prendre 25-30 s en cold path. 60 s laisse de la marge pour
des pointes normales tout en tuant les vrais hangs.

Exemptions : `/api/health*`, `/docs`, `/redoc`, `/openapi.json` — doivent
rester répondants sous stress pour diagnostic.

## Ce que ça règle / ne règle pas

✅ **Règle** : cascade hang → pool saturé → tout hang (Fix 1–3, 6)
✅ **Règle** : startup catchup qui peut geler pour toujours (Fix 2)
✅ **Règle** : mobile qui retente 9 min un 503 "permanent" (Fix 4)
✅ **Règle** : Railway healthcheck bloqué par DNS sync (Fix 5)
✅ **Règle** : n'importe quel autre endpoint non borné qui bloque le pool (Fix 6)
⚠️ **Ne règle pas la cause racine amont** (qui fait hanger Mistral/Google
News/Supabase ?). Les logs structlog existants + le nouveau endpoint pool
+ le log `request_budget_exceeded` donneront le signal pour identifier le
vrai coupable sans bloquer la prod.

## Tests

- `packages/api/tests/test_digest_both_timeout.py::test_digest_both_hanging_variant_returns_503_timeout`
- `packages/api/tests/test_health_pool.py::test_pool_endpoint_returns_metrics`
- `packages/api/tests/test_request_budget.py::test_healthcheck_never_times_out`
- `packages/api/tests/test_request_budget.py::test_slow_endpoint_gets_503`

## Post-mortem

PR à suivre : mesurer sur Railway pendant 24h la latence p99 `/digest/both`,
et le nombre de 503 `digest_generation_timeout`. Si > 1 % des requêtes, il
faudra remonter en amont (probablement Mistral timeout à réduire / circuit
breaker sur perspective analysis).
