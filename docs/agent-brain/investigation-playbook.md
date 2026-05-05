# Investigation Playbook — Incidents prod & bugs serveur

> **Point d'entrée unique** quand un agent doit comprendre une panne, un bug, ou une dégradation prod.
> Ce doc t'oriente vers les pistes les plus probables **sans rien fermer**. Lis la section qui correspond à ton symptôme, mais garde toujours l'esprit ouvert : la cause racine est rarement celle qu'on attend.

---

## 0. Prérequis — vérifier les accès

Le hook `SessionStart` lance un healthcheck `--fast` au démarrage. Scanne les lignes `[secrets]` dans les premiers messages :

```
[secrets] [OK]   connecté en tant que claude_analytics_ro
[secrets] [OK]   API Supabase répond 200 (PAT valide)
[secrets] [OK]   Railway GraphQL me{} OK
[secrets] [OK]   API Sentry /api/0/ répond 200
[secrets] [OK]   API PostHog OK (projet 129581)
```

Si un `[FAIL]` apparaît : `bash scripts/healthcheck-agent-secrets.sh` en mode complet, puis corrige le token avant d'investiguer. Référence : [docs/infra/claude-access-setup.md](../infra/claude-access-setup.md).

---

## 1. First 5 minutes — protocole universel de triage

**À faire dans cet ordre, quel que soit le symptôme**, avant toute hypothèse.

### 1.1 Probe live de l'app (≤ 30 s)

```bash
HOST=https://facteur-production.up.railway.app
echo "=== /api/health ===" ; curl -fsS -m 6 -w "\nHTTP=%{http_code} t=%{time_total}s\n" $HOST/api/health
echo "=== /api/health/ready ===" ; curl -sS -m 12 -w "\nHTTP=%{http_code} t=%{time_total}s\n" $HOST/api/health/ready
echo "=== /api/health/pool ===" ; curl -sS -m 6 -w "\nHTTP=%{http_code} t=%{time_total}s\n" $HOST/api/health/pool
```

| Résultat | Interprétation |
|---|---|
| `/health` 200 + `/ready` 200 + pool < 50% | App techniquement saine — le bug est plus haut (code, schema, route) |
| `/health` 200 + `/ready` timeout/503 | DB injoignable ou pool/lock côté Postgres |
| `/health` timeout/5xx | App down ou Railway routing cassé |
| `/health/pool` `usage_pct ≥ 80` | Pool app saturé — voir §3.3 |

### 1.2 Sentry — issues actives dans la dernière heure (≤ 30 s)

```bash
sentry-cli issues list --org facteur --project python --query "is:unresolved age:-1h" --max-rows 15
```

**Lis la stack trace de l'issue la plus récente.** C'est ton signal le plus frais. Ne formule **aucune** hypothèse avant.

### 1.3 État live de Postgres (≤ 30 s)

Via le MCP Supabase ou `psql "$DATABASE_URL_RO"` :

```sql
SELECT
  count(*) AS total,
  sum(case when state='idle in transaction' then 1 else 0 end) AS idle_in_tx,
  sum(case when state='idle in transaction' and state_change < now() - interval '60 seconds' then 1 else 0 end) AS zombies_over_60s,
  sum(case when state='active' then 1 else 0 end) AS active,
  sum(case when wait_event='Lock' then 1 else 0 end) AS waiting_lock
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid();
```

Limite Supavisor pooler = **60 connexions**. Si `total ≥ 50` ou `zombies_over_60s ≥ 10`, voir §3.3.

### 1.4 Déploiements récents (≤ 15 s)

```bash
git log origin/main --oneline -10
gh pr list --base main --state merged --limit 10 --json number,title,mergedAt,files | jq -r '.[] | "\(.mergedAt) #\(.number) \(.title)"'
```

Si une PR a été mergée dans l'heure qui a précédé l'incident → suspect numéro un. Vérifie ses fichiers modifiés.

### 1.5 Reformulation explicite du symptôme

Avant de plonger : **écris en une phrase ce que tu observes**, pas ce que tu déduis.

