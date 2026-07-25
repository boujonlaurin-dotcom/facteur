# Maintenance — index trigram `contents.entities` (1er batch « Comparer les angles »)

> Type : Maintenance / perf. Migration : `pt01_contents_entities_trgm`.
> Décision PO (24/07) : **Option A maintenant** (index trigram), Option B (dénorm)
> conditionnelle à la re-mesure post-déploiement.

## Problème

Le carrousel « Comparer les angles » (bas d'article, alias interne *perspectives*)
charge lentement le matin. Le goulot mesuré est le **1er batch DB** — la lecture
`PerspectiveService.search_internal_perspectives` — pas l'enrichissement Google
News (2e temps, en tâche de fond, hors périmètre).

La requête filtre les articles partageant une entité PERSON/ORG via :

```python
func.array_to_string(Content.entities, " ").ilike(f"%{name}%")
```

`array_to_string(entities,' ') ILIKE '%nom%'` transforme la colonne puis fait un
match sous-chaîne (wildcard en tête) → **non-sargable**. Postgres borne la fenêtre
72h via `ix_contents_published_at` puis évalue l'ILIKE **ligne par ligne** sur toute
la fenêtre. Coût **O(articles publiés sur 72h)** → grossit avec l'ingestion.
EXPLAIN prod : ~**1,58 s**, `Rows Removed by Filter: 6953`.

## Correctif livré (Option A) — ⚠️ dévie du plan initial

Le plan supposait un index d'expression **directement** sur
`array_to_string(entities,' ')`, requête inchangée. **Impossible en l'état** :

- `array_to_string(anyarray, text)` est déclaré **STABLE** (polymorphe), or
  Postgres exige des fonctions **IMMUTABLE** dans une expression d'index
  → `ERROR: functions in index expression must be marked IMMUTABLE`.
  (Validé localement : les deux formes, qualifiée ou non, échouent.)

Correctif minimal, en 3 objets **additifs** :

1. **Wrapper IMMUTABLE** `public.content_entities_text(text[])` =
   `array_to_string($1, ' ')`. Pour du `text[]` la sortie est réellement immutable
   → wrapper légitime (même pattern qu'`immutable_unaccent`).
2. **Index GIN trigram** `ix_contents_entities_trgm` sur
   `content_entities_text(entities)` avec l'opclass **`extensions.gin_trgm_ops`**.
   Le baseline crée `pg_trgm WITH SCHEMA extensions` et `extensions` **n'est pas**
   dans le `search_path` des connexions → l'opclass **doit** être qualifiée
   (`gin_trgm_ops` nu ⇒ `operator class does not exist`).
3. **Requête** de `search_internal_perspectives` bascule sur le wrapper
   (`func.content_entities_text(Content.entities).ilike(...)`) — sinon l'expression
   ne matche pas l'index et le planner reste en seq scan.

L'index est aussi déclaré dans `Content.__table_args__` (via `text()` portant
l'opclass) pour cohérence ORM↔schéma ; l'autogenerate « assume equal and skips »
(index d'expression non réfléchissable) → il ne proposera pas de le drop.

## Preuve (EXPLAIN, dataset local représentatif : 7000 lignes / fenêtre 72h)

| Forme de requête | Plan | Coût |
|---|---|---|
| `array_to_string(...) ILIKE` (avant) | Seq Scan, `Rows Removed: 7000` | ~43 ms (128 ms au 1er run) |
| `content_entities_text(...) ILIKE` (après) | **Bitmap Index Scan `ix_contents_entities_trgm`**, `Heap Blocks: 9` | sub-ms |

Sur entité **discriminante** (cas normal) → bascule trigram. Sur terme très
fréquent, le planner peut retomber sur `ix_contents_published_at` — acceptable,
jamais pire que l'existant.

## Fichiers

- `packages/api/alembic/versions/pt01_contents_entities_trgm.py` (nouveau) —
  fonction + index (`CREATE INDEX CONCURRENTLY` dans `autocommit_block`, `IF NOT
  EXISTS`, idempotent ; downgrade drop index puis fonction).
- `packages/api/app/services/perspective_service.py` — requête → wrapper.
- `packages/api/app/models/content.py` — déclaration de l'index dans `__table_args__`.
- `packages/api/tests/conftest.py` — pré-crée la fonction + `pg_trgm` avant
  `Base.metadata.create_all` (même logique que l'ENUM `interest_state` déjà présent ;
  sinon `create_all` lève `UndefinedFunction` au CREATE INDEX).

## Rollout (expand-contract, DB partagée staging↔prod)

Tout est **additif** : le backend prod (ancien code `production`, requête
`array_to_string` inchangée) ignore fonction et index jusqu'au passage hebdo.

**Recommandé — build hors-bande avant merge (accès Supabase requis) :**

```sql
-- 1) la fonction D'ABORD (l'index en dépend)
CREATE OR REPLACE FUNCTION public.content_entities_text(text[])
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT array_to_string($1, ' ') $$;
-- 2) l'index CONCURRENTLY (~30-90 s sur 72k lignes, non bloquant pour l'ingestion)
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_contents_entities_trgm
ON public.contents
USING gin (public.content_entities_text(entities) extensions.gin_trgm_ops);
```

Ensuite la migration `IF NOT EXISTS` est un no-op rapide au boot des deux services.
Si le build hors-bande est **omis**, la migration bâtit l'index CONCURRENTLY au boot
staging (délai ~30-90 s sur ce boot, sans bloquer les écritures).

## Vérifié

- `alembic upgrade head` depuis une DB vide (= CI `alembic-smoke`) : baseline →
  pt01, index `valid`/`ready`, fonction `IMMUTABLE`+`PARALLEL SAFE`. Exactement 1 head.
- `downgrade -1` retire index + fonction ; re-`upgrade head` idempotent.
- EXPLAIN : bascule sur `ix_contents_entities_trgm` (cf. tableau).
- `pytest tests/*perspective*` : 35 passés (facteur_test + DB isolée). Suite
  perspectives/coverage/entities : 151 passés.

## Suivi

- **Re-mesurer en prod** (`timings_ms.cluster_internal_db` sur ouvertures
  live-path ; viser 1er batch < 100 ms). Décide si l'**Option B** (dénormaliser
  `entity_names text[]` + GIN array + overlap sargable, migration + backfill 72k +
  écriture au point de classif + expand-contract 2 cycles) est nécessaire. Si B est
  livrée, l'index trigram devient inutile (drop en cycle contract).
- Hors périmètre : absence de cache client (re-fetch à chaque ré-open,
  `content_detail_screen.dart`) — à traiter séparément si souhaité.
