# Maintenance — Calibration de la porte de clustering « couverture médiatique »

> **Date** : 2026-06-09
> **Branche** : `boujonlaurin-dotcom/improve-clustering-quality`
> **PR ciblée** : `main`
> **Type** : outillage + 1er réglage data-driven (1 paramètre)
> **Template** : [`maintenance-highlight-calibration.md`](./maintenance-highlight-calibration.md)

## Contexte

L'écran « couverture médiatique / Autres regards » regroupe trop d'articles qui
ne partagent qu'une **entité saillante** (Trump, Macron…) sans parler du **même
événement**. Capture PO : un cluster « Trump » mélange la guerre Iran-Israël,
« Trump hué au NBA » et « Trump et le Sénat ». Conséquence : perte de confiance
+ le « niveau de polarisation » mesure le mauvais objet.

Le clustering est **100 % lexical/entité, zéro sémantique**. La porte vit dans
`packages/api/app/services/perspective_service.py` :

- `_topical_signals()` → `{title_jaccard, shared_topics, shared_entities}`
- `_is_topically_coherent()` accepte un candidat si :
  1. `title_jaccard ≥ 0.30` (`PERSPECTIVE_TITLE_JACCARD_MIN`), **ou**
  2. `shared_entities ≥ 2` (Layer 1 DB), **ou**
  3. `title_jaccard ≥ 0.08` (`PERSPECTIVE_MIN_JACCARD_FLOOR`) **ET**
     `shared_topics ≥ 1` **ET** `shared_entities ≥ 1` ← **la « weak double
     signal », la fuite principale de faux-positifs**.

À l'inverse, le Jaccard de titre seul rate les **paraphrases**
(« guerre au Moyen-Orient » vs « conflit Israël-Iran ») → faux-négatifs.

> Règle d'or PO (cf. mémoire `feedback_calibration_no_overfit`,
> `feedback_highlight_no_brute_rules`) : **mesure avant règle**. On instrumente,
> on chiffre, puis on règle **un seul paramètre** mesuré contre le gold —
> jamais de stoplist / règle métier en dur.

## Décision (validée PO)

1. **Périmètre** : dataset + harness + baseline **ET** un 1er réglage de seuils
   (durcir la branche 3) mesuré contre le gold, dans la même PR.
2. **Surface** : **perspectives uniquement** (la porte de `perspective_service`).
   On ne benche pas `importance_detector`.
3. **Étiquetage** : LLM (Mistral-large) pré-partitionne par événement → **revue
   PO** des `event_id`.
4. **Embeddings** : actés en *next steps*, non implémentés ici.

## Livrables

