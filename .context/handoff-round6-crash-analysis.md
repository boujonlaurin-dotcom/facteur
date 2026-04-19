# Handoff — Round 6 crash analysis (2026-04-19 ~16:59)

> À destination d'un nouvel agent. Tu arrives à froid. Lis ce prompt + les artefacts cités **avant** de toucher quoi que ce soit. Tu es en **ANALYSE + AJUSTEMENT DE PLAN**, pas en code. N'édite aucun fichier tant que tu n'as pas rendu ton diagnostic.

---

## Mission

Le serveur **backend (Railway service "Api", build `packages/api/Dockerfile`)** a crashé aux alentours de **2026-04-19 16:59 Europe/Paris** (heure locale CTO — convertis si tu dois corréler des logs UTC). Le CTO a dû **redémarrer manuellement** le service. C'est le **Round 6** de crashes récurrents.

Tes deux livrables :

1. **Analyse précise du crash 16:59** : quelle signature, quel endpoint, quelle cause racine probable, comment elle s'articule avec les crashes Round 1–5 ? S'agit-il d'une **nouvelle famille de pannes** ou d'une **récidive d'une panne déjà mesurée** ?
2. **Ajustement du plan de robustesse en cours** : après ton diagnostic, dis-nous si le plan D1/D2/D3/D4 du handoff CTO 2026-04-19 reste pertinent tel quel, ou s'il faut **reprioriser / ajouter / retirer** une décision. Pas de code, pas de PR — juste l'arbitrage révisé, evidence-based.

---

## Contexte indispensable — à lire AVANT toute action

Dans cet ordre :

