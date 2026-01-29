# Bug: Matching Thème Cassé (Recommandations Aléatoires)

**Date de découverte** : 19/01/2026  
**Date de résolution** : 29/01/2026  
**Sévérité** : 🔥 CRITICAL  
**Status** : ✅ RÉSOLU  
**Stories impactées** : `4.1.feed-algorithme.md`, `4.2.reco-engine-v3`

---

## ✅ Résolution

**Fix implémenté par** : BMAD Agent  
**Story** : 4.2-US-1 Fix Theme Matching Bug

### Solution appliquée

1. **Simplification CoreLayer** : Retrait de la double normalisation inutile
2. **Migration Alembic** : Conversion des labels FR vers slugs (si présents en DB)
3. **Tests unitaires** : 8 tests passant
4. **Script de vérification** : One-liner disponible

### Commande de vérification

```bash
./docs/qa/scripts/verify_theme_fix.sh
```

**Résultat** : ✅ 8 passed

---

## Problème (Archivé)

Le matching thème actuel **ne fonctionnait jamais** car :
- `Source.theme` contenait des **labels lisibles** (ex: `"Tech & Futur"`, `"Société & Climat"`)
- `UserInterest.interest_slug` contenait des **slugs normalisés** (ex: `"tech"`, `"society"`)

Le check `if content.source.theme in context.user_interests` dans `CoreLayer.score()` ne matche **JAMAIS** → Le bonus +70 pts n'était jamais appliqué.

**Impact** : Les recommandations étaient quasi-aléatoires, ignorant complètement les préférences user.

## Cause Racine

Désalignement entre la taxonomie des sources (labels français) et la taxonomie utilisateur (slugs).

## Solution Implémentée

### Option retenue : Single Taxonomy (Data Alignment)

Au lieu de complexifier le code avec un mapper, on a simplifié le code pour faire une comparaison directe (`slug == slug`).

**Avantages** : 
- Plus de "Magic Strings" dans le code.
- Plus de maintenance de double liste.
- Performance (comparaison string simple).
- Code plus lisible et maintenable.

## Fichiers modifiés

- ✅ `packages/api/app/services/recommendation/layers/core.py` - Simplification du matching
- ✅ `packages/api/alembic/versions/z1a2b3c4d5e6_fix_theme_taxonomy.py` - Migration
- ✅ `packages/api/tests/recommendation/test_core_layer.py` - Tests unitaires
- ✅ `docs/qa/scripts/verify_theme_fix.sh` - Script de vérification

## Historique

| Date | Action | Auteur |
|------|--------|--------|
| 19/01/2026 | Découverte et documentation | Antigravity |
| 29/01/2026 | Fix implémenté et tests passants | BMAD Agent |
