# Bug — Crashs serveur récurrents + dépendance au restart manuel

**Statut** : PLAN (en attente GO utilisateur)
**Branche** : `claude/fix-server-crashes-kUYo1`
**Sévérité** : 🔴 P0 (impact user direct plusieurs fois/jour)
**Rapporté** : 2026-04-23 (Laurin)

---

## Symptômes rapportés

1. **Crash matinal récurrent** après génération du digest (~9 h Paris)
2. **2–3 crashs supplémentaires par jour** à des heures reproductibles
3. Chaque crash nécessite un **restart manuel** des services Railway (Web + API)
4. Les **endpoints `sources/*`** continuent parfois à 500 même après restart et ne refonctionnent qu'après plusieurs relances

---

## Investigation — cause racine du crash matinal

### 🎯 Le « crash » de 9 h n'est pas un crash : c'est un SIGTERM programmé que Railway ne relance pas

**Site 1** — `packages/api/app/workers/scheduler.py:90-125`

```python
async def _scheduled_restart() -> None:
    """Restart périodique pour purger la fuite de sessions SQLAlchemy."""
    logger.warning("scheduled_restart_initiated", ...)
    os.kill(os.getpid(), signal.SIGTERM)
```

Ce job tourne via APScheduler à **01:00, 09:00 et 17:00 Europe/Paris** — soit
**exactement 3 fois/jour**, ce qui colle au symptôme « chaque matin + plusieurs
fois par jour ». Le 09:00 tombe pile après la fin du batch digest (06:00 →
07:30 watchdog → 08:00 top3), d'où l'association « après génération digest ».

**Site 2** — `railway.json:10` + `railway.toml:8-9`

```json
"restartPolicyType": "ON_FAILURE"
```
```toml
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 3
```

**Mécanisme du « crash » observé** :

1. 09:00 Paris — `_scheduled_restart()` émet `SIGTERM`.
2. uvicorn draine les requêtes en cours (comportement normal) et le process exit **avec le code 0**.
3. Railway voit un exit 0 → interprète « l'application s'est terminée
   proprement, rien à redémarrer » (c'est la sémantique de `ON_FAILURE` : on
   redémarre seulement sur exit non-zéro ou crash OOM/segfault).
4. Le container reste arrêté → l'app est down → utilisateurs voient « charge
   infini » jusqu'au restart manuel.

> Historique : `_scheduled_restart` a été ajouté comme *mitigation temporaire*
> de la fuite de sessions SQLAlchemy (cf. `docs/bugs/bug-infinite-load-requests.md`
> sections Round 2/3). Le commentaire lui-même dit : « À retirer dès que le
> fix architectural (P1/P2 du bug doc) est déployé et validé ≥ 48 h sans
> retour à saturation du pool. » Ces fixes (short sessions pipeline éditoriale
> + RSS sync + invalidation Supabase-kill + per-user session isolation)
> **sont déployés depuis 2026-04-15** — plus d'une semaine. La mitigation
> a survécu à sa raison d'être et se retourne aujourd'hui contre nous.

### Pourquoi les endpoints `sources/*` crashent parfois aussi après restart

Hypothèse primaire (confirmée par la lecture du code, à croiser avec Sentry une
fois les accès restaurés — cf. `[FAIL]` du healthcheck de cette session) :

- `SourceService.add_custom_source` déclenche `background_tasks.add_task(sync_source, ...)` (`routers/sources.py:377`). Le worker `sync_source` peut tenir la session DB longtemps (httpx fetch + trafilatura extract) → pression pool juste après un startup où Supabase est encore en cold path.
- `smart_source_search.py` fait 6 appels externes (YouTube, Reddit, Brave, Google News, Mistral) en cascade. Si un provider stall, le thread executor se remplit.
- Après un `_scheduled_restart()`, les connexions Supabase sont fraîches mais `init_db()` fait des probes DNS + TCP dans un executor (cf. `database.py:190-240`). Si le premier req `/api/sources` arrive pendant ce warm-up → 503 transitoire.

Le premier symptôme (9 h systématique) est largement dominant. Le second est
une conséquence secondaire de la même racine (pression pool pendant restart),
accessoirement aggravée par des paths externes non rate-limités.

---

## Plan — 2 temps

### PHASE 1 — Stopper l'hémorragie (auto-restart + détection, 24-48 h)

Objectif : **plus aucun restart manuel** n'est nécessaire pour maintenir
l'app disponible, même si des crashs résiduels subsistent.

#### F1.1 — Aligner Railway sur `restartPolicyType: "ALWAYS"` ⚡️ fix principal

Fichiers : `railway.json`, `railway.toml`

```json
"restartPolicyType": "ALWAYS"
```
```toml
restartPolicyType = "ALWAYS"
restartPolicyMaxRetries = 10
```

Effet : Railway relance le container à chaque exit (code 0 comme != 0), ce
qui rattrape immédiatement le `SIGTERM` programmé **sans le désactiver**.
Couvre aussi tout futur exit propre mal géré (OOM adjacent, uvicorn qui quit
sur shutdown path mal câblé, etc.).