> Bon : « `/api/feed` renvoie 500 avec stack `DetachedInstanceError UserPersonalization` (Sentry PYTHON-2X, last seen 09:52 UTC). Healthchecks OK. »
> Mauvais : « le pool est saturé » (déduction sans donnée).

---

## 2. Symptôme → arbre d'hypothèses

Utilise ce tableau pour **t'orienter** sans fermer de pistes. Les classes sont triées par probabilité décroissante quand le symptôme matche.

| Symptôme observé | Classes les plus probables | Première chose à vérifier |
|---|---|---|
| Tous les endpoints 500 / `Petit souci` mobile | Schema mismatch (§3.2) → Régression code (§3.1) → Pool/sessions (§3.3) | Sentry: `UndefinedColumn`, `DetachedInstanceError`, `PendingRollbackError`, `ProgrammingError` |
| Un seul endpoint 5xx | Régression code (§3.1) → Upstream externe (§3.4) → Schema mismatch (§3.2) | Stack trace de l'endpoint, dernière PR qui l'a touché |
| Mobile boucle "Chargement…" / spinner infini | Pool/sessions (§3.3) → Réseau/DNS (§3.9) → Auth/JWT (§3.7) | `/api/health/pool`, console mobile (Sentry/PostHog session replay) |
| Latence p95 explose mais 200 OK | Pool/sessions (§3.3) → Capacité (§3.5) → Upstream externe (§3.4) | `/api/health/pool` `usage_pct`, latence Mistral/RSS |
| Healthcheck OK mais users disent "rien ne marche" | Schema mismatch (§3.2) → Auth (§3.7) → Mobile cache (§3.10) | `SELECT 1` passe ne couvre pas tous les endpoints — lis Sentry |
| 502/503 récurrents | Capacité (§3.5) → Deploy (§3.6) → Pool (§3.3) | Railway logs `OOMKilled`, `Healthcheck failed`, restart loop |
| Erreurs apparues post-merge récent | Régression code (§3.1) → Schema mismatch (§3.2) | `git log` PR + `git show <sha>` files modifiés |
| Erreurs apparues post-cron horaire (06:00, 07:30, 03:00) | Cron/jobs (§3.8) → Pool/sessions (§3.3) | Sentry filtré sur le timestamp du cron, scheduler.py |
| Login impossible / disconnect au matin | Auth (§3.7) → Mobile cache (§3.10) | `bug-android-disconnect-race.md`, JWT secret cohérent |
| Articles RSS manquants / sources cassées | Upstream externe (§3.4) → Cron (§3.8) | Sentry filtre `download error`, `not a 200`, last_synced_at |

**Règle d'or** : si 2 classes paraissent plausibles, **probe les deux en parallèle**, ne choisis pas avant d'avoir vu les données.

---

## 3. Classes d'incidents — deep dives

### 3.1 Régression code (PR récente)

**Symptômes typiques** : nouvelle exception qui n'existait pas avant, soudaine sur tout ou un endpoint. Apparition coïncide avec un déploiement.

**Probes** :
```bash
# Quelle PR a été déployée juste avant le burst Sentry ?
gh pr list --base main --state merged --limit 10 --json number,title,mergedAt,files \
  | jq -r '.[] | "\(.mergedAt) #\(.number) \(.title)"'

# Diff de la PR suspecte
gh pr view <num> --json files,body
git show <sha> --stat
git show <sha> -- packages/api/app/<module suspecté>
```

**Piège classique : l'effet de bord** d'une PR "anodine".
> Exemple historique : ajouter `await session.rollback()` en `finally` paraît anodin mais expire les ORM attributes en SQLAlchemy 2.x → `DetachedInstanceError` dans tous les callers downstream.

**Décision** : revert vs forward-fix. Revert si :
- Le PR est isolé (pas de dépendances aval)
- L'effet de bord est large (≥ 2 endpoints affectés)
- Tu n'as pas la cause racine en < 30 min

Forward-fix si :
- Le bug est ciblé et la fix tient en < 100 lignes
- Le revert casserait d'autres choses utiles dans la PR

### 3.2 Schema mismatch (migration non appliquée)

**Symptômes typiques** : `UndefinedColumn`, `UndefinedTable`, `DataError`, `InFailedSqlTransaction` cascade. Les healthchecks (`SELECT 1`) passent mais les vrais endpoints crashent.

