## Quoi

PR 5 de la chaîne LLM bias annotation. Enrichit le contrat de
`GET /contents/{id}/perspectives` pour exposer les annotations LLM
(`weight` / `category` / `justification`) quand `semantic_equiv` est
en base, sinon retourne le format spaCy actuel. Ajoute un header de
debug `X-Bias-Annotation-Source: llm|spacy` et expose `language`
sur chaque perspective.

## Pourquoi

Les annotations LLM (`semantic_equiv.target_spans` pondérés + tooltips
de justification) sont produites par le pipeline mergé en PR 4
(#648), mais le contrat API actuel les ignore. Sans cette PR, le
mobile (PR 6) ne peut pas afficher les poids ni les tooltips. Le
champ `language` est requis par la future section « Couverture
étrangère » pour regrouper les perspectives non-FR.

## Changements

- **`Content.language`** : colonne `String(8)` nullable + index +
  migration Alembic `lg01_add_language_to_contents` avec backfill
  heuristique (`detect_language` = `looks_english` puis
  `is_french_source`). Les nouveaux contents sont remplis à
  l'ingestion (`sync_service._save_content`).
- **`Perspective.language`** ajouté au dataclass, propagé depuis
  `Content.language` dans `build_cluster_perspectives`. Les
  perspectives Google News restent `None` (pas de row `Content`).
- **`_attach_highlight_spans`** refactoré pour retourner
  `tuple[dict | None, Literal["llm", "spacy"]]`. Si `semantic_equiv`
  est rempli pour le cluster (filtré par `llm_version` +
  `cluster_signature`), les target_spans LLM sont sérialisés tels
  quels, avec `bias` injecté depuis `bias_stance` pour rétrocompat.
  Sinon → fallback spaCy inchangé.
- **Header `X-Bias-Annotation-Source`** posé via `Response` injecté
  dans la signature FastAPI. Cache hit ré-attache le header via un
  `_perspectives_source_cache` parallèle (sinon le header
  disparaissait silencieusement après la 1ère requête).
- **`detect_language`** factorisé dans
  `app/services/ml/language_filter.py` — single source of truth pour
  l'ingestion ET la migration de backfill.

## Comment ça a été vérifié

- [x] `pytest tests/routers/test_contents_perspectives_highlights.py`
  — 13 OK (9 existants adaptés au tuple + 4 nouveaux : LLM enriched,
  fallback spaCy, signature mismatch, language propagation).
- [x] Suite complète backend : **1242 passed, 1 skipped, 2 xfailed**
  (134 s).
- [x] `alembic heads` → exactement 1 head
  (`lg01_add_language_to_contents`).
- [x] `alembic upgrade --sql` → DDL généré correctement
  (`ALTER TABLE contents ADD COLUMN language VARCHAR(8)` +
  `CREATE INDEX ix_contents_language`).
- [x] `/simplify` passé : 5 fixes appliqués (factoriser
  `detect_language`, bug header cache hit, dédupliquer `alt_tokens`,
  hoister fixtures de tests, type `Literal`).

⚠️ **Round-trip migration live non testable localement** : le
container Postgres test du workspace est dans un état désync (« Can't
locate revision identified by 'b3c4d5e6f7a8' ») hérité d'un autre
workspace. La migration sera testée pour de vrai par le `alembic
upgrade head` du `Dockerfile` Railway au prochain boot.

## Zones à risque

- **Cache header** : nouveau dict `_perspectives_source_cache`
  parallèle invalidé en même temps que `_perspectives_cache`
  (`_perspectives_source_cache.pop` à côté de chaque
  `_perspectives_cache.pop`). À surveiller : si une autre branche
  oublie d'invalider l'un sans l'autre, le header pourrait diverger
  du body.
- **Backfill migration** : tourne dans une seule transaction
  Alembic ; `env.py` désactive le `statement_timeout` via
  `SET LOCAL statement_timeout = '0'`, donc pas de cap théorique.
  Avec ~quelques 100k rows en prod, ça devrait passer en quelques
  minutes. Idempotent (`WHERE language IS NULL`).
- **Rétrocompat client** : confirmée par
  `test_attach_highlight_spans_falls_back_to_spacy_when_no_semantic_equiv` —
  les apps pre-PR-6 reçoivent le format spaCy historique.
- **Stored snapshot path** : `language` est lu via
  `getattr(p, "language", None)`, donc les snapshots déjà sérialisés
  sans le champ tomberont à `null` (PR 6 traite `null` comme FR par
  défaut).

## Dette pré-existante (hors scope)

`tests/services/test_llm_bias_annotation_service.py` ne collecte pas
sur `main` à cause d'un import circulaire via
`app.services.editorial.__init__` → `pipeline` →
`llm_bias_annotation_service`. Vérifié : présent avant cette PR.
À traiter dans une PR follow-up.
