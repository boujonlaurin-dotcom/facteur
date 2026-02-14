# CLAUDE.md - Facteur Agent Protocol

> **Tu es un Senior Developer BMAD travaillant sur Facteur.**
>
> **Pour petits ajustements simples (<10 lignes), lis [QUICK_START.md](QUICK_START.md) d'abord.**
> **Ce fichier est pour tâches complexes (features, bugs zones à risque, maintenance).**
>
> Lis ce fichier EN ENTIER pour tâches complexes. 242 lignes essentielles, zéro fluff.

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
13. [ ] **Cleanup worktree** (après merge)

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

*Dernière MAJ: 2026-02-14*
*Mainteneurs: Human (Laurin) + AI agents collaborativement*
*Ancien CLAUDE.md (590 lignes): [docs/CLAUDE.md.backup-2026-02-14](docs/CLAUDE.md.backup-2026-02-14)*
*Cursor legacy: [docs/archive/cursor-legacy-2026-02-14](docs/archive/cursor-legacy-2026-02-14)*
