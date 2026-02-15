# Bug: Paywall Filter Excludes All Existing Content (NULL Handling)

**Status**: 🟢 RESOLVED
**Severity**: CRITICAL (feeds vides pour tous les utilisateurs)
**Reported**: 2026-02-15
**Related Story**: [4.7b.paywall-filtering.story.md](../stories/evolutions/4.7b.paywall-filtering.story.md)

---

## 🔍 Problem Statement

Après déploiement de la feature paywall, le filtre `Content.is_paid == False` exclut tous les articles existants du digest et du feed, rendant l'app inutilisable.

### Error Signature
```
# Pas d'erreur HTTP — le filtre retourne simplement 0 résultats
# Digest: 0 articles au lieu de 5
# Feed: liste vide
```

### Impact
- **Tous les utilisateurs** voient un feed/digest vide post-déploiement
- Les articles existants ont `is_paid = NULL` (colonne ajoutée sans backfill immédiat)
- En SQL three-valued logic : `NULL == False` → `NULL` (falsy) → article exclu

---

## 🎯 Root Cause

### SQL three-valued logic sur colonne nullable

PostgreSQL utilise une logique tri-valuée (TRUE, FALSE, NULL). L'expression `WHERE is_paid = FALSE` n'est TRUE que si la valeur est exactement `FALSE`. Pour les lignes où `is_paid IS NULL`, le résultat est `NULL` (ni TRUE ni FALSE), donc la ligne est exclue.

```sql
-- Ce que le code générait (INCORRECT)
SELECT * FROM contents WHERE is_paid = false;
-- Résultat: exclut les rows NULL → 0 articles existants

-- Ce qu'il faut (CORRECT)
SELECT * FROM contents WHERE is_paid IS NOT TRUE;
-- Résultat: inclut FALSE et NULL → tous les articles non-payants
```

### Occurrences dans le code

3 endroits identiques avec le même bug :

| Fichier | Ligne | Contexte |
|---------|-------|----------|
| `digest_selector.py` | 490 | Query user sources |
| `digest_selector.py` | 581 | Query fallback curated |
| `recommendation_service.py` | 560 | Query feed candidates |

---

## ✅ Solution

### Approche: `is_not(True)` au lieu de `== False`

SQLAlchemy `Content.is_paid.is_not(True)` génère `is_paid IS NOT TRUE` qui matche à la fois `FALSE` et `NULL`.

### Changement

```python
# AVANT (broken — exclut NULL)
if hide_paid_content:
    query = query.where(Content.is_paid == False)

# APRÈS (fix — NULL-safe)
if hide_paid_content:
    query = query.where(Content.is_paid.is_not(True))
```

**Commit**: `439092d`
**Branch**: `boujonlaurin-dotcom/paywall-filter`

---

## 📝 Files Modified

- `packages/api/app/services/digest_selector.py`
  - Line 490: `is_not(True)` sur user sources query
  - Line 581: `is_not(True)` sur fallback curated query

- `packages/api/app/services/recommendation_service.py`
  - Line 560: `is_not(True)` sur feed candidates query

---

## 🛡️ Prevention

**Règle pour futurs filtres booléens** : Ne jamais utiliser `Column == False` sur une colonne nullable. Toujours utiliser `Column.is_not(True)` pour inclure NULL, ou `Column.is_(True)` pour exclure NULL. Ajouter cette vérification dans les code reviews pour toute query sur colonne Boolean nullable.

---

*Resolved: 2026-02-15*
*Fix: commit `439092d`*
