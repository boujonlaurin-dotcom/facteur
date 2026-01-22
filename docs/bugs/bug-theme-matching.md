# Bug: Matching Thème Cassé (Recommandations Aléatoires)

**Date de découverte** : 19/01/2026  
**Sévérité** : 🔥 CRITICAL  
**Status** : To Do  
**Stories impactées** : `4.1.feed-algorithme.md`

---

## Problème

Le matching thème actuel **ne fonctionne jamais** car :
- `Source.theme` contient des **labels lisibles** (ex: `"Tech & Futur"`, `"Société & Climat"`)
- `UserInterest.interest_slug` contient des **slugs normalisés** (ex: `"tech"`, `"society"`)

Le check `if content.source.theme in context.user_interests` dans `CoreLayer.score()` ne matche **JAMAIS** → Le bonus +70 pts n'est jamais appliqué.

**Impact** : Les recommandations sont quasi-aléatoires, ignorant complètement les préférences user.

## Cause Racine

Désalignement entre la taxonomie des sources (labels français) et la taxonomie utilisateur (slugs).

## Solution

### Option retenue : Single Taxonomy (Data Alignment)

Au lieu de complexifier le code avec un mapper, on aligne les données sources sur le standard interne (Slugs).

1. **Mise à jour `sources_master.csv`** : Remplacement des labels ("Tech & Futur") par les slugs ("tech").
2. **Ré-import** : `import_sources.py` met à jour la base.
3. **Simplification Code** : `CoreLayer` fait une comparaison directe robustifiée (`slug == slug`).

**Avantages** : 
- Plus de "Magic Strings" dans le code.
- Plus de maintenance de double liste.
- Performance (comparaison string simple).

## Fichiers impactés

- `sources/sources_master.csv`
- `packages/api/app/services/recommendation/layers/core.py`
- `packages/api/scripts/import_sources.py`

## Vérification

```python
# scripts/validate_fix_matching.py
# Simuler un user avec interests = ["tech", "society"]
# Vérifier qu'au moins 60% des articles de sources correspondantes reçoivent le bonus +70
```

## Historique

| Date | Action | Auteur |
|------|--------|--------|
| 19/01/2026 | Découverte et documentation | Antigravity |
