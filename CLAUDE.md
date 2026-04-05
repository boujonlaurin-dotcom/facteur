# CLAUDE.md — Facteur

> App mobile digest quotidien (5 articles, "moment de fermeture"). Flutter + FastAPI + PostgreSQL (Supabase) + Railway.

---

## BRANCHE PAR DÉFAUT — RÈGLE ABSOLUE

> **`staging` est DÉPRÉCIÉ. NE JAMAIS merger, créer de PR, ni pousser vers `staging`.**
> **Toute PR DOIT cibler `main` avec `--base main`.**
> Un hook (`pre-bash-no-staging.sh`) bloque automatiquement les `gh pr create` sans `--base main`.

---

## Contraintes Techniques (LOCKED)

- Python **3.12.x** uniquement (3.13+ casse pydantic)
- `list[]`, `dict[]`, `X | None` natifs (jamais `from typing import List, Dict, Optional`)
- JWT secret identique mobile ↔ backend
- Alembic : exactement 1 head, jamais d'exécution sur Railway (SQL via Supabase SQL Editor)
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
3. **Tests E2E / UI** : utilise le **Playwright MCP** pour tester les flux visuels :
   - Démarre l'API locale si besoin (`uvicorn app.main:app --port 8080`)
   - Navigue dans l'app, remplit les formulaires, vérifie les réponses
   - Valide les cas nominaux + cas limites
4. **Suite complète** : lance la suite de tests complète (`pytest -v` backend, `flutter test` mobile) et corrige tout échec
5. Le hook `stop-verify-tests.sh` vérifie automatiquement que les tests passent avant de terminer — si un test échoue, l'agent doit corriger avant de pouvoir conclure

### 3. PR (confirmation requise)

1. Crée la PR vers `main` — **OBLIGATOIRE : `--base main`** (`staging` est DÉPRÉCIÉ, le hook `pre-bash-no-staging.sh` bloquera toute PR sans `--base main`)
2. **STOP → Notifie "PR #XX prête pour review"**
3. Attends CI green + Peer Review APPROVED avant merge

---

## Hooks Actifs (`.claude/settings.json`)

| Hook | Quand | Effet |
|------|-------|-------|
| `pre-edit-alembic-deploy.sh` | Avant Edit/Write | Bloque si migration Alembic risquée |
| `post-edit-python-guardrails.sh` | Après Edit/Write | Bloque si `List[]`/`Dict[]` from typing |
| `post-edit-alembic-heads.sh` | Après Edit/Write | Bloque si >1 head Alembic |
| `post-edit-auto-test.sh` | Après Edit/Write | Lance auto les tests du fichier modifié |
| `pre-bash-no-staging.sh` | Avant Bash | Bloque `gh pr create` sans `--base main` |
| `stop-verify-tests.sh` | Avant fin réponse | Bloque si tests échouent |

## MCP Servers

| Serveur | Usage |
|---------|-------|
| **Playwright** | Tests UI/E2E autonomes (navigation, formulaires, assertions visuelles) |
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

# E2E API (scripts QA existants)
bash docs/qa/scripts/verify_<task>.sh
```

---

## Références (lire à la demande)

- [Navigation Matrix](docs/agent-brain/navigation-matrix.md) — workflows par type de tâche
- [Safety Guardrails](docs/agent-brain/safety-guardrails.md) — guardrails + safety protocols
- [PRD](docs/prd.md) / [Architecture](docs/architecture.md) / [Front-end Spec](docs/front-end-spec.md)
- Agents BMAD : `.bmad-core/agents/` (dev, po, architect, qa)
- Scripts QA : `docs/qa/scripts/`
## 🧪 Validation Feature via Chrome (Agent QA)

Après la phase VERIFY de l'agent dev et la validation du PO (Laurin), une étape de **validation web automatisée** peut être déclenchée pour les features touchant l'UI.

### Workflow dev → QA

1. **L'agent dev** complète sa feature et écrit un QA Handoff dans `.context/qa-handoff.md` en suivant le template `.context/qa-handoff-template.md`. Ce handoff décrit les écrans impactés, les scénarios de test (happy path + edge cases), et les critères d'acceptation.

2. **L'agent dev STOP** et notifie :
   "Feature prête pour validation QA web — handoff dans .context/qa-handoff.md. Lancer /validate-feature pour tester via Chrome."

3. **L'utilisateur** lance la commande `/validate-feature` (dans un workspace séparé ou le même en mode QA). L'agent QA :
   - Ouvre l'app web dans Chrome (viewport mobile 390x844)
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
/validate-feature   # Lit .context/qa-handoff.md et teste via Chrome
```

### Checklist complémentaire (phase VERIFY)

- [ ] QA Handoff rédigé (`.context/qa-handoff.md`) si feature UI
- [ ] /validate-feature exécuté si feature UI (rapport QA dans .context/)
