# Maintenance: Isolation des branches Git - Protocole strict

## Status: ACTIF - À suivre pour tous les développements futurs

## Date: 26/01/2026

## Problème identifié

Lors du merge de `fix/personalization-clean` dans `main`, une feature d'une autre branche (AJOUT DE SOURCES VIA FLUX RSS) s'est retrouvée en production. Cela indique un **problème de contamination entre branches**.

## Cause racine

Les branches n'ont pas été correctement isolées avant le merge. Possible causes :
1. Merge accidentel d'une branche dans une autre
2. Commit de fichiers non liés dans une branche de fix
3. Merge de `main` dans une branche de feature avant le merge inverse
4. Stash/commit de changements non liés qui se retrouvent dans le merge

## Protocole strict d'isolation des branches

### 🛑 RÈGLE D'OR : Une branche = Un objectif unique

**AVANT de créer une branche** :
1. Vérifier l'état de `main` : `git status` et `git log --oneline -5`
2. S'assurer que `main` est à jour : `git pull origin main`
3. Créer la branche depuis `main` propre : `git checkout -b fix/feature-name`

### 📋 Checklist AVANT chaque commit

**Avant de `git add`** :
```bash
# 1. Vérifier quels fichiers sont modifiés
git status

# 2. Vérifier le diff de chaque fichier
git diff <fichier>

# 3. S'assurer que TOUS les fichiers modifiés sont liés à l'objectif de la branche
```

**Si un fichier n'est PAS lié à l'objectif** :
- ❌ **NE PAS** l'ajouter au commit
- ✅ Le stasher : `git stash push -m "WIP: non lié à cette branche"`
- ✅ Ou créer une branche séparée pour ce fichier

### 🔍 Vérification AVANT merge dans main

**AVANT de merger une branche dans `main`** :

```bash
# 1. Vérifier que la branche est propre
git checkout fix/feature-name
git status  # Doit être clean (pas de fichiers non commités)

# 2. Lister TOUS les fichiers modifiés dans la branche
git diff main...fix/feature-name --name-only

# 3. Vérifier que CHAQUE fichier est lié à l'objectif de la branche
git diff main...fix/feature-name --stat

# 4. Vérifier l'historique des commits
git log main..fix/feature-name --oneline
```

**Si un fichier ne devrait PAS être là** :
- ❌ **NE PAS merger**
- ✅ Créer une nouvelle branche propre avec uniquement les fichiers corrects
- ✅ Ou utiliser `git cherry-pick` pour sélectionner uniquement les commits pertinents

### 🚨 Protocole de merge sécurisé

**Étape par étape** :

```bash
# 1. S'assurer que main est à jour
git checkout main
git pull origin main

# 2. Vérifier l'état de main (doit être clean)
git status

# 3. Créer une branche de merge pour tester
git checkout -b test-merge-fix/feature-name

# 4. Merger la branche
git merge fix/feature-name --no-ff

# 5. Vérifier le résultat du merge
git diff main...test-merge-fix/feature-name --name-only
# Vérifier que seuls les fichiers attendus sont modifiés

# 6. Si OK, merger dans main
git checkout main
git merge fix/feature-name --no-ff -m "Merge fix/feature-name: description"

# 7. Vérifier une dernière fois
git log --oneline -3
git diff HEAD~1 --name-only
```

### 🔐 Protection contre les merges accidentels

**Utiliser des branches de protection** :

1. **Branche de review** : Créer `fix/feature-name-review` pour review avant merge
2. **Branche de test** : Tester le merge dans une branche séparée avant `main`
3. **Pull Request** : Toujours créer une PR pour review (même si on merge soi-même)

### 📝 Template de commit propre

**Format de message de commit** :
```
fix(scope): description courte

- Détail 1
- Détail 2

Résout le problème X.
Refs: docs/bugs/bug-xxx.md
```

