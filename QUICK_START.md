# QUICK START - Facteur Agent

> **Pour petits ajustements simples (<10 lignes code, bugfixes triviaux).**
> **Pour features/bugs complexes, lis [CLAUDE.md](CLAUDE.md).**

---

## 🤔 Quel Fichier Lire?

| Type Tâche | Fichier | Exemples |
|------------|---------|----------|
| **Ajustement UI simple** | **QUICK_START** ✅ | Modifier label bouton, couleur, taille, espacement |
| **Bugfix trivial** | **QUICK_START** ✅ | Typo, condition if manquante, import oublié |
| **Feature complète** | [CLAUDE.md](CLAUDE.md) | Nouvelle fonctionnalité, nouveau endpoint, nouvelle UI |
| **Bug complexe** | [CLAUDE.md](CLAUDE.md) | Auth broken, routing broken, DB fail, API timeout |
| **Zone à risque** | [CLAUDE.md](CLAUDE.md) | Auth, Router, DB, Infra, Migrations |
| **Maintenance** | [CLAUDE.md](CLAUDE.md) | Refactoring, migration, tech debt, architecture |

**Règle d'or**: Si hésitation → Lis **[CLAUDE.md](CLAUDE.md)**.

---

## 🎯 Projet: Facteur

**Quoi**: App mobile digest quotidien (5 articles, "moment de fermeture")
**Stack**: Flutter + FastAPI + PostgreSQL (Supabase) + Railway
**Phase**: Post-MVP v1.0.1, Epic 10 (Digest Central) en cours

---

## ⚡ Workflow Simplifié (Petits Ajustements)

### 1. Setup Worktree (si modif code)

```bash
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur
git checkout main && git pull origin main
git checkout -b fix/<nom>  # Ex: fix/digest-button-label
git worktree add ../fix/<nom> fix/<nom>
cd ../fix/<nom>

# Vérif isolation
./.claude-hooks/check-worktree-isolation.sh
```

**Skip worktree si**: Doc-only changes (README, comments, stories)

### 2. Localise Code

**Mobile** (`apps/mobile/lib/`):
- Features: `features/{feature}/screens/`, `widgets/`, `providers/`
- Shared: `widgets/`, `models/`, `core/`

**Backend** (`packages/api/app/`):
- Routers: `routers/{domain}.py`
- Services: `services/{domain}_service.py`
- Models: `models/{entity}.py`

**Aide**: [Navigation Matrix - Codebase Maps](docs/agent-brain/navigation-matrix.md#mobile-feature-map)

### 3. Fix + Test

**Mobile**:
```bash
cd apps/mobile
flutter test && flutter analyze
# Si modif Freezed/Riverpod:
dart run build_runner build --delete-conflicting-outputs
```

**Backend**:
```bash
cd packages/api && source venv/bin/activate
pytest -v
```

### 4. Commit

```bash
git add <fichiers>
git commit -m "fix: <description courte>

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

### 5. Cleanup (après merge)

```bash
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur
git worktree remove ../fix/<nom>
```

---

## 🛡️ Guardrails Critiques (Quick Ref)

| # | Pattern | Quick Fix |
|---|---------|-----------|
| 1 | **Python Type Hints** | `list[]` (PAS `List[]` from typing) |
| 2 | **Build Runner** | Après modif Freezed/Riverpod → `dart run build_runner build` |
| 3 | **Async Partout** | Tout I/O doit être `async`/`await` (DB, HTTP, file) |

**Détails complets**: [Safety Guardrails](docs/agent-brain/safety-guardrails.md)

---

## 🔗 Références Rapides

**Documentation**:
- [CLAUDE.md](CLAUDE.md) - Protocol complet (tâches complexes)
- [Agent Brain README](docs/agent-brain/README.md) - Navigation détaillée
- [Navigation Matrix](docs/agent-brain/navigation-matrix.md) - Workflows + Codebase Maps

**BMAD Agents**:
- [Dev Agent](.bmad-core/agents/dev.md) - Full-stack developer
- [QA Agent](.bmad-core/agents/qa.md) - Quality assurance

**Hooks**:
- `.claude-hooks/check-worktree-isolation.sh` - Vérifie worktree
- `.claude-hooks/pre-code-change.sh` - Vérifie Story/Bug Doc (tâches complexes)

---

## 🚦 Quand Escalader vers CLAUDE.md

**Escalade IMMÉDIATE si**:
- Modif >10 lignes de code
- Nouvelle feature (UI, endpoint, service)
- Bug affecte Auth, Router, DB, Infra
- Modification de migration Alembic
- Besoin de Story/Bug Doc pour traçabilité

**Workflow CLAUDE.md inclut**:
- Identification Agent BMAD (@dev, @po, @architect, @qa)
- Cycle M.A.D.A complet (Measure → Decide → Act → Verify)
- Story/Bug Doc OBLIGATOIRE
- Hooks de sécurité complets
- Safety Protocols pour zones à risque

---

*Dernière MAJ: 2026-02-14*
*Pour tâches complexes, suis [CLAUDE.md](CLAUDE.md) intégralement.*