Risque : **très faible**. `ALWAYS` est la policy par défaut pour la majorité
des services HTTP sur Railway. La boucle de crash infini est bornée par
`maxRetries=10` + le healthcheck (120 s timeout) qui marquera le déploiement
`UNHEALTHY` si l'app ne se stabilise pas.

Réversible en une ligne si problème.

#### F1.2 — Désactiver `_scheduled_restart()` (les fixes P1/P2 sont en prod depuis une semaine)

Fichier : `packages/api/app/workers/scheduler.py`

Option A (recommandée) : retirer l'ajout du job `scheduled_restart` dans
`start_scheduler()` (lignes 184-191) et laisser la fonction `_scheduled_restart`
en place commentée pendant 48 h au cas où on devrait rollback.

Option B (plus conservatrice) : garder le job mais remplacer
`os.kill(SIGTERM)` par `await engine.dispose()` — recycle les connexions du
pool SQLAlchemy sans tuer le process. Moins bon que A car ça ne traite pas
un vrai leak si un réapparaissait.

Prérequis de validation : observer `/api/health/pool` pendant 48 h après
merge. Si `checked_out` reste < 15 en steady-state → le leak est effectivement
corrigé, on peut retirer sans risque.

#### F1.3 — Monitor externe + auto-restart (ceinture + bretelles)

Mettre en place un monitor indépendant de Railway :

- **Option low-cost** : [Healthchecks.io](https://healthchecks.io) (gratuit
  jusqu'à 20 checks) ou [Better Uptime](https://betteruptime.com) (gratuit
  pour 10 monitors).
- Ping `GET /api/health/ready` toutes les 60 s (pas `/api/health` — le
  liveness probe ne vérifie pas la DB).
- Sur 2 fails consécutifs : webhook → Railway API (`POST /services/{id}/restart`)
  + notification push (Telegram/email/Slack).

Bonus : le monitor historisera les périodes de downtime → métrique objective
pour prioriser la suite.

#### F1.4 — Alertes Sentry sur les signatures crash

Rules à configurer dans l'UI Sentry (pas de code) :

| Signature                                | Seuil      | Priorité |
|------------------------------------------|------------|----------|
| `QueuePool limit ... reached`            | ≥ 3/min    | P0 push  |
| `digest_generation_timeout`              | ≥ 5/min    | P0 push  |
| `db_pool_pressure_high` + `usage_pct>90` | ≥ 2/min    | P1 email |
| `db_connection_invalidated_by_signature` | ≥ 10/h     | P1 email |

---

### PHASE 2 — Robustesse structurelle (priorisé par ROI)

Une fois la Phase 1 stabilisée (= app toujours up sans intervention pendant
7 jours consécutifs), attaquer les causes profondes.

#### F2.1 — Isoler le scheduler sur un worker Railway dédié (ROI ⭐️⭐️⭐️)

Aujourd'hui `AsyncIOScheduler` tourne dans le même event loop que uvicorn.
Pendant `run_digest_generation` (06:00, 3-5 min de pipeline LLM pour
N users), l'API est pressurisée : pool DB partagé, CPU/IO asyncio compétition,
et surtout *si le batch crash il prend l'API avec lui*.

Fix : créer un service Railway `facteur-worker` (Dockerfile identique,
`CMD` différente : `python -m app.workers.run_scheduler`). Le service `api`
ne gère que les requêtes HTTP. Le scheduler, RSS sync, digest generation,
top3, cleanup, tournent dans le worker.

Effet attendu :
- Plus de pool contention pendant le batch
- Un crash du worker n'impacte plus l'API
- Dimensionnement indépendant (le worker peut être plus gras sans coût API)

Coût : refactor modéré (1-2 jours). Tests E2E à valider : le flow on-demand
`get_or_create_digest` doit continuer à marcher depuis l'API.

#### F2.2 — Request budget middleware (ROI ⭐️⭐️)

Le middleware `request_budget` a été retiré (commit `cf882aa`) avec l'idée
de ne pas masquer les vrais bugs. Maintenant qu'on a les timeouts unitaires
(digest/feed) + la dédup singleflight, on peut le remettre en **filet de
sécurité** seulement : wrap chaque handler dans `asyncio.wait_for(90 s)` +
log `request_budget_exceeded path=X method=Y user=Z`.

Bénéfice : n'importe quel futur endpoint ajouté sans timeout unitaire est
borné par défaut → on ne régresse plus sur un single endpoint oublié.

#### F2.3 — Email confirmation check hors-DB (ROI ⭐️⭐️)

`dependencies.py:78-116` fait `SELECT email_confirmed_at FROM user_profiles`
sur chaque requête (cache 1 h, mais premier hit/h = DB). À 100 DAU × 20 req/h,
ça fait ~2000 checks/h juste pour un champ qui est déjà dans le JWT Supabase
(`user_metadata.email_verified`).

Fix : décoder le JWT (déjà fait), lire `email_confirmed_at` du payload, zéro
DB. Fallback DB uniquement si le champ manque (users très anciens).

#### F2.4 — Circuit breaker sur les providers externes (ROI ⭐️⭐️)

