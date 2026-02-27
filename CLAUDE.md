# CLAUDE.md - Facteur Agent Protocol

> **Tu es un Senior Developer BMAD travaillant sur Facteur.**
>
> **Pour petits ajustements simples (<10 lignes), lis [QUICK_START.md](QUICK_START.md) d'abord.**
> **Ce fichier est pour tâches complexes (features, bugs zones à risque, maintenance).**
>
> Lis ce fichier EN ENTIER pour tâches complexes. 260 lignes essentielles, zéro fluff.

---

## 🎯 Projet: Facteur

**Quoi**: App mobile digest quotidien (5 articles, "moment de fermeture")
**Valeur**: Users "finished" et informés en 2-4 minutes (Slow Media)
**Stack**: Flutter + FastAPI + PostgreSQL (Supabase) + Railway
**Phase**: Post-MVP v1.0.1, Epic 10 (Digest Central) en cours

### Contraintes Stack (LOCKED)

| Layer | Technology | Contrainte |
|-------|-----------|-----------|
| Mobile | Flutter/Dart | SDK >=3.0.0 <4.0.0 |
| Backend | FastAPI/Python | **3.12 ONLY** (3.13+ casse pydantic) |
| DB | PostgreSQL | Via Supabase (managed) |
| Auth | Supabase Auth | JWT RS256 |
| State | Riverpod 2.5 | Code gen (build_runner) |

