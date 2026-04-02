# CLAUDE.md — Facteur

> App mobile digest quotidien (5 articles, "moment de fermeture"). Flutter + FastAPI + PostgreSQL (Supabase) + Railway.

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

1. Crée la PR vers `main` — **toujours spécifier `--base main`** (`staging` est la branche par défaut du repo GitHub, `gh pr create` prend `staging` si `--base` n'est pas précisé)
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