**Probes** :
```sql
-- Quelles révisions Alembic sont appliquées en prod ?
SELECT version_num FROM alembic_version;
```
```bash
# Quelles révisions le code attend-il ?
ls packages/api/alembic/versions/
grep -h "^revision\|^down_revision" packages/api/alembic/versions/*.py
```
Confronte les deux. Une révision dans `versions/` mais absente d'`alembic_version` = migration non appliquée.

**Pourquoi ça arrive** : le `Dockerfile` fait `alembic upgrade head` au boot mais c'est best-effort (3 retries puis skip). La règle CLAUDE.md ("SQL via Supabase SQL Editor, jamais d'Alembic sur Railway") est plus sûre — appliquer manuellement avant merge.

**Fix** : extraire le SQL pur de la migration, l'appliquer via Supabase SQL Editor (le MCP `apply_migration` peut être en read-only selon le rôle), puis `UPDATE alembic_version SET version_num='<nouveau>' WHERE version_num='<ancien>'`.

**Piège** : `alembic_version` peut avoir plusieurs lignes (multi-head). Le hook `post-edit-alembic-heads.sh` est censé bloquer, mais a déjà raté — vérifie `alembic heads` localement avant.

### 3.3 Pool / sessions DB

**Symptômes typiques** : `QueuePool limit reached`, `TimeoutError`, `DbHandler exited`, `PendingRollbackError`, `idle in transaction` qui s'accumulent.

**Architecture rappel** :
- App pool SQLAlchemy : `pool_size + max_overflow` (config `database.py`)
- Supavisor pooler Supabase : 60 connexions max (limite plan)
- Postgres `max_connections` : ~100 (accessible via Supavisor)

**Probes** :
```bash
curl $HOST/api/health/pool
```
```sql
-- Détail des sessions
SELECT pid, application_name, state, wait_event_type, wait_event,
       EXTRACT(EPOCH FROM (now() - state_change))::int AS sec_in_state,
       EXTRACT(EPOCH FROM (now() - xact_start))::int AS sec_in_xact,
       LEFT(query, 200) AS query_preview
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid()
ORDER BY xact_start NULLS LAST LIMIT 30;

-- Locks bloquants
SELECT blocked.pid AS blocked_pid, blocking.pid AS blocking_pid,
       blocking.application_name, blocking.state,
       LEFT(blocking.query, 200) AS blocking_query
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));
```

**Mitigation immédiate** (zombie idle-in-tx > 5 min) :
```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state='idle in transaction'
  AND application_name='Supavisor'
  AND state_change < now() - interval '60 seconds';
```

**Pièges fréquents** :
- **Pool app vs Supavisor** : si pool app à 20% mais Supavisor saturé, le bottleneck est Supavisor (60 max). Bumper `pool_size` n'aide pas.
- **Connect_args ignorées** : Supavisor en transaction-mode strippe les options libpq startup. `idle_in_transaction_session_timeout` mis dans `connect_args["options"]` est **inactif** — utiliser `SET LOCAL` per-session via event listener.
- **`async with async_session_maker()` sans rollback** : crée des zombies. Pattern obligatoire = `safe_async_session()` (helper `database.py`) qui fait `expunge_all() + rollback()` en `finally`.
- **`rollback()` après objets ORM retournés** : expire les attributs en SQLA 2.x → `DetachedInstanceError` aval. **Toujours `expunge_all()` AVANT rollback** quand la fonction retourne des objets.

### 3.4 Upstream externe (LLM, RSS, Auth provider)

**Symptômes typiques** : timeout 30s+ sur un endpoint, latence p95 qui explose, erreurs `httpx.ReadTimeout` / `OpenAI APIError` / `download error`.

**Upstreams critiques** :
| Service | Usage | Symptômes si down |
|---|---|---|
| Mistral API | Editorial pipeline, smart-search Mistral layer, ML classification | Digest gen hang, smart-search degraded |
| Brave / Google News | Smart-search layers (b, c) | Smart-search resultats partiels |
| RSS feeds (50+ sources) | Cron RSS sync intervalle | Articles manquants, `not a 200` Sentry |
| Supabase Auth | JWT verification, login | 401 burst, mobile bouclé en login |
| Railway platform | Hosting | 502 partout, restart loops |