**Contraintes dures**:
- Python **3.12.x** uniquement (jamais 3.13+)
- `list[]` natif Python (pas `List` de typing) → [Guardrail #1](docs/agent-brain/safety-guardrails.md#python-type-hints)
- JWT secret identique mobile ↔ backend

---

## 🎭 ÉTAPE 1: Identification Agent BMAD (OBLIGATOIRE EN PREMIER)

**Avant M.A.D.A, identifie ton rôle BMAD:**

| Type Tâche | Agent BMAD | Profile |
|------------|------------|---------|
| Feature complète | **@dev** | [Dev Agent](.bmad-core/agents/dev.md) |
| Story creation | **@po** | [PO Agent](.bmad-core/agents/po.md) |
| Architecture decision | **@architect** | [Architect](.bmad-core/agents/architect.md) |
| Bug fix | **@dev** | [Dev Agent](.bmad-core/agents/dev.md) |
| QA / Verification | **@qa** | [QA Agent](.bmad-core/agents/qa.md) |

**Action**: Lis ton agent profile BMAD (200 lignes) + sections Agent Brain ciblées.

---

## 🔄 ÉTAPE 2: Cycle M.A.D.A (Measure → Decide → Act → Verify)

| Phase | Actions | **Documentation OBLIGATOIRE** | **Hooks OBLIGATOIRES** | STOP |
|-------|---------|------------------------------|------------------------|------|
| **MEASURE** | 1. Setup worktree isolé<br>2. Classifie (Feature/Bug/Maintenance)<br>3. Lis docs via [Navigation Matrix](docs/agent-brain/navigation-matrix.md) | **Crée/MAJ Story OU Bug Doc**<br>([Templates](docs/stories/README.md)) | `.claude-hooks/check-worktree-isolation.sh` | - |
| **DECIDE** | Produit `implementation_plan.md` | MAJ Story: "Technical Approach" | - | **STOP**<br>→ GO user |
| **ACT** | Implémente atomiquement | MAJ Story: tasks ✓, File List, Changelog | `.claude-hooks/pre-code-change.sh` | - |
| **VERIFY** | Crée script QA one-liner | MAJ Story/Bug: "Verification", script path | - | **STOP** |
| **REVIEW** | PR Lifecycle: CI → Staging → Peer Review ([ÉTAPE 3](#-étape-3--pr-lifecycle-ci--staging--review--merge)) | PR green + staging verified + review APPROVED | - | **STOP**<br>→ GO user |

### Détails M.A.D.A par Type

**Feature**:
1. Measure: Crée `docs/stories/core/{epic}.{story}.{nom}.md` ([Navigation Matrix - Feature](docs/agent-brain/navigation-matrix.md#1-feature--evolution))
2. Decide: Plan technique + notify user
3. Act: Code + MAJ story (tasks, File List, Changelog)
4. Verify: `docs/qa/scripts/verify_<task>.sh` + one-liner proof

**Bug**:
1. Measure: Crée `docs/bugs/bug-{nom}.md` ([Navigation Matrix - Bug](docs/agent-brain/navigation-matrix.md#2-bug-fix))
2. Decide: Root cause analysis + plan fix
3. Act: Fix minimal + MAJ bug doc (Solution, Files Modified)
4. Verify: Prevention script + regression test

**Maintenance**:
1. Measure: Crée `docs/maintenance/maintenance-{nom}.md` ([Navigation Matrix - Maintenance](docs/agent-brain/navigation-matrix.md#3-maintenance--refactoring))
2. Decide: Impact analysis + rollback plan
3. Act: Migration en étapes
4. Verify: Rollback test + documentation

---

## 🚀 ÉTAPE 3: PR Lifecycle (CI → Staging → Review → Merge)

**Règle bloquante** : Aucun merge vers `main` sans CI green + staging verified + Peer Review APPROVED.

### 3.1 Ouvrir la PR

```bash
git push origin <branch-name>
gh pr create --title "<type>: <description>" --body "$(cat .github/pull_request_template.md)"
```

CI s'exécute automatiquement : `lint` + `test` + `build` (Docker) + `verify` (BMAD).
**Ne pas continuer tant que CI est rouge.**

### 3.2 Déployer en Staging

**Automatique** : `deploy-staging.yml` se déclenche dès que `lint`, `test` et `build` passent sur la PR.
Smoke tests inclus (health, readiness, environment check). Visible dans les checks de la PR.

Fallback manuel si besoin : `gh workflow run deploy-staging.yml --ref <branch-name>`

### 3.3 Handoff : l'agent dev prépare la review

Avant de STOP, l'agent dev **écrit un résumé de handoff** dans `.context/pr-handoff.md` :

```markdown
# PR #XX — <titre>
## Quoi : <résumé en 2-3 lignes>
## Pourquoi : <problème résolu / valeur ajoutée>
## Zones à risque : <fichiers/modules critiques modifiés>
## Ce que le reviewer doit vérifier en priorité : <points d'attention>
```

Puis l'agent STOP et notifie : **"PR #XX prête pour Peer Review — handoff dans `.context/pr-handoff.md`"**

### 3.4 Peer Review Conductor

1. **L'utilisateur ouvre un workspace Conductor séparé** sur la branche
2. **Prompt de review** (le reviewer lit automatiquement `.context/pr-handoff.md` + le diff) :

> Lis `.context/pr-handoff.md` pour le contexte, puis review le workspace diff en peer review senior.
> Check: Security, Guardrails Facteur (`list[]`, stale token), Breaking changes, Test coverage, Architecture, Performance.
> Utilise l'outil DiffComment pour laisser tes commentaires directement sur les lignes de code.
> Output final : BLOCKERS / WARNINGS / SUGGESTIONS / **APPROVED** ou **NOT APPROVED**

3. **Si blockers** → copier la sortie du reviewer dans le workspace de l'agent dev → l'agent fix → re-push → CI re-run
4. **Si APPROVED** → merge autorisé

### 3.5 Merge & Production

Merge via **GitHub UI** (bouton "Squash and merge") ou CLI :
```bash
gh pr merge <PR-number> --squash
```
Railway auto-déploie sur production via push to main.

### Règles

- L'agent de review est **un workspace Conductor séparé** (pas le même agent qui a codé)
- L'agent de dev **NE DOIT PAS** se self-review ni merger sans ce processus
- PR docs-only (stories, README) : skip staging (cocher "N/A" dans la PR template)

---

## 🗺️ Navigation Rapide par Type

**Selon ton type de tâche, suis ce workflow:**

| Type | Workflow Complet |
|------|------------------|
| **Feature** | [Feature Workflow](docs/agent-brain/navigation-matrix.md#1-feature--evolution) → PRD → Story → Specs → Mobile/Backend Maps → Code |
| **Bug** | [Bug Workflow](docs/agent-brain/navigation-matrix.md#2-bug-fix) → Bug Template → Retrospectives → Root Cause → Fix → Prevention |
| **Maintenance** | [Maintenance Workflow](docs/agent-brain/navigation-matrix.md#3-maintenance--refactoring) → État Actuel → Impact → Plan → Rollback |

**Guide complet**: [Agent Brain README](docs/agent-brain/README.md)

---

## 🛡️ Top 3 Guardrails Techniques (CRITIQUE)

Issus de bugs réels en production. **Lecture obligatoire**: [Safety Guardrails](docs/agent-brain/safety-guardrails.md)

| # | Pattern | Quick Fix | Détails |
|---|---------|-----------|---------|
| 1 | **Python Type Hints** | `list[]` (PAS `List[]` from typing) | [Guardrail #1](docs/agent-brain/safety-guardrails.md#python-type-hints) |
| 2 | **Supabase Stale Token** | Jamais trust `email_confirmed_at` JWT seul | [Guardrail #2](docs/agent-brain/safety-guardrails.md#supabase-stale-token) |
| 3 | **Worktree Isolation** | Un agent = un worktree = une branche | [Guardrail #3](docs/agent-brain/safety-guardrails.md#worktree-isolation) |

**Zones à risque élevé** (Auth/Router/Infra/DB): Lis [Safety Protocols](docs/agent-brain/safety-guardrails.md#safety-protocols) AVANT toute modif.

---

## 📂 Chemins Critiques

**Projet Root**: `/Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur/`

### Docs Essentiels

```
docs/
├── prd.md, architecture.md, front-end-spec.md  # Specs
├── agent-brain/                                 # Navigation agent
│   ├── README.md                                # Guide orientation
│   ├── navigation-matrix.md                     # Type tâche → Docs → Codebase
│   └── safety-guardrails.md                     # Safety + Guardrails fusionnés
├── stories/core/10.digest-central/              # Epic actuel
├── bugs/, maintenance/                          # Tracking
└── qa/scripts/                                  # 34 scripts vérification
```

### Codebase (Simplifié)

```
apps/mobile/lib/features/        # 13 modules (digest, feed, auth, sources...)
  └── {feature}/screens/, providers/, repositories/, widgets/

packages/api/app/
  ├── routers/                   # 14 endpoints
  ├── services/                  # Business logic
  ├── models/                    # SQLAlchemy ORM
  └── workers/                   # Background jobs

.bmad-core/agents/               # Agents BMAD (@dev, @pm, @po, @architect, @qa)
.claude-hooks/                   # Hooks de sécurité
```

**Voir [Navigation Matrix](docs/agent-brain/navigation-matrix.md) pour chemins détaillés par cas d'usage.**

---

## 🚀 Quick Commands

### Mobile
```bash
cd apps/mobile
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api/
dart run build_runner build --delete-conflicting-outputs  # Après Freezed/Riverpod
flutter test && flutter analyze
```

### Backend
```bash
cd packages/api && source venv/bin/activate
uvicorn app.main:app --reload --port 8080
curl http://localhost:8080/api/health
alembic upgrade head  # Migrations
pytest -v
```

### Worktree (OBLIGATOIRE)
```bash
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur
git checkout main && git pull origin main
git checkout -b <agent>-<tache>  # Ex: dev-digest-share-button
git worktree add ../<agent>-<tache> <agent>-<tache>
cd ../<agent>-<tache>

# Vérif isolation
./.claude-hooks/check-worktree-isolation.sh

# Après merge
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur
git worktree remove ../<agent>-<tache>
```

---

## 🧼 Hygiène Codebase (Règles d'Or)

- **Git**: Un sujet = un commit. Branche dédiée. Pas de mélange mobile/API/docs.
- **Artifacts**: Jamais commit `analysis_*.txt`, `*.lock` (sauf pubspec.lock), logs → `.gitignore`
- **Hooks**: Exécute hooks AVANT actions ([Hooks README](.claude-hooks/README.md))
- **Release**: `docs/qa/scripts/verify_release.sh` avant déploiement
- **Bypass actif**: Documente dans `docs/maintenance/`

---

## 📋 Checklist Agent (Quick Start)

**Avant de commencer**:

1. [ ] **Agent BMAD identifié** (@dev, @pm, @po, @architect, @qa)
2. [ ] **Agent profile BMAD lu** (`.bmad-core/agents/{agent}.md`)
3. [ ] **Worktree isolé créé** (`.claude-hooks/check-worktree-isolation.sh`)
4. [ ] **Type identifié** (Feature / Bug / Maintenance)
5. [ ] **Navigation Matrix lue** → Workflow identifié
6. [ ] **Story/Bug Doc créée/MAJ** (OBLIGATOIRE avant code)

**Pendant M.A.D.A**:

7. [ ] **Plan rédigé** (`implementation_plan.md`)
8. [ ] **User notifié** → **STOP** → Attente GO
9. [ ] **Pre-code-change hook** (`.claude-hooks/pre-code-change.sh`)
10. [ ] **Safety Guardrails vérifiés** (si zone à risque)
11. [ ] **Story/Bug MAJ** (tasks ✓, File List, Changelog)
12. [ ] **Script vérification** (`docs/qa/scripts/verify_<task>.sh`)

**Avant merge** ([ÉTAPE 3](#-étape-3--pr-lifecycle-ci--staging--review--merge)):

13. [ ] **PR ouverte** + CI green (lint, test, build, verify)
14. [ ] **Staging déployé** + smoke tests passed (`deploy-staging.yml`)
15. [ ] **Peer Review Conductor** → Workspace séparé → APPROVED
16. [ ] **Merge** (squash) → Production auto-deploy
17. [ ] **Cleanup worktree** (après merge)

---

## 🔗 Références Complètes

**Documentation complète** (ne lis que si besoin ciblé):
- [Agent Brain README](docs/agent-brain/README.md) - Guide orientation
- [Navigation Matrix](docs/agent-brain/navigation-matrix.md) - Workflows détaillés
- [Safety Guardrails](docs/agent-brain/safety-guardrails.md) - Tous guardrails + safety protocols
- [PRD](docs/prd.md) - Product requirements
- [Architecture](docs/architecture.md) - Specs techniques complètes
- [Front-end Spec](docs/front-end-spec.md) - UI/UX design system
- [BMAD User Guide](.bmad-core/user-guide.md) - Méthodologie complète

**BMAD Agents** (`.bmad-core/agents/`):
- `dev.md` - Full-stack developer
- `pm.md` - Product manager
- `po.md` - Product owner
- `architect.md` - Architecture decisions
- `qa.md` - Quality assurance

**Hooks** (`.claude-hooks/`):
- `check-worktree-isolation.sh` - Vérifie worktree (EN PREMIER)
- `pre-code-change.sh` - Vérifie Story/Bug Doc (AVANT code)

---

*Dernière MAJ: 2026-02-27*
*Mainteneurs: Human (Laurin) + AI agents collaborativement*
*Ancien CLAUDE.md (590 lignes): [docs/CLAUDE.md.backup-2026-02-14](docs/CLAUDE.md.backup-2026-02-14)*
*Cursor legacy: [docs/archive/cursor-legacy-2026-02-14](docs/archive/cursor-legacy-2026-02-14)*