1. **`.context/perf-watch/2026-04-19.md`** — rapport watcher nocturne complet (§1–§9). Tu y trouveras : état Sentry saturé, cartographie PYTHON-14, timeline des digests timeout, blocages sandbox (Railway CLI absent, `backboard.railway.com` + `facteur-production.up.railway.app` hors allowlist).
2. **`.context/pr-handoff.md`** — PR #437 actuelle (branche `claude/backend-stability-scalability-PAzL7`, base `main`, 3 commits). D1 F1 (filtre Sentry) + D3 ciblé (rollback community). **Pas encore mergée** à l'heure où je rédige ce handoff — vérifie l'état via `mcp__github__pull_request_read get=get` owner=`boujonlaurin-dotcom` repo=`facteur` pullNumber=437.
3. **`docs/bugs/bug-infinite-load-requests.md`** — historique complet des Rounds 1–5 (dont R3 `_invalidate_on_supabase_kill` et R5 FeedPageCache + mobile single-flight).
4. **`docs/bugs/bug-community-pending-rollback.md`** — racine technique du `PendingRollbackError` / PYTHON-14 ; comprends bien **pourquoi R3 ne suffit pas**.
5. **`docs/maintenance/maintenance-sentry-trafilatura-filter.md`** — pourquoi Sentry a été saturé et ce que fait D1 F1.
6. **`packages/api/app/database.py`** lignes 120–156 (`_invalidate_on_supabase_kill`) et 242–280 (`get_db`) — seule source de vérité sur la gestion de pool et les rollbacks.
7. **`packages/api/app/main.py`** (après merge PR #437 — sinon branche `claude/backend-stability-scalability-PAzL7`) — filtre `_sentry_before_send` + init Sentry.

---

## État du système à l'instant T (à confirmer toi-même)

- **Sentry projet** : quota saturé depuis 2026-04-18 15:00 UTC → **0 event accepté** tant que D1 F1 (PR #437) n'est pas déployée en prod. Tu verras donc peut-être **rien** dans Sentry pour le crash 16:59 — c'est attendu, pas une bonne nouvelle.
- **Release en prod** : `c2d2d802` (Round 5, PR #436) depuis 2026-04-19 00:20 UTC.
- **PR #437** : statut inconnu à l'heure de ton tour. Vérifie merged / CI status / tout nouveau commit.
- **Pool DB** : 10 base + 10 overflow. **Pas touché** depuis R4.
- **Pool health endpoint** (`/api/health/pool`) : exposé mais le sandbox Claude **ne peut pas l'appeler** — demande au CTO de coller le JSON de sortie actuel, ou lis `packages/api/app/routers/health.py` pour comprendre ce qu'il retourne.
- **Tokens Sentry/Railway** transmis historiquement via chat : **à traiter comme compromis**. Ne les utilise pas, ne les redemande pas — attends une injection propre via env harness (`SENTRY_AUTH_TOKEN`, `RAILWAY_TOKEN`).
- **Mobile web deploy** (`apps/mobile/Dockerfile`) : cassé depuis PR #434 PostHog (pubspec.lock désync, posthog_flutter absent du lockfile). **Hors scope** de ton analyse — service Railway différent, pas lié au crash backend. Ne touche pas.

---

## Ce que tu dois creuser en priorité pour le 16:59

**Hypothèses à tester, pas à retenir les yeux fermés**. Classe-les par vraisemblance après collecte d'evidence, ne pars pas sur une idée fixe :

1. **Récidive `PendingRollbackError` sur un autre endpoint que community** — D3 n'a patché qu'un seul culprit. Si 16:59 vient d'un autre router qui swallow des exceptions sans `rollback()`, l'option "audit systématique" remonte en P0.
2. **Pool DB saturé** (`QueuePool limit of size 10 overflow 10 reached`) — c'était R1/R2 signature. Round 5 a ajouté du cache côté feed, mais `get_community_recommendations`, le digest, et d'autres endpoints peuvent encore saturer le pool. Besoin : état du pool à ±5min du crash.
3. **Timeouts digest cascadant** — le watcher a recensé 9 groupes `digest_generation_timeout` pré-saturation Sentry. Si 16:59 tombe dans une fenêtre de génération digest simultanée, l'hypothèse digest-bound reprend. D4 remonte.
4. **OOM / crash worker** — le scheduler interne (`app/workers/scheduler.py`) peut faire tomber le process si un worker blessé n'est pas isolé. Railway redémarre mais le restart laisse une trace dans les logs Railway.
5. **Healthcheck failure répété** → Railway tue le container. Healthcheck `/api/health` avec timeout 120s. Si un handler tient 120s, le container est reaped.
6. **Restart scheduler `_scheduled_restart`** (watcher §0 règle : interdit avant 7j de `QueuePool limit = 0`) — vérifier s'il a fiat un restart implicite à 16:59 (cf. `docs/bugs/bug-infinite-load-requests.md` pour l'heure programmée).

Pour chaque hypothèse, dis clairement : **evidence pour / evidence contre / incertitude résiduelle**. Pas de conclusion sans au moins un point de mesure.

---

## Données à demander au CTO (tu ne peux pas les récupérer seul)

Liste ça en haut de ton rapport, format prêt-à-copier :

1. **Railway logs** du service "Api" sur la fenêtre **2026-04-19 14:30 → 15:30 UTC** (= 16:30 → 17:30 Paris) : toute ligne `ERROR`, `CRITICAL`, `Out of memory`, `SIGTERM`, `Container stopped`, `Healthcheck failed`, `restart`, `exit code`.
2. **Sortie actuelle de** `curl https://facteur-production.up.railway.app/api/health/pool` (ou l'équivalent Railway auth si endpoint gated).
3. **Capture ou ID Sentry** s'il existe un event accepté malgré la saturation (parfois Sentry laisse passer les `fatal` même sur quota épuisé).
4. Heure précise de la restart manuelle effectuée par le CTO (à 1 min près).
5. Pattern user signalé au moment du crash (si connu) : combien d'users actifs, action répétitive, push notif venant de tomber, etc.

---

## Ce que tu dois produire

**Un seul document** : `.context/perf-watch/2026-04-19-round6-1659.md` avec la structure suivante (respecte les sections, même si tu écris "N/A — données manquantes" pour certaines) :

```
# Round 6 — crash 2026-04-19 ~16:59 Paris

## 1. Timeline certifiée
[minutage précis entre dernier deploy, dernier batch, crash, restart]

## 2. Evidence collectée
2.1 Sentry → [ce que tu as vu / confirmé absent]
2.2 Railway logs → [extraits bruts datés]
2.3 Pool health → [JSON copié]
2.4 Corrélations traffic → [si données]

## 3. Hypothèses classées
[tableau : hypothèse / evidence pour / evidence contre / P(vraie)]

## 4. Diagnostic retenu
[1 cause racine OU "indéterminable sans X" — sois honnête]

## 5. Articulation avec Rounds 1–5
[récidive mesurée / nouvelle famille / mutation d'une panne connue]

## 6. Ajustement du plan CTO 2026-04-19
6.1 D1 F1 (Sentry filter) → [reste P0 / downgrade / déjà OK]
6.2 D2 (rollback Round 5) → [toujours conditionné 24h / déclenche maintenant / N/A]
6.3 D3 ciblé (community rollback) → [suffisant / remonte en "audit systématique" P0 / P1]
6.4 D4 (scalabilité digest) → [toujours sprint planning / remonte en P1]
6.5 Nouvelle décision D5 ? → [si ton diagnostic révèle un angle non couvert]

## 7. Reco d'action immédiate (≤1h)
[le minimum pour que le serveur tienne cette nuit, sans sur-ingénierie]

## 8. Questions ouvertes pour le CTO
[ce que tu n'as pas pu trancher faute de données]
```

---

## Contraintes dures (ne les négocie pas)

- **N'édite aucun fichier de code** (`packages/api/app/**`, `apps/mobile/**`). Tu es en analyse.
- **Ne merge rien**, ne push rien, ne rebase rien.
- **Ne rotate aucun token**, ne relance aucun deploy Railway. CTO only.
- **Ne touche pas à la branche `claude/backend-stability-scalability-PAzL7`** — PR #437 est en attente de merge par le CTO.
- **Staging est déprécié** (CLAUDE.md §BRANCHE PAR DÉFAUT) — ne le mentionne pas comme option.
- **Alembic** : si tu suspectes une migration comme cause, **ne lance aucune migration Alembic sur Railway** (cf. CLAUDE.md §Contraintes Techniques). Fournis uniquement le SQL à exécuter manuellement via Supabase SQL Editor dans ta reco.
- **Règle §0 du watcher** : interdit de toucher `pool_size`, `overflow`, `_scheduled_restart`, `pool_recycle` tant qu'on n'a pas 7 jours consécutifs de `QueuePool limit = 0`. Si tu veux lever cette règle, argumente explicitement — le CTO décide.
- **Scope limité au backend "Api"**. Mobile web deploy cassé (pubspec.lock désync posthog_flutter, PR #434) est un **autre incident** — ne le traite pas ici.
- **Pas d'emoji** dans le doc final.

---

## Style attendu

- Factuel, daté, sourcé. Chaque affirmation forte est soit sourcée à un fichier/ligne, soit à un event Sentry/Railway, soit marquée "inférence — incertitude".
- Pas d'auto-satisfaction, pas de recommandation sans evidence.
- Si une donnée manque, tu **nommes** la donnée manquante et tu proposes une action CTO pour la débloquer. Tu ne spécules pas pour combler.
- Livrable cible : **≤ 400 lignes** markdown, tableaux préférés aux paragraphes quand c'est possible.

---

## Sortie finale attendue

Quand tu as fini, poste UN message au CTO :

```
Round 6 analysis ready → .context/perf-watch/2026-04-19-round6-1659.md
Diagnostic: <1 phrase>
Plan ajusté: <D1/D2/D3/D4/D5 en une ligne chacun>
Blockers pour toi: <liste des données manquantes, 3 max>
```

Et stop. N'enchaîne pas sur du code, n'ouvre pas de PR. Attends arbitrage CTO.
