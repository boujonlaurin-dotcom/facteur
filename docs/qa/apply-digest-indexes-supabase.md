# Appliquer les index digest (Supabase SQL Editor)

## Contexte

Le endpoint `/api/digest` timeout (>10s). Ces 4 index optimisent les requêtes.  
À exécuter **un par un** dans l’éditeur SQL Supabase (pas en bloc) : l’éditeur peut timeout, et `CREATE INDEX ... CONCURRENTLY` ne fonctionne pas dans une transaction.

## Méthode

1. Ouvrir **Supabase Dashboard** → ton projet → **SQL Editor**.
2. Pour **chaque** commande ci‑dessous :
   - Coller **une seule** commande dans l’éditeur.
   - Cliquer **Run**.
   - Si timeout : attendre 30 s, puis réessayer la **même** commande.
   - Une fois réussie, passer à la suivante.
3. Après chaque `CREATE INDEX`, tu peux vérifier avec la requête de vérification (voir plus bas).

## Commandes (une à la fois)

### Index 1 – Contents (source_id, published_at)

```sql
CREATE INDEX ix_contents_source_published ON contents (source_id, published_at DESC);
```

### Index 2 – Contents (curated fallback)

```sql
CREATE INDEX ix_contents_curated_published ON contents (published_at DESC, source_id);
```

### Index 3 – UserContentStatus

```sql
CREATE INDEX ix_user_content_status_exclusion ON user_content_status (user_id, content_id, is_hidden, is_saved, status);
```

### Index 4 – Sources.theme

```sql
CREATE INDEX ix_sources_theme ON sources (theme);
```

### Enregistrer la migration

```sql
INSERT INTO alembic_version (version_num) VALUES ('x8y9z0a1b2c3');
```

(Si la ligne existe déjà, tu peux avoir une erreur de contrainte unique ; dans ce cas c’est OK.)

## Vérification

Après les 4 index + l’INSERT, exécuter :

```sql
SELECT indexname FROM pg_indexes WHERE indexname LIKE 'ix_%' ORDER BY indexname;
```

Tu dois voir au moins :

- `ix_contents_curated_published`
- `ix_contents_source_published`
- `ix_sources_theme`
- `ix_user_content_status_exclusion`

## Alternative : script Python (connexion directe)

Si tu as une connexion stable à la base (sans timeout court type pooler) :

```bash
cd packages/api && source venv/bin/activate && python scripts/apply_digest_indexes.py
```

Le script exécute chaque `CREATE INDEX` dans une connexion séparée (autocommit), avec retry 30 s en cas d’erreur.

## Fichiers

- **SQL** : `packages/api/sql/012_digest_performance_indexes.sql`
- **Script** : `packages/api/scripts/apply_digest_indexes.py`