**Probes** :
```bash
# Latence Mistral en prod ?
sentry-cli issues list --query "MISTRAL_API_URL OR mistral.ai" --max-rows 10
# Sources qui ratent leur sync RSS
psql "$DATABASE_URL_RO" -c "SELECT name, last_synced_at FROM sources WHERE is_active AND last_synced_at < now() - interval '6 hours' ORDER BY last_synced_at NULLS FIRST LIMIT 20;"
# Statut Railway / Supabase
curl -fsS https://api.railway.com/health 2>/dev/null
curl -fsS https://status.supabase.com/api/v2/status.json 2>/dev/null | jq .
```

**Pièges** :
- **Une session DB checkout pendant un appel LLM 30s** = pool slot bloqué 30s. Voir §3.3 + pattern PR #485 / #489 (release session avant calls externes).
- **Statut "200" upstream ≠ contenu valide** : Mistral peut retourner 200 avec un JSON malformé. Toujours valider la response.
- **Bruit Sentry RSS** : les "download error" / "not a 200" sont **filtrés** dans `_sentry_before_send` (#491). Ne te laisse pas distraire — mais si le filtre cache **trop**, certains vrais bugs sont noyés.

### 3.5 Capacité / OOM / disk

**Symptômes typiques** : 502/503 récurrents, restart loops Railway, `MemoryError`, latence qui dérive sans pic clair.

**Probes** :
```bash
railway logs --service <id> | grep -iE "OOMKilled|memory|restart|sigterm|sigkill"
railway status --json
```

**Pièges** :
- **Single uvicorn worker** : si la charge dépasse 1 process, on serialize. Pas de scaling horizontal aujourd'hui.
- **Scheduler in-process** : RSS sync intervalle, digest 06h, top3 08h, cleanup 03h **partagent le pool API**. Si un job ML cron mange 10 connexions pendant que les users arrivent, l'API étouffe.
- **`run_in_executor` sans bound** : trafilatura/feedparser peuvent bloquer un thread executor. Voir `bug-infinite-load-requests.md`.

### 3.6 Configuration / env / deploy

**Symptômes typiques** : "ça marchait hier", env var manquante, custom domain qui pointe vers le mauvais service.

**Probes** :
```bash
# Vrai hostname de l'API mobile
grep -rE "https://[a-z-]+\.up\.railway\.app|API_URL|baseUrl" apps/mobile/lib/config/
# Pour Facteur prod : https://facteur-production.up.railway.app

# Le hostname répond-il vraiment du backend Python ?
curl -fsS $HOST/api/health
# Si tu reçois du HTML Flutter au lieu de JSON, c'est le frontend web — vérifie le routing Railway

railway variables --service <id>
```

**Pièges historiques (réels, pour mémoire)** :
- Hostname `api-production-c660.up.railway.app` = frontend web Flutter, **pas** le backend Python. Le backend est sur `facteur-production.up.railway.app`.
- `railway.toml` lu, `railway.json` ignoré (cf. PR #368). Modifier le bon fichier.
- `restartPolicyType` config sur `railway.toml` mais policy dans `railway.json` = effective policy = celle non-éditée. Toujours vérifier `serviceManifest` du deployment courant.
- Healthcheck `/api/health` (liveness pure) ne détecte rien, healthcheck `/api/health/ready` (DB-aware) déclenche restart si DB down — choisir selon ce qu'on veut faire en cas de panne.

### 3.7 Auth / JWT / refresh

**Symptômes typiques** : burst 401, "logged out" au matin, mobile bouclé en re-login.

**Probes** :
```bash
sentry-cli issues list --query "is:unresolved 401 OR JWT OR refresh_token" --max-rows 10
```

**Architecture** :
- JWT secret partagé mobile ↔ backend (CLAUDE.md : "JWT secret identique mobile ↔ backend")
- Supabase Auth gère le refresh token
- Race condition refresh = bug-android-disconnect-race.md (PR #477 a fixé)

**Piège** : si l'app fait 4 retries sur 401, et le 1er refresh est en cours, les 3 autres peuvent invalider le refresh token. Toujours single-flight.

### 3.8 Cron / job background

**Symptômes typiques** : erreurs qui apparaissent à heures fixes (06:00, 07:30, 03:00 Paris), zombies idle-in-tx créés par batch, sources `last_synced_at` figés.

**Architecture** : `packages/api/app/workers/scheduler.py` — APScheduler in-process avec :
- `rss_sync` (intervalle, `RSS_SYNC_INTERVAL_MINUTES`)
- `daily_top3` (08:00 Paris)
- `daily_digest` (06:00 Paris)
- `digest_watchdog` (07:30 Paris)
- `storage_cleanup` (03:00 Paris)

**Probes** :
```bash
railway logs --service <id> | grep -iE "digest_(generation|watchdog)|rss_sync|storage_cleanup" | tail -50
```
```sql
-- Coverage digest
SELECT count(DISTINCT user_id) AS users_with_digest, current_date AS today
FROM daily_digest WHERE target_date = current_date;
```

**Pièges** :
- **Lock APScheduler entre instances Railway** : si Railway scale à 2 replicas, 2 schedulers s'exécutent. Aujourd'hui = 1 replica donc OK, mais à surveiller au scaling.
- **`misfire_grace_time` vs réalité** : si Railway redémarre pendant un cron, le job peut être skippé silencieusement. `coalesce=True` aide mais ne garantit pas l'exécution.

### 3.9 Réseau / DNS / TLS

**Symptômes typiques** : timeout au connect, `SSL_ERROR`, `name resolution failed`, custom domain qui répond intermittent.

**Probes** :
```bash
dig +short facteur-production.up.railway.app
curl -fsSI $HOST/api/health    # vérifie le cert TLS via -I (HEAD)
nslookup api.facteur.app       # si custom domain
```

**Pièges** :
- **TCP keepalive Postgres = 1800s** par défaut. Si le réseau coupe entre app et Supavisor, la connexion zombie persiste 30 min côté app. Ajouter `keepalives_idle` dans `connect_args` réduit, mais pas appliqué en transaction-mode (cf. §3.3 piège connect_args).
- **DNS Railway internal** : à l'intérieur de Railway, utiliser `<service>.railway.internal` pour speed. Mais en local c'est `*.up.railway.app`.

### 3.10 Mobile / cache client

**Symptômes typiques** : "1 user voit X, l'autre voit Y", "ça marche en navigation privée", données stale persistantes.

**Probes** :
- Demander la version app du user impacté (`apps/mobile/pubspec.yaml` vs prod)
- PostHog session replay si dispo
- Vérifier les caches mobiles : `FEED_CACHE` (in-memory côté backend), Hive/SharedPreferences côté mobile

**Pièges** :
- **`FEED_CACHE` TTL 30s côté backend** : un user qui retry rapidement voit le même payload même si la DB a changé. Pas un bug en soi, à expliquer à l'user.
- **Cache mobile `cached_network_image`** : 7 jours par défaut. Si une image change d'URL, l'ancienne reste cachée.

---

## 4. Anti-patterns & biais cognitifs à éviter

### 4.1 Extrapoler depuis l'incident de la veille

**Symptôme** : « hier c'était les zombies, donc aujourd'hui c'est encore les zombies ».
**Coût observé** : 4h de hot fix sur la mauvaise piste le 28/04.
**Antidote** : toujours pull Sentry **fraiche** + lire la stack trace **avant** toute hypothèse.

### 4.2 Hot fix sur hot fix

**Symptôme** : enchaîner 2-3 PRs en moins de 4h sans que la situation s'améliore.
**Coût observé** : PR #493 a introduit le bug PR #495 a dû fixer (cascade).
**Antidote** : si 2 hot fixes en 4h ne résolvent pas → STOP, re-probe live, demande un **fresh diagnostic**.

### 4.3 Fix qui paraît anodin

**Symptôme** : « j'ajoute juste un `await session.rollback()` en finally, c'est safe ».
**Réalité** : effets de bord ORM/SQL/async dont le contributeur ne soupçonne pas l'existence.
**Antidote** : pour toute couche de défense ajoutée, lister explicitement (1) ce qu'elle protège, (2) ce qu'elle peut casser. Tester downstream, pas juste l'endpoint touché.

### 4.4 Bumper la capacité sans diag

**Symptôme** : « pool plein, je passe de 20 à 50 ».
**Réalité** : si Supavisor (60) est le vrai bottleneck, ou si le code leak des sessions, augmenter `pool_size` accélère juste la pollution.
**Antidote** : toujours `pg_stat_activity` + `/api/health/pool` AVANT de toucher la config.

### 4.5 Restart pour stop the bleeding

**Symptôme** : « je redémarre Railway et on verra bien ».
**Réalité** : redémarrer ne tue pas les zombies côté Supavisor (cf. §3.3). Et le restart peut **aggraver** (sessions zombies + nouvelles sessions = + de pression).
**Antidote** : comprendre où vit le state corrompu. Côté app → restart aide. Côté Supabase/Supavisor → restart Railway ne sert à rien, il faut intervenir SQL-side.

### 4.6 Confondre "200 OK" avec "fonctionne"

**Symptôme** : `/api/health` répond 200, donc on n'investigue pas la prod.
**Réalité** : l'app peut être démarrée mais tous les endpoints concrets crasher (schema mismatch typique).
**Antidote** : tester un endpoint **utilisé par les users** (avec un token valide) avant de conclure.

### 4.7 Ignorer le timing

**Symptôme** : ne pas corréler timestamp d'un burst Sentry avec l'heure de merge d'une PR.
**Antidote** : pour chaque issue Sentry "first_seen", regarder s'il y a eu un merge dans les 2h précédentes.

### 4.8 Auto-redéploiement en boucle

**Symptôme** : l'auto-restart Railway / un GH Action redéploie l'app à chaque saturation, sans casser le cycle.
**Réalité** : si le bug est dans le code, redéployer ne change rien — juste plus d'events Sentry.
**Antidote** : tout système d'auto-redeploy doit avoir une **back-off exponentielle** + une **issue auto-créée** au 3ᵉ déclenchement consécutif pour forcer une intervention humaine.

---

## 5. Aide-mémoire commandes

### Sentry
```bash
# Top issues unresolved 1h
sentry-cli issues list --org facteur --project python --query "is:unresolved age:-1h" --max-rows 15

# Issue spécifique avec stack
sentry-cli issues view PYTHON-XX

# Filtrer par texte
sentry-cli issues list --query "is:unresolved DetachedInstance"
```

### Supabase / Postgres
```bash
psql "$DATABASE_URL_RO" -c "SQL ici"
# OU via MCP : mcp__supabase__execute_sql / list_tables / list_migrations
```

Snippets utiles :
- État pool : voir §1.3
- Sessions zombies : voir §3.3
- Locks : voir §3.3 (deuxième query)
- Migration appliquée ? voir §3.2

### Railway
```bash
railway status --json
railway logs --service <id> --since 30m
railway variables --service <id>
# GraphQL pour ce qui n'est pas dans le CLI
curl -fsS -X POST "https://backboard.railway.app/graphql/v2" \
  -H "Authorization: Bearer $RAILWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ me { name } }"}'
```

### App live
```bash
HOST=https://facteur-production.up.railway.app
curl -fsS $HOST/api/health
curl -sS $HOST/api/health/ready
curl -sS $HOST/api/health/pool | jq .
```

### Git / GitHub
```bash
git log origin/main --oneline -15
gh pr list --base main --state merged --limit 10 --json number,title,mergedAt
gh pr view <num> --json files,body
git show <sha> --stat
```

### Scripts QA existants
```bash
ls docs/qa/scripts/        # verify_<task>.sh par feature
bash docs/qa/scripts/verify_<task>.sh
```

### Healthcheck accès
```bash
bash scripts/healthcheck-agent-secrets.sh         # mode complet
bash scripts/healthcheck-agent-secrets.sh --fast  # rapide (utilisé au SessionStart)
```

---

## 6. Quand appeler du renfort / rendre la main au user

Tu dois **STOP et demander au user** dans ces cas :

- 2 hot fixes consécutifs n'ont pas résolu → demande un fresh diagnostic externe
- Tu identifies une cause racine qui demande une décision stratégique (revert vs forward, downscaling, contact support Supabase/Railway)
- Une action destructive est nécessaire (`pg_terminate_backend`, `DROP`, force push, redeploy en cascade)
- Le MCP Supabase est en read-only et la fix demande un write
- Un secret semble compromis → STOP + procédure rotation
- L'incident dure > 30 min sans cause racine identifiée

**Format de remontée** :
1. Symptôme observé en 1 ligne (ce que tu **vois**, pas ce que tu déduis)
2. Probes effectués (résumé bullet)
3. Cause racine probable (avec niveau de certitude : confirmée / probable / hypothèse)
4. Options de fix (A/B/C avec pros/cons)
5. **Recommandation** + question explicite au user

---

## 7. Après l'incident — discipline post-mortem

Toute panne user-facing > 5 min mérite une note courte dans `docs/postmortems/<date>-<topic>.md`. Format SBAR :

- **Situation** : ce qui s'est passé (factuel, timestamps)
- **Background** : contexte (PRs récents, état pool, etc.)
- **Assessment** : cause racine confirmée + cause systémique (pourquoi c'est passé en prod)
- **Recommendation** : actions correctives (immédiate, court terme, long terme)

Référence : voir `docs/postmortems/` (à créer s'il n'existe pas).

---

## 8. Investigations non urgentes (ops "calmes")

### 8.1 Comprendre l'usage d'une feature

| Outil | Quand l'utiliser |
|---|---|
| PostHog API ou MCP | Events produit (clicks, views, funnels) |
| `scripts/analytics/run_usage_queries.sh` | Agrégats DB (streaks, rétention, framework R01/R02) |
| `psql "$DATABASE_URL_RO"` ou Supabase SQL Editor | SQL ad-hoc |

**Piège** : le pooler Supabase utilise le username `claude_analytics_ro.ykuadtelnzavrqzbfdve` (avec le point — routing pgBouncer). Si tu vois "role does not exist", c'est ce détail.

### 8.2 Auditer la sécurité d'un accès / d'une écriture

| Question | Outil | Commande |
|---|---|---|
| Qui peut faire quoi sur la DB ? | `psql` | `\dp schema.table` |
| `claude_analytics_ro` ne peut pas écrire ? | Healthcheck complet | `bash scripts/healthcheck-agent-secrets.sh` |
| Vérifier un GRANT spécifique | Supabase SQL Editor | `SELECT * FROM information_schema.role_table_grants WHERE grantee='claude_analytics_ro';` |

**Règles non négociables** :
1. Jamais d'écriture via `DATABASE_URL_RO`. Si écriture nécessaire → demander `service_role` à l'user avec justification.
2. Jamais imprimer un secret en sortie.
3. Toujours utiliser le Session Pooler (port 5432 sur `*.pooler.supabase.com`), pas le endpoint direct (IPv6-only).
4. Si un token fuite : révoquer immédiatement + update secret GitHub + relancer healthcheck.

### 8.3 Migration Alembic locale

| Étape | Commande |
|---|---|
| Head courant | `cd packages/api && alembic current` |
| Vérifier 1 head | `bash .claude-hooks/post-edit-alembic-heads.sh` (auto) |
| SQL de rattrapage prod | Supabase SQL Editor — voir §3.2 |

---

## 9. Aller plus loin

| Doc | Quand le lire |
|---|---|
| [CLAUDE.md](../../CLAUDE.md) | Règles projet (workflow, hooks, PR) |
| [Safety Guardrails](safety-guardrails.md) | Zones à risque (Auth, Router, DB, Infra) |
| [Navigation Matrix](navigation-matrix.md) | Workflow par type de tâche |
| [docs/bugs/](../bugs/) | Bugs historiques résolus — souvent un précédent existe |
| [docs/maintenance/](../maintenance/) | Refactors et choix architecturaux |
| [docs/infra/claude-access-setup.md](../infra/claude-access-setup.md) | Tokens et accès multi-services |

---

**Mantra de l'investigation** :
> Lire la stack avant la déduction. Probe avant l'hypothèse. Données avant action. Une couche à la fois.
