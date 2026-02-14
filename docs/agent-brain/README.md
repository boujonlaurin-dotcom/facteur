# Agent Brain - Documentation Navigable

**Système de navigation intelligente pour agents AI.**

---

## 🎯 Philosophie

L'ancien `CLAUDE.md` (400+ lignes) était un "knowledge dump" qui noyait les directives critiques dans le contexte technique. L'Agent Brain sépare:

1. **Protocole Core** (`CLAUDE.md` racine, ≤ 100 lignes) - Règles non-négociables
2. **Navigation Contextuelle** (ce dossier) - Où aller selon le type de tâche
3. **Docs de Référence** (`docs/` racine) - PRD, architecture, stories, bugs

---

## 📂 Structure

```
/CLAUDE.md (racine) ← Protocole core uniquement
/docs/agent-brain/
  ├── README.md (ce fichier) ← Orientation
  ├── navigation-matrix.md ← Matrice: TYPE TÂCHE → DOCS → CODEBASE
  ├── safety-protocols.md ← Danger zones (Auth, Router, DB, Infra)
  └── tech-guardrails.md ← Battle-tested patterns (Python, Supabase, Flutter)
```

---

## 🗺️ Comment Naviguer

### 1. Lis TOUJOURS `CLAUDE.md` (racine) en premier
- Protocole M.A.D.A (Measure → Decide → Act → Verify)
- Règles non-négociables (worktree isolation, pas de code avant plan)
- Matrice de navigation rapide

### 2. Identifie ton type de tâche

| Type | Lis ensuite |
|------|-------------|
| **Feature/Evolution** | [Navigation Matrix](navigation-matrix.md#1-feature--evolution) |
| **Bug Fix** | [Navigation Matrix](navigation-matrix.md#2-bug-fix) |
| **Maintenance/Refactoring** | [Navigation Matrix](navigation-matrix.md#3-maintenance--refactoring) |

### 3. Zones à risque élevé

**AVANT toute modif sur Auth/Router/DB/Infra**, lis:
- [Safety Protocols](safety-protocols.md)

**Sections critiques**:
- [Worktree Isolation](safety-protocols.md#worktree-isolation-obligatoire) (OBLIGATOIRE pour tous)
- [Auth / Security](safety-protocols.md#auth--security) (JWT, tokens, guards)
- [Router / Core Mobile](safety-protocols.md#router--core-mobile) (Navigation, redirects)
- [Infra / Database](safety-protocols.md#infra--database) (Migrations, Docker)

### 4. Battle-Tested Patterns

**Pour éviter bugs déjà résolus**, lis:
- [Tech Guardrails](tech-guardrails.md)

**Top 3 Guardrails** (lire en priorité):
1. [Python Type Hints](tech-guardrails.md#garde-fou-1-type-hints-python-312) (`list[]` pas `List[]`)
2. [Supabase Stale Token](tech-guardrails.md#garde-fou-4-stale-token-email-confirmation) (email confirmation bug)
3. [Migration Lock Timeout](tech-guardrails.md#garde-fou-7-migration-lock-timeout-supabase-pgbouncer) (Alembic + Supabase)

---

## 🧭 Workflows Courants

### Cas 1: Feature Mobile + Backend

```
1. CLAUDE.md → Identifie type: Feature
2. Navigation Matrix → Feature workflow:
   a. PRD (contexte business)
   b. Architecture + Front-end Spec (specs tech)
   c. Mobile Map + Backend Map (codebase)
3. Crée Story: docs/stories/core/{epic}.{story}.{nom}.md
4. Implémente (voir Navigation Matrix pour chemins exacts)
5. Tech Guardrails → Vérifie patterns (type hints, async, etc.)
6. Safety Protocols → Si zone à risque (auth, router, db)
7. Crée script: docs/qa/scripts/verify_<tache>.sh
```

### Cas 2: Bug Fix

```
1. CLAUDE.md → Identifie type: Bug
2. Navigation Matrix → Bug workflow:
   a. Bug Template (repro steps)
   b. Retrospectives (patterns similaires)
   c. Workflows Map (zone concernée)
3. Tech Guardrails → Vérifie si pattern connu
4. Safety Protocols → Si danger zone (double vérif)
5. Crée docs/bugs/bug-<nom>.md
6. Fix minimal
7. Regression prevention: verify_<bug>.sh
```

### Cas 3: Maintenance / Refactoring

```
1. CLAUDE.md → Identifie type: Maintenance
2. Navigation Matrix → Maintenance workflow:
   a. Maintenance docs (état actuel)
   b. Architecture (impact analysis)
   c. Safety Protocols (danger zones)
3. Impact analysis complet
4. Plan de rollback AVANT modif
5. Migration en étapes (si breaking changes)
6. docs/maintenance/maintenance-<nom>.md
```

---

## 🛡️ Règles d'Or (Rappel)

Ces règles sont dans `CLAUDE.md` racine, mais répétées ici pour visibilité:

1. **Worktree isolation**: Un agent = un worktree = une branche
2. **M.A.D.A strict**: Measure → Decide (notify_user, STOP) → Act → Verify
3. **Pas de code avant plan validé**: `implementation_plan.md` + approbation user
4. **One-liner proof**: Toute tâche DONE = script de vérification exécutable
5. **Git propre**: Un sujet = un commit, pas de mélange mobile/API/docs
6. **Safety first**: Zones à risque (Auth/Router/DB/Infra) = double vérification

---

## 📚 Index Rapide

### Docs de Référence (hors Agent Brain)

| Doc | Quand le lire |
|-----|---------------|
| [PRD](../prd.md) | Feature: contexte business, user stories |
| [Architecture](../architecture.md) | Specs techniques, data models, APIs |
| [Front-end Spec](../front-end-spec.md) | Mobile UI/UX, design system |
| [Stories](../stories/README.md) | Template story, conventions |
| [Bugs](../bugs/README.md) | Template bug, catégories |
| [QA Scripts](../qa/scripts/) | Inspiration pour verify_*.sh |
| [Retrospectives](../) | `retrospective-*.md` → Patterns bugs |
| [Handoffs](../handoffs/) | Transfert connaissance inter-agents |
| [Maintenance](../maintenance/) | Tech debt, status bypasses |

### BMAD Framework

| Doc | Quand le lire |
|-----|---------------|
| [BMAD User Guide](../../.bmad-core/user-guide.md) | Méthodologie complète |
| [Agent Profiles](../../.bmad-core/agents/) | Rôles: dev, pm, po, architect, qa |
| [Checklists](../../.bmad-core/checklists/) | Story DOD, PM, architect gates |
| [Templates](../../.bmad-core/templates/) | PRD, architecture, front-end YAML |

---

## 🔄 Maintenance de l'Agent Brain

**Quand mettre à jour ces fichiers**:

1. **Navigation Matrix**: Nouveau type de tâche, nouveau workflow
2. **Safety Protocols**: Nouveau bug en production dans danger zone
3. **Tech Guardrails**: Pattern récurrent découvert (3+ occurrences)

**Qui met à jour**:
- Human (Laurin) après retrospective
- Agents si découverte de pattern critique (avec approbation)

**Versionning**:
- Date "Dernière MAJ" en bas de chaque fichier
- Changelog implicite via Git history

---

*Dernière MAJ: 2026-02-14*
*Créé par: Human (Laurin) + Claude (agent exploration + structuration)*
