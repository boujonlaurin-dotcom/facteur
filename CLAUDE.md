# CLAUDE.md — Facteur

> App mobile digest quotidien (5 articles, "moment de fermeture"). Flutter + FastAPI + PostgreSQL (Supabase) + Railway.

---

## BRANCHES & ENVIRONNEMENTS — RÈGLE ABSOLUE

> **`main` = environnement STAGING CONTINU** (backend `api-staging-40d3`, APK flavor
> `staging` = `com.example.facteur.staging`, canal `beta`). C'est l'env que TU testes.
> **Toute PR DOIT cibler `main` avec `--base main`** — le workflow quotidien est inchangé.
>
> **`production` = branche HEBDO** (backend `facteur-production`, APK flavor `prod`,
> canal `stable` → vrais users). Elle n'est **JAMAIS** une cible de PR et ne reçoit
> **jamais** de commit direct : elle est avancée **uniquement** par le bouton manuel
> GitHub Actions **« Weekly Production Release »** (`weekly-release.yml`).
>
> **`staging` (l'ancienne branche) est abandonnée** — ne plus l'utiliser.
> Un hook (`pre-bash-no-staging.sh`) bloque tout `gh pr create` sans `--base main`.

---

## Contraintes Techniques (LOCKED)

- Python **3.12.x** uniquement (3.13+ casse pydantic)
- `list[]`, `dict[]`, `X | None` natifs (jamais `from typing import List, Dict, Optional`)
- JWT secret identique mobile ↔ backend
- **Alembic est la seule source de vérité pour le schéma DB.** Tout DDL (ALTER, CREATE, DROP) passe par une migration générée via `alembic revision --autogenerate -m "<desc>"` dans la PR qui le requiert. **Pas de SQL manuel via Supabase SQL Editor** — c'est le pattern qui a causé l'incident de drift d'avril 2026 (cf. [runbook de récupération](docs/runbooks/recover-from-alembic-drift.md)). Exactement 1 head Alembic. Le `Dockerfile` exécute `alembic upgrade head` au démarrage de chaque conteneur Railway — donc une migration cassée plante le déploiement, et stamper prod *avant* de merger une refonte de la chaîne est obligatoire (cf. runbook).
- **Migrations additives / expand-contract OBLIGATOIRE.** `main` (staging) et `production` (prod) **partagent la DB Supabase de prod**. Le `Dockerfile` joue `alembic upgrade head` au boot des **deux** services : une migration mergée dans `main` touche donc la DB partagée **dès le boot staging**, pendant que le backend prod (ancien code `production`) tourne encore dessus jusqu'à 1 semaine. ⇒ jamais de `DROP`/rename/`NOT NULL`-sur-peuplé en une étape ; étaler sur 2 cycles hebdo (semaine N ajoute, semaine N+1 retire). Migrations idempotentes (no-op si déjà à head), gardées sur les deux backends.
- Zones à risque (Auth, Router, DB, Infra) → lire [Safety Guardrails](docs/agent-brain/safety-guardrails.md) AVANT modif

---

## Workflow : PLAN → CODE+TEST → PR

### 1. PLAN (confirmation requise)

1. Classifie la tâche : **Feature** / **Bug** / **Maintenance**
2. Lis les docs nécessaires via la [Navigation Matrix](docs/agent-brain/navigation-matrix.md)
3. Crée la documentation :
   - Feature → `docs/stories/core/{epic}.{story}.{nom}.md`
   - Bug → `docs/bugs/bug-{nom}.md`
   - Maintenance → `docs/maintenance/maintenance-{nom}.md`
4. Rédige le plan technique dans la Story/Bug doc
5. **STOP → Présente le plan à l'utilisateur → Attends GO**

### 2. CODE + TEST (autonome)

Après le GO utilisateur, implémente et teste en autonomie :

1. **Code** : implémente atomiquement, MAJ story (tasks ✓, fichiers modifiés)
2. **Tests unitaires** : les hooks `post-edit-auto-test.sh` lancent automatiquement les tests liés à chaque fichier modifié. Corrige les échecs immédiatement.
3. **Tests E2E / UI** : utilise le **Playwright Agent CLI** (`playwright-cli`, skills `facteur-qa-web` + `playwright-cli`) pour tester les flux visuels sur le build web :
   - Démarre l'API locale si besoin (`uvicorn app.main:app --port 8080`)
   - Navigue dans l'app, remplit les formulaires, vérifie les réponses
   - Valide les cas nominaux + cas limites
   - ⚠️ Flutter web = canvas : active la sémantique au boot (cf. skill `facteur-qa-web`) avant tout `snapshot`
4. **Suite complète** : lance la suite de tests complète (`pytest -v` backend, `flutter test` mobile) et corrige tout échec
5. Le hook `stop-verify-tests.sh` vérifie automatiquement que les tests passent avant de terminer — si un test échoue, l'agent doit corriger avant de pouvoir conclure

> **Raccourci recommandé** : une fois le code écrit, lance **[`/go`](.claude/commands/go.md)** pour enchaîner automatiquement VERIFY (tests + Playwright + scripts QA) → SIMPLIFY (skill `simplify`) → PR vers `main`. Voir [/go — chaîne verify→simplify→PR](#go--chaîne-verifysimplifypr) plus bas.

### 3. PR (confirmation requise)

1. Crée la PR vers `main` — **OBLIGATOIRE : `--base main`** (env staging continu ; le hook `pre-bash-no-staging.sh` bloquera toute PR sans `--base main`). **Ne jamais cibler `production`** (avancée seulement par le bouton hebdo).
2. **STOP → Notifie "PR #XX prête pour review"**
3. Attends CI green + Peer Review APPROVED avant merge

> La commande `/go` prend en charge les étapes 2 et 3 (push, création PR avec base `main`, body depuis `.context/pr-handoff.md`, arrêt après "PR #XX prête pour review").

---

## Hooks Actifs (`.claude/settings.json`)

| Hook | Quand | Effet |
|------|-------|-------|
| `pre-edit-alembic-deploy.sh` | Avant Edit/Write | Avertit si édition d'un fichier deploy touche `alembic upgrade`/`stamp` (le `Dockerfile` exécute la chaîne au boot — toute erreur plante le déploiement Railway) |
| `post-edit-python-guardrails.sh` | Après Edit/Write | Bloque si `List[]`/`Dict[]` from typing |
| `post-edit-alembic-heads.sh` | Après Edit/Write | Bloque si >1 head Alembic |
| `post-edit-auto-test.sh` | Après Edit/Write | Lance auto les tests du fichier modifié |
| `pre-bash-no-staging.sh` | Avant Bash | Bloque `gh pr create` sans `--base main` |
| `stop-verify-tests.sh` | Avant fin réponse | Bloque si tests échouent |

## Changelog utilisateur

Si ta PR dépasse **400 lignes de diff** OU si elle livre un changement user-visible important (nouvelle feature, refonte UX, fix d'un bug bloquant connu), ajoute une entrée dans `apps/mobile/assets/changelog.json` (clé `unreleased`) :

```json
{ "tag": "Perspectives", "summary": "Clustering plus pertinent dans les perspectives." }
```

- `tag` : **1-2 mots max**, orienté feature (ex: « Perspectives », « Tournée », « Onboarding »). Sert au bandeau cumulatif en haut du Flâner.
- `summary` : **1 phrase courte** sur la **valeur user** (pas la techno). Sert à la modal « Quoi de neuf » (bullet point).

L'agent peut **by-passer la règle des 400 lignes** si elle ne reflète pas l'impact réel (gros refactor invisible / petit fix UX très visible). Le script `scripts/promote_changelog.py --version X.Y.Z` déplace `unreleased` → `released` au moment du bump de version.

## Outillage UI/E2E & MCP Servers

**Tests UI/E2E** : **Playwright Agent CLI** (`playwright-cli`, épinglé dans `package.json`).
Skills : `.claude/skills/facteur-qa-web/` (spécificités Facteur) + `.claude/skills/playwright-cli/`
(syntaxe). Pilote le build web Flutter ; voir aussi `/validate-feature`. (Le MCP `@playwright/mcp`
a été retiré au profit du CLI.)

| Serveur MCP | Usage |
|---------|-------|
| Sentry | Monitoring erreurs production |
| Railway | Déploiement et logs |
| Supabase | Accès DB et Auth |

## Tests : Commandes

```bash
# Backend
cd packages/api && pytest -v
cd packages/api && pytest tests/test_specific.py -x -q

# Mobile
cd apps/mobile && flutter test
cd apps/mobile && flutter analyze
# NB : l'Android a 2 flavors (staging|prod) → tout build/run APK exige --flavor.
# Smoke Kotlin local (cf. memory APK post-merge) : flutter build apk --debug --flavor staging

# E2E API (scripts QA existants)
bash docs/qa/scripts/verify_<task>.sh
```

---

## Références (lire à la demande)

- [Navigation Matrix](docs/agent-brain/navigation-matrix.md) — workflows par type de tâche
- [Safety Guardrails](docs/agent-brain/safety-guardrails.md) — guardrails + safety protocols
- [Investigation Playbook](docs/agent-brain/investigation-playbook.md) — outils par scénario prod (bug, usage, migration, logs, sécurité)
- [Runbook : récupération de drift Alembic](docs/runbooks/recover-from-alembic-drift.md) — étapes à suivre si la chaîne Alembic se met à diverger de prod
- [Runbook : réconcilier `production` (release hebdo cassé au `--ff-only`)](docs/runbooks/recover-from-production-divergence.md) — si `production` a divergé suite à un commit direct (merge commit arbre-identique sans squash + piège push merge-commit + piège GITHUB_TOKEN)
- [Claude Access Setup](docs/infra/claude-access-setup.md) — secrets + accès multi-services (Supabase/Railway/Sentry/PostHog)
- [PRD](docs/prd.md) / [Architecture](docs/architecture.md) / [Front-end Spec](docs/front-end-spec.md)
- Agents BMAD : `.bmad-core/agents/` (dev, po, architect, qa)
- Scripts QA : `docs/qa/scripts/`

### Santé des accès agents

Le hook `SessionStart` lance un healthcheck `--fast` au démarrage. Scanne les lignes `[secrets]` dans les premiers messages de la session ; un `[FAIL]` doit être traité avant toute investigation prod. Healthcheck complet :

```bash
bash scripts/healthcheck-agent-secrets.sh
```
## 🧪 Validation Feature web via Playwright Agent CLI (Agent QA)

Après la phase VERIFY de l'agent dev et la validation du PO (Laurin), une étape de **validation web automatisée** peut être déclenchée pour les features touchant l'UI.

### Workflow dev → QA

1. **L'agent dev** complète sa feature et écrit un QA Handoff dans `.context/qa-handoff.md` en suivant le template `.context/qa-handoff-template.md`. Ce handoff décrit les écrans impactés, les scénarios de test (happy path + edge cases), et les critères d'acceptation.

2. **L'agent dev STOP** et notifie :
   "Feature prête pour validation QA web — handoff dans .context/qa-handoff.md. Lancer /validate-feature pour tester via le Playwright Agent CLI."

3. **L'utilisateur** lance la commande `/validate-feature` (dans un workspace séparé ou le même en mode QA). L'agent QA :
   - Ouvre le build web Flutter avec `playwright-cli` (viewport mobile 390x844, sémantique activée — cf. skill `facteur-qa-web`)
   - Exécute chaque scénario du handoff
   - Capture des screenshots avant/après chaque interaction
   - Vérifie les erreurs console et les requêtes réseau
   - Produit un rapport de validation structuré

4. **Si APPROVED** → merge autorisé (passe à l'étape PR Lifecycle)
   **Si FAIL** → l'agent QA liste les bugs trouvés, propose de créer des issues GitHub, et l'agent dev reprend le fix.

### Quand utiliser /validate-feature

- Features touchant l'UI mobile (écrans, composants, navigation)
- Bugs visuels ou d'interaction signalés par les utilisateurs
- Avant un déploiement en production pour les features critiques

### Quand ne PAS utiliser

- Changements backend-only (API, workers, migrations)
- Modifications docs-only
- Refactoring sans impact visuel

### Commande

```
/validate-feature   # Lit .context/qa-handoff.md et teste via le Playwright Agent CLI
```

### Checklist complémentaire (phase VERIFY)

- [ ] QA Handoff rédigé (`.context/qa-handoff.md`) si feature UI
- [ ] /validate-feature exécuté si feature UI (rapport QA dans .context/)

---

## /go — chaîne verify→simplify→PR

> **Commande de référence pour conclure une tâche.** Fichier :
> [`.claude/commands/go.md`](.claude/commands/go.md).

Quand l'agent a fini d'écrire le code, `/go` prend le relais et fait **en
autonomie** les 3 étapes qui restent — avec la preuve que ça marche :

1. **VERIFY**
   - Backend : `pytest -v` + démarrage `uvicorn` + `curl` sur les endpoints
     touchés (cas nominal + 1 cas limite) + `docs/qa/scripts/verify_<task>.sh`
     si présent.
   - Mobile : `flutter test && flutter analyze` + Playwright Agent CLI
     (`playwright-cli`, skill `facteur-qa-web` ; viewport 390x844, sémantique
     activée au boot, console sans erreurs, réseau sans 4xx/5xx inattendus,
     edge cases).
   - Alembic : exactement 1 head, `upgrade head` local OK. Le `Dockerfile` rejouera `alembic upgrade head` au prochain boot Railway — une migration cassée plante le déploiement, donc tester localement contre une DB *vide* (`make db-reset`) est non-négociable.
   - Re-run systématique de la suite complète avant de conclure
     (anticipe le hook `stop-verify-tests.sh`).
2. **SIMPLIFY** : invoque la skill `simplify` puis re-run VERIFY si du code a
   été modifié.
3. **PR** : push (`-u origin`, retry backoff 2/4/8/16s), création PR via
   `mcp__github__create_pull_request` vers `main` **obligatoirement**, body
   repris depuis `.context/pr-handoff.md` s'il existe, puis STOP avec
   `PR #<num> prête pour review — <url>` et propose
   `subscribe_pr_activity` pour suivre CI/reviews.

### Quand lancer /go

- **Toujours** en fin de tâche, quelle qu'elle soit (feature, bug, maintenance).
- Remplace les étapes 2 (phase VERIFY) + 3 du workflow PLAN → CODE+TEST → PR.
- Compatible avec `/validate-feature` : si la feature touche l'UI, lance
  `/validate-feature` *avant* `/go` pour générer le rapport QA, puis `/go`
  enchaîne simplify + PR.

### Règles non négociables de /go

- `--base main` **toujours** (hook : `--base main` obligatoire ; jamais `production`).
- Jamais `--no-verify`, jamais `--force-with-lease` sur `main`, jamais amender
  un commit déjà poussé.
- Si VERIFY échoue à la 2e tentative après fix → **stop** et demande à
  l'utilisateur au lieu de boucler.
