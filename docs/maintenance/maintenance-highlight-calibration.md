# Maintenance — Calibration data-driven du highlighting (suite Story 7.4)

> **Date** : 2026-05-19
> **Branche** : `boujonlaurin-dotcom/fix-article-highlight`
> **PR ciblée** : `main`
> **Type** : investigation / outillage (read-only, pipeline non modifiée)
> **Prérequis** : [`maintenance-highlight-cartography.md`](./maintenance-highlight-cartography.md)

## Contexte

La cartographie initiale (30 titres, 5 pseudo-clusters) a rendu visibles
plusieurs catégories d'erreurs (faux positifs sur entités-pivots, verbes
neutres, alias d'entités simples, expressions multi-tokens fragmentées),
mais le volume est trop faible pour en déduire des règles de calibration
défendables. La démarche est donc **inversée** : avant toute modification
de `TitleAnnotationService`, on construit un dataset annoté de référence
et un évaluateur reproductible, puis on pose une **baseline chiffrée**.

> Règle d'or PO : **volume avant règle**. Pas de filtre POS / stopword
> métier inféré à partir de <30 clusters annotés.

## Décision

1. **Pipeline non modifiée dans cette PR.** Livrables : dataset annotable,
   évaluateur, baseline mesurée, journal de calibration. Les ajustements
   chirurgicaux (un paramètre par PR) viennent ensuite.
2. **Pas de Mistral** (phase 2 Story 7.4 reste dormante — décision
   réévaluée après calibration).
3. **Pas de modification UI** dans cette PR.

## Livrables

| Fichier | Rôle |
|---------|------|
| `packages/api/scripts/build_highlight_dataset.py` | Construit le dataset stratifié (≥33 clusters, ≥165 titres) à partir d'un dump brut MCP Supabase. |
| `packages/api/scripts/evaluate_title_annotations.py` | Évaluateur : P/R/F1 token-lemma + span fusionné, catégorisation FP/FN, top-N lemmes, mode `--compare`. |
| `packages/api/tests/scripts/test_evaluate_title_annotations.py` | 12 tests hermétiques (FakeNlp), dont 1 smoke bout-en-bout. |
| `packages/api/tests/scripts/fixtures/toy_dataset.json` | Toy dataset 1 cluster × 2 articles utilisé par le smoke test. |
| `.context/highlight-dataset-<date>.json` | Dataset annotable (annotations vides à remplir). |
| `.context/highlight-baseline-<date>.{md,json}` | Baseline mesurée (iter 0). |
| `.context/highlight-calibration-log.md` | Journal append-only des itérations. |

## Workflow

### 1. Extraction du pool d'articles (MCP Supabase)

Le rôle `claude_analytics_ro` (DATABASE_URL_RO) est filtré par RLS et voit
0 row sur `contents`. Toujours passer par MCP Supabase :

```sql
SELECT c.id, c.title, c.url, c.published_at, c.theme, c.entities, c.language,
       s.name AS source_name, s.bias_stance, c.source_id
FROM contents c
JOIN sources s ON s.id = c.source_id
WHERE c.published_at >= NOW() - INTERVAL '7 days'
  AND c.published_at <= NOW() - INTERVAL '1 hour'
  AND c.language = 'fr'
  AND c.title IS NOT NULL
  AND c.entities IS NOT NULL
  AND array_length(c.entities, 1) >= 2;
```

Le résultat MCP est repackagé en JSON :

```json
{ "generated_at": "...", "articles": [ { "id":"...", "title":"...", ... } ] }
```

et écrit dans `.context/raw-articles-<date>.json` (gitignored).

### 2. Construction du dataset

```bash
cd packages/api && source venv/bin/activate
python scripts/build_highlight_dataset.py \
    --raw .context/raw-articles-2026-05-19.json \
    --out .context/highlight-dataset-2026-05-19.json
```

Filtres appliqués (modifiables en CLI) :

- `--min-size 4` articles par cluster
- `--max-per-cluster 7` (les plus récents conservés)
- `--window-hours 36` (≤ 36 h entre 1er et dernier article)
- `--min-pair-ratio 0.7` (≥ 70 % des paires partagent ≥ 2 entités)
- `--min-shared-entities 2` (entités PERSON/ORG/EVENT)
- Dédup par `source_id` (1 article par source)

Stratification par défaut : `politics` (6) · `international+geopolitics` (6)
· `economy` (5) · `culture` (4) · `society+environment` (5) · `science+tech`
(4). Chaque cluster doit avoir ≥ 2 stances distinctes (≥ 3 pour `politics`
et `international`).

### 3. Annotation

#### 3.1 Conventions d'annotation

Chaque perspective (article ≠ référence du cluster) peut recevoir un
bloc `annotations.<source>` (par défaut `po_synchronous` ou `agent_mirror`) :