| Fichier | Rôle |
|---------|------|
| `packages/api/scripts/build_event_dataset.py` | Construit les pools lâches par entité partagée (fenêtre + cap, pas de dédup source). |
| `packages/api/scripts/label_event_dataset.py` | Pré-label LLM cluster-assign (1 prompt/pool) + substrat de revue PO. |
| `packages/api/scripts/evaluate_event_clustering.py` | Harness sur la **porte réelle** : P/R/F1 pairwise, contamination, FP-par-chemin, FN-par-raison, sweep, `--compare`. |
| `packages/api/tests/scripts/test_build_event_dataset.py` | Seeding / fenêtre / stratif. |
| `packages/api/tests/scripts/test_label_event_dataset.py` | Validateur (exactly-once-or-NOISE, jamais d'écrasement revu) + dry-run. |
| `packages/api/tests/scripts/test_evaluate_event_clustering.py` | Fns pures, anti-drift `gate_pair`, agrégation toy (FP planté → `weak_double_signal`). |
| `packages/api/tests/scripts/fixtures/toy_event_dataset.json` | Toy : 1 pool Trump, événements iran(3)/nba(1) + NOISE. |
| `.context/gold-events-*.json\|.md` | Généré, gitignored. |

## Schéma du gold (`dataset_kind: event_membership`)

```json
{
  "schema_version": 1, "dataset_kind": "event_membership", "seed_window_hours": 72,
  "pools": [{
    "pool_key": "trump", "pool_display": "Trump",
    "seed_entity": {"name": "Trump", "type": "PERSON"}, "theme": "international",
    "events": [{"event_id": "iran", "label": "Frappes Iran-Israël", "size": 3}],
    "articles": [{
      "id": "...", "title": "...", "topics": ["geopolitics","middleeast"],
      "entities": ["{\"name\":\"Trump\",\"type\":\"PERSON\"}"],
      "event_id": "iran", "label_source": "llm_pass1",
      "label_reviewed": false, "label_confidence": 0.8, "label_notes": ""
    }]
  }]
}
```

`event_id` = slug stable ; sentinelle `"NOISE"` = article partageant l'entité
mais sans événement multi-articles cohérent (**jamais** « même événement » avec
quoi que ce soit). `topics`/`entities` portés **verbatim** (forme `text[]` de
chaînes JSON, parsées exactement comme `_parse_entity_names`).

## Workflow

### 1. Extraction du pool (MCP Supabase)

`claude_analytics_ro` est RLS-0 ; passer par MCP Supabase. Sélectionner
**`topics` ET `entities`** :

```sql
SELECT c.id, c.title, c.url, c.published_at, c.theme, c.topics, c.entities,
       c.language, s.name AS source_name, s.bias_stance, c.source_id
FROM contents c
JOIN sources s ON s.id = c.source_id
WHERE c.published_at >= NOW() - INTERVAL '72 hours'
  AND c.language = 'fr'
  AND c.title IS NOT NULL
  AND c.entities IS NOT NULL
  AND array_length(c.entities, 1) >= 1;
```

Repackager en `{ "generated_at": "...", "articles": [...] }` →
`.context/raw-articles-<date>.json` (gitignored).

### 2. Construction des pools

```bash
cd packages/api && source venv/bin/activate
python scripts/build_event_dataset.py \
    --raw ../../.context/raw-articles-<date>.json \
    --out ../../.context/gold-events-<date>.json
```

Défauts : `--min-size 6 --max-per-pool 30 --window-hours 72`. **Pas** de dédup
par source ni de filtre « ≥2 entités » (on veut les pools gras qui se scindent
+ les paires intra-événement multi-sources). Stratification par thème comptée
**en pools** (`DEFAULT_QUOTAS`).

### 3. Pré-label LLM + revue PO

```bash
python scripts/label_event_dataset.py \
    --dataset ../../.context/gold-events-<date>.json --mode fill
```

Approche **cluster-assign** (1 prompt/pool, pas O(n²)). Validateur tolérant :
un index assigné **exactement une fois** → son événement ; 0 ou ≥2 fois → NOISE.
`EVENT_LABEL_DRY_RUN=1` → stub déterministe (tests).

**Revue PO** (rubrique d'arbitrage) :

- Un événement = mêmes **acteurs + action + moment**. Annonce vs réaction de
  marché = events distincts si l'angle diffère ; en cas de doute → NOISE.
- Éditer les `event_id` douteux dans le JSON `.context/`, passer
  `label_reviewed: true` **pool par pool**.
- Phases : **A** gold synchrone PO (2-3 pools en visio) · **B** miroir
  (le PO valide le draft LLM) · **C** `--mode blind` re-label des pools revus
  → mesure de l'accord LLM↔PO (`event_id_blind`) comme signal de qualité du gold.

### 4. Baseline (Iter 0) + diagnostic

```bash
python scripts/evaluate_event_clustering.py \
    --dataset ../../.context/gold-events-<date>.json --tag baseline
```

Le harness importe les **vraies** fonctions de la porte (anti-drift garanti par
`test_gate_pair_matches_real_gate`) et rejoue **toutes les paires ordonnées**
seed↔candidat. Métriques :

- Pairwise **P/R/F1** micro **+ macro par pool** (un gros pool ne domine pas le
  micro ; le n est affiché).
- **Contamination par seed** : % d'articles hors-événement admis (moyenne +
  pires offenders « junk-drawers »).
- **FP par chemin d'acceptation** : `strong_jaccard` / `double_entity` /
  `weak_double_signal`. Attendu : majorité des FP en `weak_double_signal`.
- **FN par signal manquant** : `low_jaccard` / `jaccard_below_floor` /
  `no_shared_topic` / `no_shared_entity` → révèle le gap des paraphrases.
- **Couverture des signaux** : fraction `full_signals` (garde-fou si la prod a
  des `entities` nulles, ~17 % — sinon la fuite serait mal attribuée).

> **Hors-périmètre déterministe** : Layer 2/3 (Google News) génère des candidats
> sans topics/entities — on mesure la *porte*, pas la génération de candidats.

### 5. 1er réglage data-driven (Iter 1, même PR)

```bash
python scripts/evaluate_event_clustering.py \
    --dataset ../../.context/gold-events-<date>.json --tag baseline --sweep
```

Le `--sweep` balaie `PERSPECTIVE_MIN_JACCARD_FLOOR ∈ {0.08, 0.12, 0.15, 0.20,
0.25}` + la variante « exiger `shared_entities ≥ 2` partout » et imprime le
tradeoff (P↑ / contamination↓ vs R). Choisir le réglage qui **maximise la
précision sans dégrader le rappel au-delà d'un seuil acceptable** (validé PO).
Vu le cas Cuba/Chagos (Jaccard ≈ 0.09), un floor à ~0.15 rejette ce FP — **à
confirmer par la mesure sur le gold réel**.

**Un seul paramètre** modifié dans `perspective_service.py`, puis re-run :

```bash
python scripts/evaluate_event_clustering.py \
    --dataset ../../.context/gold-events-<date>.json --tag iter1
python scripts/evaluate_event_clustering.py --compare \
    ../../.context/gold-events-baseline-<date>.json \
    ../../.context/gold-events-iter1-<date>.json
```

La fixture Texas existante (`tests/test_perspective_service.py`) doit rester
verte ; ajouter une fixture Trump multi-événements.

## Journal de calibration (append-only — 1 paramètre / PR)

| Iter | Date | Param | P_pair | R_pair | F1_pair | Contam | FP_weak_double | FN_jaccard_floor | ΔF1 | Notes |
|------|------|-------|--------|--------|---------|--------|----------------|------------------|-----|-------|
| 0 | 2026-06-09 | baseline (floor 0.08) | 0.897 | 0.876 | 0.886 | 0.169 | 252 | 360 | — | gold **revu PO** (découpe NOISE/événements validée telle quelle) ; 20 pools / 4906 paires ordonnées |
| 1 | 2026-06-09 | `PERSPECTIVE_MIN_JACCARD_FLOOR` 0.08 → 0.12 | 0.926 | 0.809 | 0.864 | 0.129 | 124 | 628 | −0.023 | arbitrage PO « moins de mauvais clusters » : FP −128 (−36 %), contamination −24 %, rappel −7,6 % |

> **Iter 0** mesuré le 2026-06-09 sur gold **revu PO** (7 pools junk-drawer relus,
> découpe NOISE/événements confirmée sans flip). Diagnostic confirmé sur données
> prod : `weak_double_signal` = 71 % des FP (252/356), `jaccard_below_floor` =
> 83 % des FN (360/436). Le `--sweep` montre que durcir le floor n'est PAS un
> repas gratuit sur données réelles (contrairement au toy) : ↑précision et
> ↓contamination se paient en ↓rappel (des paraphrases intra-événement
> dépendent aussi de la branche faible).
>
> **Iter 1 — floor 0.08 → 0.12 (validé PO).** `weak_double_signal` FP 252 → 124
> (la branche ciblée est bien coupée de moitié), `double_entity` FP **inchangé à
> 92** : le floor ne touche QUE la branche faible — les FP qui partagent ≥2
> entités (ex. Trump *Iran-Israël* ↔ *Pentagone-espionnage*, qui partagent
> Trump + Israël) survivent à **toute** valeur de floor. Le cœur du grief Trump
> reste donc adressable seulement par les embeddings (cf. *Suite*). Pareillement,
> les FN paraphrases (`jaccard_below_floor` 360 → 628) s'aggravent avec le floor
> et ne se règlent pas ici.
>
> | floor | P | R | F1 | Contam | FP | FN |
> |-------|---|---|----|--------|----|----|
> | 0.08 (actuel) | 0.897 | 0.876 | 0.886 | 0.169 | 356 | 436 |
> | 0.12 | 0.926 | 0.809 | 0.864 | 0.129 | 228 | 672 |
> | 0.15 | 0.933 | 0.756 | 0.835 | 0.105 | 192 | 858 |
> | 0.20 | 0.942 | 0.693 | 0.798 | 0.082 | 150 | 1082 |
> | 0.25 | 0.949 | 0.629 | 0.756 | 0.071 | 120 | 1306 |
> | entités≥2 partout | 0.952 | 0.581 | 0.722 | 0.072 | 104 | 1474 |
>
> Chaque PR de calibration ajoute **une ligne et une seule** au journal. Le gold
> (réel, revu PO) et le `--compare` fournissent le delta.

## Tests

```bash
cd packages/api && pytest \
    tests/scripts/test_build_event_dataset.py \
    tests/scripts/test_label_event_dataset.py \
    tests/scripts/test_evaluate_event_clustering.py \
    tests/test_perspective_service.py -v
```

Tests **purs** (sans réseau ni DB). Le smoke `test_evaluate_toy_pool_*` vérifie
le toy à confusion connue (TP=2, FP=4 `weak_double_signal`, FN=4
`jaccard_below_floor`) et le sweep (floor 0.15 tue les 4 FP sans coût de rappel).

## Pièges

1. `Source.bias_stance` est un `StrEnum` SQLAlchemy ⇒ sérialiser via `.value`.
2. `Content.entities` est `text[]` de chaînes JSON ⇒ `json.loads(raw)` par
   élément (`_parse_entity_names`), jamais `c.entities[0]["name"]`.
3. MCP Supabase tronque à ~1 000 rows ⇒ paginer si le pool dépasse.
4. `LOCATION` est exclu des entités discriminantes (`Iran` ne compte pas) :
   bien fournir des `entities` PERSON/ORG/EVENT pour exercer `full_signals`.
5. Confirmer que le dump porte bien `content.topics` (slugs ML) et pas un thème
   source (cf. risque « provenance topics » du plan).
6. **Anti-drift** : ne pas réimplémenter la porte — `gate_pair` (défaut) DOIT
   rester identique à `_is_topically_coherent` (test dédié). Les params de
   `gate_pair` servent uniquement au sweep.
7. PR base `main` obligatoire ; `staging` bloqué par hook.

## Suite (hors PR — actés, non implémentés)

**Direction de fond = sémantique par embeddings.** Le lexical seul ne distingue
pas deux événements partageant une entité (FP) et rate les paraphrases (FN).
Piste : colonne `pgvector` sur `Content`, embeddings `mistral-embed` sur
`titre (+ description)`, appartenance gated par **cosinus dans une fenêtre
temporelle serrée + ≥1 entité discriminante partagée**. Le gold + harness de
cette PR deviennent le banc de mesure de cette refonte (chaque itération
mesurée, journal de calibration).
