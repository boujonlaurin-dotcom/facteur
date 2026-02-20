# Maintenance : Collisions de révisions Alembic (deploy Railway)

**Date** : 2026-02-20
**Auteur** : BMAD Agent (@dev)
**Type** : Infra / Database / Alembic

---

## Contexte

3 échecs de deploy Railway successifs causés par des problèmes de chaîne Alembic.
Chaque erreur avait une cause racine différente, toutes liées à des collisions
de revision IDs ou des désynchronisations entre l'état DB et les fichiers migration.

---

## Incidents & Causes Racines

### Incident 1 : Duplicate revision ID

**Erreur** : `FAILED: Multiple head revisions are present`
**Cause** : Deux fichiers migration avec le même `revision` ID (`g2h3i4j5k6l7`) :
- `g2h3i4j5k6l7_reactivate_les_echos.py` (existant)
- `g2h3i4j5k6l7_add_format_version_to_daily_digest.py` (nouveau, PR #104)

**Pourquoi** : L'agent a choisi un revision ID manuellement au lieu d'utiliser
`alembic revision --autogenerate` qui génère un ID unique.

**Fix** : Renommer la révision en `h3i4j5k6l7m8`, chaîner après `g2h3i4j5k6l7`.

### Incident 2 : Table alembic_version désynchronisée

**Erreur** : `Requested revision h3i4j5k6l7m8 overlaps with g2h3i4j5k6l7`
**Cause** : Après fix manuel via SQL, la table `alembic_version` contenait DEUX
entrées (parent + enfant) au lieu d'une seule (le head courant).

**Pourquoi** : `INSERT INTO alembic_version` au lieu de `UPDATE`. La table
`alembic_version` ne contient qu'UNE seule ligne (le head actuel).

**Fix** : `DELETE FROM alembic_version WHERE version_num = 'g2h3i4j5k6l7';`

### Incident 3 : Deuxième collision + branchement au milieu de la chaîne

**Erreur** : `Revision a1b2c3d4e5f6 is present more than once` + `Multiple head revisions`
**Cause** : Un autre PR (#106, collections) a introduit :
1. Un fichier avec le même revision ID qu'un existant (`a1b2c3d4e5f6`)
2. Un `down_revision` pointant vers le milieu de la chaîne (`z1a2b3c4d5e6`)
   au lieu du head actuel (`h3i4j5k6l7m8`), créant un fork

**Fix** : Renommer en `i4j5k6l7m8n9`, chaîner après `h3i4j5k6l7m8` (le vrai head).

### Incident 4 : DuplicateTable après re-chaînage

**Erreur** : `relation "collections" already exists`
**Cause** : Les tables avaient été créées manuellement via Supabase SQL Editor
avant que la migration alembic ne soit corrigée. Alembic tentait de les recréer.

**Fix** : `UPDATE alembic_version SET version_num = 'i4j5k6l7m8n9' WHERE version_num = 'h3i4j5k6l7m8';`

---

## Règles pour les agents (OBLIGATOIRES)

### R1 : Toujours utiliser `alembic revision` pour générer les migrations

```bash
cd packages/api && source venv/bin/activate
alembic revision --autogenerate -m "description_courte"
```

**JAMAIS** créer un fichier migration manuellement avec un revision ID inventé.
`alembic revision` garantit un ID unique et un `down_revision` pointant vers le head.

### R2 : Vérifier la chaîne avant commit

```bash
# Vérifier qu'il n'y a qu'un seul head
alembic heads

# Vérifier la chaîne complète (doit être linéaire)
alembic history --verbose | head -20

# Vérifier qu'aucun ID n'est dupliqué
grep -r "^revision" packages/api/alembic/versions/ | sort -t"'" -k2 | uniq -d -f1
```

Si `alembic heads` retourne plus d'un head → il y a un fork à corriger AVANT de push.

### R3 : Ne jamais créer de tables manuellement si une migration existe

Si les tables sont dans un fichier Alembic, elles DOIVENT être créées par Alembic.
Créer manuellement via Supabase SQL Editor désynchronise `alembic_version`.

**Exception** : Si les tables existent déjà (créées par erreur), rattraper avec :
```sql
UPDATE alembic_version SET version_num = '<new_head>' WHERE version_num = '<current>';
```

### R4 : La table `alembic_version` = UNE seule ligne

`alembic_version` contient **uniquement** le head courant. Jamais d'INSERT — toujours UPDATE.

```sql
-- Vérifier l'état
SELECT * FROM alembic_version;

-- Corriger si nécessaire (avancer au head sans exécuter la migration)
UPDATE alembic_version SET version_num = '<target_head>';
```

### R5 : Après merge de PRs avec migrations, vérifier les collisions

Quand plusieurs PRs ajoutent des migrations en parallèle, la deuxième à merger
aura un `down_revision` qui ne pointe plus vers le head (puisque la première PR
a ajouté un maillon). **Toujours** rebaser et mettre à jour `down_revision` après merge.

```bash
# Après merge d'un PR avec migration, sur la branche suivante :
alembic heads  # Doit retourner UN seul head
# Si deux heads → corriger le down_revision du dernier fichier ajouté
```

---

## Diagnostic rapide (aide-mémoire)

| Erreur | Cause probable | Fix |
|--------|---------------|-----|
| `Multiple head revisions` | Fork dans la chaîne (2 migrations pointent le même parent) | Corriger `down_revision` du plus récent |
| `Revision X is present more than once` | Deux fichiers avec le même `revision` ID | Renommer un des deux |
| `Requested revision X overlaps with Y` | `alembic_version` contient plusieurs lignes | `DELETE` les lignes en trop, garder le head |
| `DuplicateTable: relation X already exists` | Table créée manuellement, migration pas stampée | `UPDATE alembic_version SET version_num = '<head>'` |
| `Can't locate revision` | `down_revision` pointe vers un ID qui n'existe pas | Vérifier les fichiers, corriger la référence |

---

## Fichiers impactés (session du 20/02)

| Fichier | Action |
|---------|--------|
| `alembic/versions/h3i4j5k6l7m8_add_format_version_to_daily_digest.py` | Créé (remplace g2h3...) |
| `alembic/versions/i4j5k6l7m8n9_add_collections.py` | Créé (remplace a1b2...) |
| `alembic/versions/g2h3i4j5k6l7_add_format_version_to_daily_digest.py` | Supprimé (collision) |
| `alembic/versions/a1b2c3d4e5f6_add_collections.py` | Supprimé (collision) |

## PRs associés

- PR #105 : Fix collision revision format_version
- PR #107 : Fix collision revision collections
