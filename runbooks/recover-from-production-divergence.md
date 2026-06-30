# Runbook : réconcilier `production` quand le release hebdo casse au `--ff-only`

> **À lire avant tout le reste**
>
> `production` ne doit **JAMAIS** recevoir de commit direct. Elle est avancée **uniquement** par le bouton GitHub Actions **« Weekly Production Release »** (`weekly-release.yml`), qui fait un `git merge --ff-only origin/main`. Ce `--ff-only` est un **garde-fou** : il refuse d'avancer si `production` a divergé de `main`.
>
> Si tu te retrouves à suivre ce runbook, le garde-fou a fait son job : **quelqu'un (ou un bot/app) a poussé un commit directement sur `production`**. Le réconcilier n'est que la moitié du travail — **trouve aussi qui/quoi a écrit sur `production` hors du bouton hebdo et bloque-le** (cf. dernière section), sinon ça se reproduira.

> **Symptôme**
>
> Le run « Weekly Production Release » échoue au step *Advance production to main* avec :
> ```
> hint: Diverging branches can't be fast-forwarded
> fatal: Not possible to fast-forward, aborting.
> ```
> (ou, depuis le durcissement de `weekly-release.yml`, un message explicite pointant vers ce runbook).

---

## 1. Confirmer la divergence

```bash
git fetch origin main production
# production doit être un ancêtre de main. Si NO -> divergence confirmée.
git merge-base --is-ancestor origin/production origin/main && echo OK || echo "DIVERGENCE"
# Identifier le(s) commit(s) sur production absent(s) de main :
git log --oneline origin/main..origin/production
```

Note le SHA du commit pirate (ex. `25a79169`) et son auteur (`git log -1 --format='%an / committer %cn' <sha>`).

## 2. Comprendre : il manque l'ascendance, pas le contenu

En général le **contenu** du commit pirate est déjà sur `main` (livré par une PR normale en parallèle) ; il ne manque que le **lien d'ascendance** qui ferait de `production` un ancêtre de `main`.

- ❌ Une **cherry-pick** ne corrige PAS : nouveau SHA ⇒ `production` toujours pas ancêtre de `main`.
- ✅ La bonne réconciliation = un **commit de merge** `merge origin/production` dans `main`, à **arbre identique à `main`** (zéro changement de contenu).

## 3. Construire le merge commit (arbre identique à main)

```bash
git checkout -b reconcile-production-divergence origin/main
git merge --no-ff --no-commit origin/production
# Résoudre tout conflit en gardant la version de main (le contenu pirate y est déjà).
# Ex. doublon de binding réintroduit par l'auto-merge :
git checkout origin/main -- <fichier-en-conflit>
# VÉRIFIER que l'arbre est byte-identique à main (doit être VIDE) :
git diff --stat origin/main          # -> aucune ligne
git commit -m "Merge production into main — relink hotfix ancestry (ff-only fix)"
# VÉRIFIER l'ascendance dans les deux sens :
git merge-base --is-ancestor <sha-pirate> HEAD && echo "prod ancêtre OK"
git merge-base --is-ancestor origin/main HEAD && echo "main peut ff vers ce commit OK"
```

## 4. Faire atterrir le merge commit sur `main` — **SANS squash**

> ⚠️ **Piège n°1.** Le bouton de merge GitHub du repo squashe par défaut. Un **squash/rebase crée un nouveau SHA et re-casse l'ascendance** : `production` ne redevient pas ancêtre de `main`, et le `--ff-only` échoue encore. (C'est arrivé 2× lors de l'incident du 2026-06-30.)

Deux options :
- **PR** mergée strictement avec **« Create a merge commit »** (pas squash, pas rebase).
- **Push direct** (le plus sûr, `main` n'a pas de garde anti-commit-direct) :
  ```bash
  git push origin <sha-du-merge-commit>:main
  ```

Vérifier : `git merge-base --is-ancestor <sha-pirate> origin/main` ⇒ **YES**.

## 5. Relancer le release hebdo — et le piège du push merge-commit

Relance « Weekly Production Release ». Le `--ff-only` passe maintenant. Mais :

> ⚠️ **Piège n°2.** Le `git push origin production` du workflow peut être refusé :
> ```
> remote: fatal error in commit_refs
> ! [remote rejected]   production -> production (failure)
> ```
> C'est un **quirk plateforme** : le `GITHUB_TOKEN` Actions refuse de pousser un **merge commit** en tête de `production`, alors qu'un push **humain/PAT** du *même* ref-update passe. Vérifiable : `git push --dry-run origin <main_sha>:production` est clean.

**Contournement** : pousser le fast-forward sur `production` **à la main**, puis relancer le hebdo :
```bash
git push origin <main_sha>:production   # = avancement que le bouton hebdo tente
```
> ⚠️ Ce push **déclenche le deploy Railway prod** (deploy-on-merge) immédiatement.

Au relancement, le step *Advance production to main* devient « Already up to date », le push est un no-op (plus de merge commit à pousser ⇒ plus d'erreur `commit_refs`), et le build APK + release GitHub + smoke prod s'enchaînent.

> **Ne PAS « corriger » en passant le push hebdo à un PAT** : `promote-to-production.yml` (Production Smoke Tests) écoute `push: [production]` et le hebdo compte sur le `GITHUB_TOKEN` pour NE PAS le re-déclencher. Un PAT ré-armerait ce smoke en double.

## 6. Cause racine : empêcher les écritures directes sur `production`

Réconcilier n'est qu'un sparadrap. La vraie cause = une écriture directe sur `production`. À traiter :

- Identifier l'auteur (UI/API GitHub, app comme `railway-app[bot]`, humain).
- Mettre un **ruleset GitHub sur `production`** interdisant les écritures directes, **avec bypass pour le seul push Actions du hebdo** (`github-actions[bot]`/GITHUB_TOKEN) — sinon le ruleset bloque le bouton hebdo lui-même. Valider après coup : `git push --dry-run origin <main_sha>:production` en tant que bot reste OK ; une écriture humaine est refusée.

## 7. Nettoyage

```bash
git push origin --delete reconcile-production-divergence   # branche temporaire
git worktree remove <chemin> --force ; git worktree prune   # si worktree temporaire
```
