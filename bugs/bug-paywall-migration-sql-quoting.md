# Bug: SQL Quoting Error in Paywall Migration DEFAULT Clause

**Status**: 🟢 RESOLVED
**Severity**: CRITICAL (migration fails → deployment blocked)
**Reported**: 2026-02-15
**Related Story**: [4.7b.paywall-filtering.story.md](../stories/evolutions/4.7b.paywall-filtering.story.md)

---

## 🔍 Problem Statement

La migration Alembic `q1r2s3t4u5v6` crashe au déploiement. Le `ALTER TABLE sources ADD COLUMN paywall_config JSONB DEFAULT '...'` produit une erreur de syntaxe SQL.

### Error Signature
```
psycopg2.errors.SyntaxError: syntax error at or near "{"
LINE 1: ... paywall_config JSONB DEFAULT ''''{"keywords":[],...
```

### Impact
- Déploiement Railway bloqué (migration exécutée avant uvicorn)
- Toute la feature paywall inopérante tant que migration échoue
- Aucun rollback nécessaire (la migration n'a jamais réussi)

---

## 🎯 Root Cause

### Double-escaping des single quotes

Le wrapper `_execute_with_retry()` fait `sql.replace("'", "''")` pour injecter le SQL dans un bloc `EXECUTE '...'` PL/pgSQL.

Le SQL original contenait :
```python
"DEFAULT ''{"
"\"keywords\":[],"
"\"url_patterns\":[],"
"\"min_content_length\":null"
"}''::jsonb"
```

Les `''` dans le Python string → après escaping → `''''` dans le SQL final.

**Résultat** : PostgreSQL voit `DEFAULT ''''{"keywords"...}''''::jsonb` — une chaîne vide `''` suivie d'un identifiant invalide `{keywords...}`.

---

## ✅ Solution

### Approche: Supprimer le DEFAULT JSONB littéral

La colonne `paywall_config` n'a pas besoin de DEFAULT. `NULL` signifie "utiliser `DEFAULT_PAYWALL_CONFIG`" dans `PaywallDetector`. Seules les sources avec une config spécifique (seeded manuellement) ont une valeur non-NULL.

### Changement

```python
# AVANT (broken)
_execute_with_retry(
    "ALTER TABLE sources "
    "ADD COLUMN IF NOT EXISTS paywall_config JSONB "
    "DEFAULT ''{"
    "\"keywords\":[],"
    "\"url_patterns\":[],"
    "\"min_content_length\":null"
    "}''::jsonb"
)

# APRÈS (fix)
_execute_with_retry(
    "ALTER TABLE sources "
    "ADD COLUMN IF NOT EXISTS paywall_config JSONB DEFAULT NULL"
)
```

**Commit**: `77b8418`
**Branch**: `boujonlaurin-dotcom/paywall-filter`

---

## 📝 Files Modified

- `packages/api/alembic/versions/q1r2s3t4u5v6_add_paywall_detection.py`
  - Lines 57-61: Remplacement DEFAULT JSONB littéral par DEFAULT NULL

---

## 🛡️ Prevention

**Règle pour futures migrations** : Ne jamais passer de SQL contenant des single quotes via `_execute_with_retry()` — le wrapper fait déjà le double-escaping. Si un DEFAULT complexe est nécessaire, utiliser `op.execute()` directement (hors wrapper) ou séparer en ALTER TABLE + UPDATE DEFAULT.

---

*Resolved: 2026-02-15*
*Fix: commit `77b8418`*
