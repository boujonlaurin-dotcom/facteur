# Claude Agent Hooks

**Hooks de sécurité pour contraindre les agents à suivre le protocole.**

---

## 🎯 Objectif

Ces hooks sont des **garde-fous automatiques** qui bloquent les agents s'ils dévient du protocole BMAD/Agent Brain.

---

## 📋 Hooks Disponibles

### 1. `check-worktree-isolation.sh`

**Quand l'exécuter**: EN TOUT PREMIER, avant toute action.

**But**: Vérifie que l'agent travaille dans un worktree isolé (pas le repo principal).

**Bloque si**:
- Agent travaille dans le repo principal
- Git dir = `.git` (pas `.git/worktrees/...`)

**Usage**:
```bash
./.claude-hooks/check-worktree-isolation.sh
```

**Résultat attendu**:
```
✅ Worktree Isolation: OK
   Worktree: /Users/laurinboujon/Desktop/Projects/Work Projects/dev-digest-share
   Git dir: /Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/.git/worktrees/dev-digest-share
```

---

### 2. `pre-code-change.sh`

**Quand l'exécuter**: AVANT toute modification de code (phase Act du M.A.D.A).

**But**: Vérifie qu'une Story/Bug Doc existe selon le type de branche.

**Bloque si**:
- Branche = `main` (modification directe interdite)
- Type `feature/*` ET aucune story dans `docs/stories/`
- Type `fix/*` ET aucune bug doc dans `docs/bugs/`

**Warning si**:
- Type `maintenance/*` ET aucune doc dans `docs/maintenance/` (pas blocant)

**Usage**:
```bash
./.claude-hooks/pre-code-change.sh
```

**Résultat attendu**:
```
✅ User Story détectée (3 fichier(s))
✅ Pre-Code-Change Hook: PASSED
```

---

## 🔗 Intégration dans CLAUDE.md

Ces hooks sont référencés dans `CLAUDE.md` à la section **Cycle M.A.D.A**:

| Phase | Actions | **Hooks OBLIGATOIRES** | STOP Points |
|-------|---------|------------------------|-------------|
| **MEASURE** | Setup worktree | `.claude-hooks/check-worktree-isolation.sh` | - |
| **ACT** | Avant modif code | `.claude-hooks/pre-code-change.sh` | - |

---

## 🧪 Test des Hooks

### Scénario 1: Worktree Isolation OK

```bash
# Setup worktree
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur
git checkout -b feature/test-hooks
git worktree add ../feature/test-hooks feature/test-hooks
cd ../feature/test-hooks

# Test hook
./.claude-hooks/check-worktree-isolation.sh
# ✅ Devrait passer
```

### Scénario 2: Worktree Isolation FAIL (repo principal)

```bash
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur

# Test hook dans repo principal
./.claude-hooks/check-worktree-isolation.sh
# ❌ Devrait échouer avec instructions
```

### Scénario 3: Pre-Code-Change OK (story existe)

```bash
# Assure qu'une story existe
ls docs/stories/core/

# Test hook
./.claude-hooks/pre-code-change.sh
# ✅ Devrait passer
```

### Scénario 4: Pre-Code-Change FAIL (pas de story)

```bash
# Supprime temporairement toutes stories
mv docs/stories docs/stories.bak

# Test hook
./.claude-hooks/pre-code-change.sh
# ❌ Devrait échouer

# Restore
mv docs/stories.bak docs/stories
```

---

## 🚀 Roadmap Hooks (Futur)

### Hooks Potentiels

1. **`pre-commit-msg.sh`**: Valide format commit message (un sujet = un commit)
2. **`post-code-change.sh`**: Vérifie que Story/Bug Doc a été MAJ (File List, Changelog)
3. **`pre-verify.sh`**: Vérifie qu'un script `verify_<task>.sh` existe dans `docs/qa/scripts/`
4. **`danger-zone-check.sh`**: Détecte modifications sur Auth/Router/DB/Infra → double vérif

### Intégration Git Hooks (Optionnel)

Actuellement, les hooks sont **manuels** (agents doivent les appeler). Pour automatisation:

```bash
# Créer symlink dans .git/hooks/
ln -s ../../.claude-hooks/pre-code-change.sh .git/hooks/pre-commit
```

**Avantage**: Automatique à chaque `git commit`
**Inconvénient**: Worktree-specific, pas portable

---

## 📝 Convention Naming Hooks

- `check-*`: Vérifications non-bloquantes (warnings)
- `pre-*`: Vérifications bloquantes AVANT action
- `post-*`: Vérifications bloquantes APRÈS action

---

*Dernière MAJ: 2026-02-14*
*Mainteneur: Human (Laurin)*
