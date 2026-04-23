# PR #465 — fix(infra): crashs serveur matinaux — restart policy ALWAYS + retrait mitigation SIGTERM

## Quoi

Railway était configuré en `restartPolicyType: ON_FAILURE`. Le job cron `_scheduled_restart` émettait un SIGTERM 3×/jour (01h/09h/17h Paris) comme mitigation temporaire d'une fuite de sessions SQLAlchemy — uvicorn drainait proprement (exit 0) → Railway ne relançait pas → l'app était down jusqu'au restart manuel. Ce PR passe Railway en `ALWAYS` et retire le job SIGTERM devenu obsolète.

## Pourquoi

`_scheduled_restart` était une mitigation P0 documentée dans `bug-infinite-load-requests.md` avec la note explicite « À retirer dès que les fixes P1/P2 sont déployés et validés ≥ 48h ». Ces fixes (sessions scoped, RSS timeout, pool isolation) sont en prod. La mitigation avait survécu à sa raison d'être et causait 3 pannes manuelles/jour.

## Fichiers modifiés

- **Config** : `railway.json` — `ON_FAILURE` → `ALWAYS` + `restartPolicyMaxRetries: 10`
- **Backend** : `packages/api/app/workers/scheduler.py` — retrait de `_scheduled_restart()`, son `add_job` (01h/09h/17h), et les imports `os`/`signal`
- **Tests** : `packages/api/tests/workers/test_scheduler.py` — 2 tests qui vérifiaient l'existence du job remplacés par un test de garde qui vérifie son absence (`test_scheduled_restart_job_is_not_registered`)
- **Docs** : `docs/bugs/bug-server-crashes.md` — nouveau bug doc (diagnostic + plan Phase 2 si nécessaire)

## Zones à risque

- **Retrait de la mitigation pool** : si P1/P2 n'est pas aussi stable qu'estimé, le pool peut re-saturer sans garde-fou. Signal clair : Sentry `QueuePool limit reached` → revert.
- **`ALWAYS` policy** : Railway relancera sur tout exit 0, y compris un futur shutdown intentionnel mal câblé. Borné par `maxRetries: 10`.

## Points d'attention pour le reviewer

1. **Hypothèse P1/P2 stable** : l'investigation est basée sur l'analyse statique du code (pas d'accès live à Sentry/Railway logs dans cette session). On pose que les fixes pool tiennent, mais le monitoring post-deploy est critique.
2. **`ALWAYS` ne couvre pas les hangs** : si le process reste vivant mais figé (pool saturé sans crash), Railway ne redémarre toujours pas — ce cas nécessiterait un monitor externe ou un liveness check DB. Documenté en Phase 2 du bug doc.
3. **Tests non exécutés localement** : pas de venv dans ce workspace. Validation AST OK, pytest à confirmer en CI.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **`_digest_watchdog`** (7h30 Paris) : non touché.
- **`bug-infinite-load-requests.md`** : les références à `_scheduled_restart` qu'il contient sont historiques, pas du code actif.
- **Pool config** (`database.py:43-44`) : `pool_size=10, max_overflow=10` (total 20 conns) inchangé — Phase 2 adressera si contention résiduelle.

## Comment tester

1. **Après deploy** — logs Railway au prochain créneau 09h00 Paris : ne plus voir `scheduled_restart_initiated`. Container doit rester up.
2. **Logs startup** : chercher le log `Scheduler started` avec le champ `jobs=["rss_sync", "daily_top3", "daily_digest", "digest_watchdog", "storage_cleanup"]`. Plus de `scheduled_restart_cron`.
3. **Stabilité 48h** : zéro restart manuel requis. Si Sentry `QueuePool limit reached` → `git revert 7144c98f`.
4. **CI** : `cd packages/api && pytest tests/workers/test_scheduler.py -v` — notamment `test_scheduled_restart_job_is_not_registered`.