`smart_source_search.py` appelle YouTube/Reddit/Brave/Google News/Mistral
en cascade. Chaque provider a ses timeouts mais rien ne court-circuite un
provider qui devient *lent mais pas timeout* (reply en 9 s au lieu de 10 s).

Fix : `pybreaker` ou `circuitbreaker` par provider. Après N erreurs dans une
fenêtre courte, le breaker ouvre et fail-fast pendant un cooldown.

#### F2.5 — Observabilité pool en continu (ROI ⭐️)

Tâche asyncio background qui sample `/api/health/pool` toutes les 30 s et
émet Sentry breadcrumb. Dashboard Railway custom-log pour voir le
`checked_out` en time series (pas juste des spikes ponctuels).

#### F2.6 — Rate limit plus large côté API (ROI ⭐️)

Actuellement `_check_search_endpoint_rate` (10/min) ne couvre que
`/smart-search`. Étendre (via un middleware simple token-bucket par user_id)
à `/api/feed/`, `/api/digest/both`, `/api/sources` :
- `/feed/` : 30/min (le singleflight aide pour le digest, pas le feed)
- `/digest/both` : 6/min (singleflight + cette borne = ceinture++)
- `/sources` : 60/min

Ne résout pas la racine mais pose un plafond propre si un bug mobile spam.

#### F2.7 — Scalabilité horizontale (phase 3, après F2.1)

Prérequis : F2.1 fait. Ensuite :

1. **Redis (Upstash)** pour remplacer `FEED_CACHE` in-process par un cache
   partagé — nécessaire pour scaler à 2+ instances API.
2. **Read replica Supabase** pour les read paths feed/digest. Les writes
   (user actions) restent sur primary.
3. **Horizontal scaling Railway** (2 instances API derrière LB) + invalidation
   cache via Redis pub/sub.

À ne démarrer qu'à partir de ~500 DAU ou si F2.1-F2.6 ne suffisent plus.

---

## Ordonnancement proposé

```
Jour 0 (aujourd'hui) :
  └─ PR #1 : F1.1 (restart policy ALWAYS) + F1.2 (retirer scheduled_restart)
     → Merge + deploy + validation 24 h /api/health/pool

Jour 1-2 :
  ├─ F1.3 (monitor externe configuré, webhook Railway testé)
  └─ F1.4 (rules Sentry configurées)
  → Phase 1 close : plus de restart manuel requis, alerting en place

Jour 3-10 (en parallèle, priorité décroissante) :
  ├─ F2.1 (worker Railway dédié) ← gros ROI
  ├─ F2.2 (request budget middleware 90 s)
  ├─ F2.3 (email_confirmed check hors-DB)
  ├─ F2.4 (circuit breaker providers)
  ├─ F2.5 (observabilité pool)
  └─ F2.6 (rate limit élargi)

Jour 30+ : F2.7 si DAU x3
```

---

## Fichiers à modifier (Phase 1)

| Fichier                                  | Changement                                                |
|------------------------------------------|-----------------------------------------------------------|
| `railway.json`                           | `restartPolicyType: "ALWAYS"`                             |
| `railway.toml`                           | idem + `restartPolicyMaxRetries = 10`                     |
| `packages/api/app/workers/scheduler.py`  | Retirer `scheduler.add_job(_scheduled_restart, ...)`      |
| `docs/bugs/bug-server-crashes.md`        | Ce document                                               |
| `docs/bugs/bug-infinite-load-requests.md`| Marquer Round 2 `_scheduled_restart` comme **retiré**     |

Tests :
- `packages/api/tests/workers/test_scheduler.py` : ajouter assert « aucun
  job id `scheduled_restart` enregistré » pour éviter la régression.

Monitoring (hors code) :
- UptimeRobot / Healthchecks.io : ping `/api/health/ready` toutes les 60 s.
- Sentry rules : les 4 signatures du tableau F1.4.

---

## Checklist validation post-merge Phase 1

- [ ] `railway.json` + `railway.toml` mergés, déploiement observé dans
      l'interface Railway (pas de config error).
- [ ] Scheduler job `scheduled_restart` absent des logs startup (`logger.info("Scheduler started", ...)` doit lister seulement 5 jobs).
- [ ] 24 h sans restart manuel requis.
- [ ] `/api/health/pool` `checked_out` stable < 12 en steady-state.
- [ ] Monitor externe configuré, test de bascule validé (force un exit,
      vérifier que le monitor tire le restart dans < 2 min).
- [ ] Alertes Sentry reçues sur un test synthétique.

---

## Références

- `docs/bugs/bug-infinite-load-requests.md` — historique Rounds 1-6, toutes
  les mitigations pool.
- `docs/bugs/bug-digest-pipeline-reliability.md` — scheduler + watchdog.
- `docs/bugs/bug-digest-total-failure-2026-04-12.md` — Fix 2/4/5.
- `docs/bugs/bug-feed-default-hang.md` — timeout/fallback two-phase feed.
- `docs/bugs/bug-railway-healthcheck-migrations.md` — startup path.
