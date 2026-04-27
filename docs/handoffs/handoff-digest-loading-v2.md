# Hand-off : Investigation Chargements Infinis du Digest (v2)

**Pour l'agent suivant** — *à lire en entier avant de toucher au code.*

---

## 1. Pourquoi tu es là

Le user signale, **encore et toujours**, des chargements infinis sur l'écran
Digest de l'app mobile Facteur. Son mental model : "le digest est figé,
pré-calculé toutes les 24h, identique pour tous → pourquoi il y a un seul
spinner ?"

La réalité du code :
- Digest **personnalisé par user** (sources suivies, weekly_goal, mode serein,
  format éditorial/topics, mute list).
- Cron 8h00 Paris (`app/jobs/digest_generation_job.py`) génère un digest par user
  actif.
- Endpoint `GET /api/digest/both` sur le hot-path d'ouverture d'app — appelé par
  `apps/mobile/lib/features/digest/repositories/digest_repository.dart`.

## 2. Ce qu'a fait l'agent précédent (à NE PAS reproduire)

Sur la branche `claude/fix-digest-loading-sWZRJ`, j'ai :
1. Ajouté un param `allow_generation` à `DigestService.get_or_create_digest`.
2. Fait passer les routes GET en `allow_generation=False` (read-only, retourne
   202 si pas de cache).
3. Parallélisé `/digest/both` via `asyncio.gather`.
4. Augmenté le pool DB (5+5 → 10+10).
5. Réduit la concurrency du catchup (10 → 5).
6. Réduit les retry mobile (3×[5,10,15]s → 2×[3,6]s).
7. Push sur la branche, deux commits : `3b3e5b6` (bug doc) + `0b9f71c` (fix).

**Le piège** : la branche a été créée à partir de `8a52569` (mi-mars), et
`origin/main` a depuis avancé de **145 commits**. Mon fix écrase ~20 PRs
upstream qui touchent les mêmes fichiers. Tentative de merge → conflits massifs.

**Donc : ne fais PAS confiance à mon fix. Il est probablement redondant ET
destructif** vis-à-vis des fixes déjà mergés.

## 3. Ce que `main` contient déjà (à lire AVANT d'investiguer)

Lance ces commandes et lis les diffs / messages de PR :

```bash
git fetch origin main
git log --oneline 8a52569..origin/main -- \
  packages/api/app/services/digest_service.py \
  packages/api/app/routers/digest.py \
  packages/api/app/database.py \
  packages/api/app/jobs/digest_generation_job.py \
  apps/mobile/lib/features/digest/providers/digest_provider.dart \
  apps/mobile/lib/features/digest/repositories/digest_repository.dart
```

PRs particulièrement pertinentes à comprendre **avant** d'investiguer :

| PR | Sujet | Pourquoi c'est important |
|---|---|---|
| #405 | claude/fix-infinite-loading-requests | **Déjà un fix sur le même symptôme** — sessions courtes, timeouts socket |
| #408 | pool exhaustion stability Round 2 | Sites C/D/E/F + statement_timeout + middleware |
| #412 | session leak — close() avant LLM | BaseException rollback, drop middleware |
| #414 | Round 3 — Supabase-killed conns + per-user session isolation | Singleflight per user |
| #442 | session rollback in digest+feed handlers (Round 6) | |
| #448 | **hotfix(api): singleflight per user on /digest/both (P0)** | **Existe déjà : ne le réinvente pas** |
| #456 | make /digest/both post-gather DB ops fail-open | |
| #457 | clone sibling user's editorial_v1 digest for new users | Fallback rapide nouveaux users |
| #461 | Fix digest perspective undercount & same-day deep article | |
| #470 | Sprint 1 — time_spent, digest completion, PostHog | Instrumentation |
| #479 | **stop the bleeding — Railway restart policy + 3 worker session leaks** | Le plus récent, dernier filet |
| #481 | smart-search quality + latency phase 1+2 | |

Lis au minimum #405, #414, #448, #457, #479. Tu comprendras l'historique du
combat anti-loading et les hypothèses déjà testées.

## 4. Ta mission

### Étape 1 — investiguer la réalité Railway **avant** d'écrire une ligne de code

L'agent précédent (moi) n'avait pas d'accès Railway. **Toi tu l'as.** Utilise-le.

```bash
# Liste les services / déploiements
railway list
railway status

# Logs en cours (priorité absolue)
railway logs --tail 500
railway logs --filter "digest"
railway logs --filter "ERROR"
railway logs --filter "session"
railway logs --filter "pool"
railway logs --filter "503"
railway logs --filter "202"
```

Si un MCP Railway est dispo (`mcp__railway__*`), préfère-le au CLI.

Cherche en particulier :
- `digest_endpoint_unhandled_error`, `digest_generation_returned_none`
- `digest_singleflight_*` (depuis #448)
- `digest_format_mismatch_regenerating`
- `pool exhausted`, `QueuePool limit of size`, `connection pool` warnings
- Latency p95/p99 sur `GET /digest/both` et `GET /digest`
- Erreurs 503, 504, timeouts client
- Stack traces récentes sur les services ML / digest_selector / editorial pipeline

Sentry : à priori non dispo en self-service ici, mais demande au user s'il peut
te coller un dashboard ou une alerte récente. Si oui, croise avec les logs.

### Étape 2 — formuler le diagnostic

Réponds aux questions concrètes avant de proposer quoi que ce soit :

1. **Le bug existe-t-il vraiment encore en l'état actuel de `main` ?** Avec
   #448 (singleflight), #457 (clone sibling), #479 (3 leaks fixés), peut-être
   que le symptôme observé par le user vient d'un **autre** chemin (cold-start
   widget Android ? notification push ? onboarding ? auth ?).
