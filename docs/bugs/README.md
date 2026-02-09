# Bugs Tracker - Facteur

Ce dossier contient la documentation des bugs identifiés et leur statut.

## Structure

- **Racine** : Bugs actifs/en cours d'investigation
- **`resolved/`** : Bugs corrigés et archivés

## Format des fichiers

Les fichiers de bug suivent le format : `bug-{description-courte}.md`

### Template

```markdown
# Bug: [Titre court]

## Statut
- [ ] En cours d'investigation
- [ ] En cours de correction  
- [x] Corrigé (date: YYYY-MM-DD)

## Sévérité
- 🔴 Critique
- 🟠 Haute
- 🟡 Moyenne
- 🟢 Faible

## Description
[Description du problème]

## Étapes de reproduction
1. ...
2. ...

## Cause racine
[Analyse technique]

## Solution
[Comment ça a été corrigé]

## Fichiers concernés
- `path/to/file.dart`

## Notes
[Informations complémentaires]
```

## Bugs récents

### 2026-02-09 - Auth Login Failure (RÉSOLU)
**Fichier**: Voir `resolved/bug-auth-login-failure.md`

- **Problème**: Connexion impossible sur web/Android, fonctionnait en local
- **Cause**: Secret SUPABASE_URL contenait l'URL du dashboard au lieu de l'URL API
- **Solution**: Auto-correction côté code + correction du secret GitHub
- **PR**: #27

---

*Dernière mise à jour: 2026-02-09*