```json
{
  "target_spans":  [{"start":29, "end":34, "text":"Paris", "category":"fact"}],
  "exclude_spans": [{"start":0,  "end":6,  "text":"Donald","category":"entity_alias"}],
  "notes": "Paris = seul fait nouveau ; Donald = alias de Trump"
}
```

**Catégories fermées** :

- `target_spans.category` : `editorial_angle`, `fact`,
  `multi_token_expression`, `framing_noun`
- `exclude_spans.category` : `pivot_entity`, `neutral_verb`,
  `entity_alias`, `geographic_alias` (loggé mais hors-scope V1), `noise`

#### 3.2 Phases d'annotation

| Phase | Quoi | Champ JSON |
|-------|------|------------|
| A — gold synchrone PO | 12 clusters (≈ 60-80 titres) annotés en visio avec Laurin. Couvre 2 clusters par thème majeur + 1 par thème mineur. | `po_synchronous` |
| B — miroir agent | Agent annote les ≥ 21 clusters restants en suivant les conventions du gold. | `agent_mirror` |
| C — validation par échantillonnage | 3 clusters tirés au hasard du miroir, diff vs prédictions, PO valide ou corrige. Désaccord token-lemma > 15 % ⇒ re-passe du miroir. | n/a |

### 4. Évaluation

```bash
python scripts/evaluate_title_annotations.py \
    --dataset .context/highlight-dataset-2026-05-19.json \
    --annotator po_synchronous \
    --tag baseline
```

Produit :

- `.context/highlight-baseline-<date>.json` (machine, consommé par `--compare`)
- `.context/highlight-baseline-<date>.md` (lisible humain)

Métriques produites :

- **Token-lemma** : sets de lemmes, P/R/F1 micro.
- **Span fusionné** : intervalles `(start, end)` après fusion des spans
  contigus (gap ≤ 1 char), match exact.
- **FP par catégorie** : croisement avec `exclude_spans` (FP_pivot_entity,
  FP_neutral_verb, FP_entity_alias…).
- **FN par catégorie** : tagué via `target_spans.category`.
- **Top-30 lemmes** FP/FN — base data-driven pour inférer une éventuelle
  whitelist ou un stopword métier *à partir des données*, pas de
  l'intuition.

### 5. Journal de calibration

`.context/highlight-calibration-log.md`, append-only :

```
| Iter | Date | Param modifié | P_tok | R_tok | F1_tok | P_span | R_span | F1_span | ΔF1_tok | Top FP | Top FN | Notes |
| 0    | 2026-05-19 | baseline (état actuel) | … | … | … | … | … | … | — | … | … | PR baseline |
```

Cette PR pose la ligne **Iter 0**. Chaque PR de calibration ajoute une
ligne et une seule (**règle : un paramètre par PR**) en fournissant le
delta vs baseline. Mode `--compare` :

```bash
python scripts/evaluate_title_annotations.py --compare \
    .context/highlight-baseline-2026-05-19.json \
    .context/highlight-after-iter1.json
```

## Tests

```
cd packages/api && pytest tests/scripts/test_evaluate_title_annotations.py -v
cd packages/api && pytest tests/services/test_title_annotation_service.py -v   # régression
cd packages/api && pytest tests/routers/test_contents_perspectives_highlights.py -v
```

12 tests évaluateur (10 unitaires + 2 smoke bout-en-bout) ; 29 tests de
régression sur le service et le router restent verts (vérifié 2026-05-19).

## Pièges

1. `Source.bias_stance` est un `StrEnum` SQLAlchemy ⇒ sérialiser via
   `.value` (cf. `scripts/inspect_title_annotations.py:139`).
2. `Content.entities` est `text[]` de JSON strings ⇒ `json.loads(raw)`
   par élément, pas `c.entities[0]["name"]`.
3. MCP Supabase tronque à ~1 000 rows ⇒ paginer (`OFFSET/LIMIT` ou
   filtre par jour) si le pool dépasse.
4. Match gold vs pred sur **lemma** (pas sur text) — sinon "martèle"
   et "martèlent" ratent.
5. Fusion de spans : `gap ≤ 1 char` côté gold ET pred (cohérence).
6. Ne pas réimplémenter spaCy dans l'évaluateur : appeler
   `get_title_annotation_service()` pour rester aligné sur la pipeline.
7. PR base `main` obligatoire ; `staging` bloqué par hook.
8. **Aucune modif de `TitleAnnotationService` dans cette PR** — la
   calibration commence en PR+1, une variable à la fois.

## Suite (hors-scope de cette PR)

- Phase A d'annotation (séance synchrone PO).
- Phase B (miroir agent) + C (validation).
- PR+1 : `pivot_entity_lemmas` paramètre passé à `diff_spans`.
- PR+2 : alias d'entités simples (substring).
- PR+3+ : selon les top-FP/FN observés dans Iter 0.