2. **Quelle est la latence réelle p50/p95/p99 de `GET /digest/both`** sur les
   dernières 24-48h ?
3. **Y a-t-il des erreurs ?** Si oui : quel taux, quel chemin, quelle stack ?
4. **Est-ce que le cron 8h Paris s'exécute** chaque jour ? `digest_generation_job_completed`
   doit apparaître dans les logs. Combien d'échecs `digest_generation_user_failed` ?
5. **Quel est l'effet du startup catchup** (`_startup_digest_catchup` dans
   `app/main.py`) sur le pool ? Est-ce qu'il sature encore après #408/#414/#479 ?
6. **Le user a-t-il des reproductions précises** (device, OS, instant de la
   journée, action déclencheuse) ? Demande-lui.

### Étape 3 — décision plan

Trois branches possibles selon ce que tu trouves :

- **A. Pas de bug observé en logs** → bug peut-être côté mobile (cache, retry,
  cold-start widget, route, déshydratation Riverpod). Investigue le mobile, pas
  le backend.
- **B. Bug confirmé sur un chemin spécifique** → fix ciblé, **sans** dupliquer
  les fixes existants. Lis singleflight (#448) avant tout — si ton fix touche
  `/digest/both`, tu vas probablement intéragir avec le lock.
- **C. Bug systémique / pool exhaustion non résolu** → escalade : ce n'est plus
  un fix code, c'est de l'infra (sizing Supabase, replicas Railway, queue
  asynchrone Redis pour génération).

### Étape 4 — workflow CLAUDE.md à respecter strictement

1. Bug → crée `docs/bugs/bug-digest-loading-infini-v2.md` (n'écrase pas le v1
   de l'agent précédent, garde-le pour historique).
2. Rédige PLAN dans le doc → **STOP, présente le plan au user, attends GO**.
3. Si GO → implémente sur **une branche basée sur `origin/main` à jour** :

   ```bash
   git fetch origin main
   git checkout -b claude/fix-digest-loading-v2 origin/main
   ```

   **NE TRAVAILLE PAS** sur `claude/fix-digest-loading-sWZRJ` (la branche stale
   de l'agent précédent — laisse-la pour archive).
4. PR vers `main` : **toujours `--base main`** (le repo a `staging` comme défaut
   GitHub).
5. Pas de migration Alembic sur Railway. Si tu touches au schéma DB, fournis le
   SQL pour Supabase SQL Editor et **sors la migration du scope du deploy**.

## 5. Contraintes techniques (rappel CLAUDE.md)

- Python **3.12.x** (3.13+ casse pydantic). L'env local de l'agent précédent
  avait Python 3.11 + 3.12 dispo, j'ai dû forcer `python3.12 -m pytest`.
- `list[]`, `dict[]`, `X | None` natifs. Jamais `from typing import List, Dict, Optional`.
- Hooks actifs : `post-edit-auto-test.sh` lance les tests après chaque édit,
  `stop-verify-tests.sh` bloque la fin de réponse si les tests échouent.
- MCP dispo : Playwright (UI/E2E), Sentry, **Railway**, Supabase. Utilise-les.

## 6. État du repo au moment du hand-off

- Branche actuelle : `claude/fix-digest-loading-sWZRJ` (stale, 145 commits behind main)
- Commits ajoutés par l'agent précédent : `3b3e5b6` (doc) + `0b9f71c` (fix)
- Aucun fichier non commité, aucun staged change.
- Tests `test_digest_service.py` + `test_digest_generation_job.py` +
  `test_digest_selector.py` + `test_topic_selector.py` passent (75 tests sur
  ce périmètre — mais sur du code stale, donc valeur informative limitée).

## 7. Ce que tu dois livrer

Un message au user, dans cet ordre :

1. **Diagnostic réel** appuyé par les logs Railway (timestamps, taux, latences).
   Pas d'hypothèses non vérifiées.
2. **État des fixes upstream** : qu'est-ce qui marche déjà, qu'est-ce qui ne
   marche pas.
3. **Plan d'action** : ciblé, minimal, qui ne réinvente rien d'existant.
4. **STOP, demande GO** avant d'implémenter.

Si tu trouves que mon fix de la branche `sWZRJ` contient quand même un morceau
utile (par ex. retry mobile plus court), dis-le explicitement et propose un
cherry-pick chirurgical, **après** avoir vérifié qu'il ne casse pas un fix
existant.

## 8. Anti-pattern à éviter

- Ne tente **pas** de rebase / merge `claude/fix-digest-loading-sWZRJ` sur main.
  Trop de conflits, trop de risque de réintroduire des bugs déjà fixés.
- Ne **pas** coder avant d'avoir lu les logs Railway et compris ce que font
  #448, #457, #479.
- Ne **pas** présumer que le bug est backend. Il peut être 100 % mobile (cache
  Riverpod, cold start, widget Android, race condition retry).
- Ne **pas** ré-implémenter un singleflight, un fail-open, un clone-sibling :
  ils existent déjà.

Bonne chasse.