**Vérification** :
- ✅ Un seul objectif par commit
- ✅ Tous les fichiers modifiés sont liés à cet objectif
- ✅ Message clair et descriptif

### 🧹 Nettoyage des branches

**Après merge dans main** :

```bash
# 1. Vérifier que le merge est bien dans main
git checkout main
git log --oneline -3

# 2. Supprimer la branche locale (optionnel)
git branch -d fix/feature-name

# 3. Supprimer la branche distante (optionnel)
git push origin --delete fix/feature-name
```

## Exemple : Workflow correct pour un fix

### ❌ MAUVAIS (ce qui s'est passé)

```bash
# Sur une branche avec des changements non liés
git checkout fix/personalization
git add .  # Ajoute TOUT, y compris des fichiers non liés
git commit -m "fix: personalization"
git push
git checkout main
git merge fix/personalization  # Merge tout, y compris les fichiers non liés
```

### ✅ BON (workflow correct)

```bash
# 1. Partir de main propre
git checkout main
git pull origin main
git status  # Vérifier que c'est clean

# 2. Créer une branche dédiée
git checkout -b fix/personalization-api-failure

# 3. Modifier UNIQUEMENT les fichiers liés au fix
# ... modifications ...

# 4. Vérifier avant de commit
git status
git diff
# S'assurer que seuls les fichiers de personnalisation sont modifiés

# 5. Si d'autres fichiers sont modifiés, les stasher
git stash push -m "WIP: autres changements non liés"

# 6. Commit uniquement les fichiers du fix
git add apps/mobile/lib/features/feed/repositories/personalization_repository.dart
git add packages/api/app/routers/personalization.py
git commit -m "fix(personalization): corrige échecs API mute"

# 7. Vérifier avant merge
git diff main...fix/personalization-api-failure --name-only
# Doit afficher uniquement les 2 fichiers ci-dessus

# 8. Merger dans main
git checkout main
git merge fix/personalization-api-failure --no-ff

# 9. Vérifier après merge
git log --oneline -3
git diff HEAD~1 --name-only
# Vérifier que seuls les fichiers attendus sont dans le merge
```

## Outils de vérification

### Script de vérification (à créer)

```bash
#!/bin/bash
# verify-branch-clean.sh

BRANCH=$1
MAIN_BRANCH=${2:-main}

echo "Vérification de la branche $BRANCH..."

# Vérifier les fichiers modifiés
FILES=$(git diff $MAIN_BRANCH...$BRANCH --name-only)

echo "Fichiers modifiés :"
echo "$FILES"

# Demander confirmation
read -p "Tous ces fichiers sont-ils liés à l'objectif de la branche ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "❌ Arrêt : des fichiers non liés détectés"
    exit 1
fi

echo "✅ Branche propre"
```

## Checklist récapitulative

**AVANT de créer une branche** :
- [ ] `main` est à jour et clean
- [ ] Objectif de la branche est clair et unique

**PENDANT le développement** :
- [ ] Seuls les fichiers liés à l'objectif sont modifiés
- [ ] Les fichiers non liés sont stasher ou dans une autre branche
- [ ] Chaque commit a un objectif unique

**AVANT de merger dans main** :
- [ ] `git diff main...branch --name-only` montre uniquement les fichiers attendus
- [ ] `git log main..branch` montre uniquement les commits liés à l'objectif
- [ ] Test du merge dans une branche de test (optionnel mais recommandé)

**APRÈS le merge** :
- [ ] Vérification que seuls les fichiers attendus sont dans `main`
- [ ] Suppression de la branche (optionnel)

## Références

- Git best practices : https://git-scm.com/book
- Conventional commits : https://www.conventionalcommits.org/
- Git workflow : `.cursorrules` (BMad Method)

## Historique

- **26/01/2026** : Problème identifié - feature RSS mélangée avec fix personnalisation
- **26/01/2026** : Protocole créé pour éviter les mélanges futurs
