# Maintenance — Calibration de la curation veille (ajustements « released »)

> **Date** : 2026-06-09
> **Branche** : `boujonlaurin-dotcom/veille-final-adjustments`
> **PR ciblée** : `main`
> **Type** : outillage + fix mesuré (gate-all des sources configurées)
> **Template** : [`maintenance-clustering-calibration.md`](./maintenance-clustering-calibration.md)

## Contexte

La Veille n'était pas digne d'être « released » à cause de **trop de
faux-positifs**. Capture PO (compte `laurin_boujon@proton.me`, veille NBA) : une
veille « NBA » affichait du cricket (Ben Stokes / Harry Brook), du hockey
(Penguins, Canucks), du baseball (Dodgers / Mookie Betts) — presque tout taggé
« The Athletic + ». Un seul article sur cinq était réellement NBA.

**Cause racine (vérifiée dans le code).** `fetch_veille_feed`
(`packages/api/app/services/veille/feed_filter.py`) construit le feed en deux
blocs. Le **Bloc A « Tes sources »** appelait
`_score_block(apply_floor=False, apply_threshold=False, diversity_cap=3)` :
**laisser-passer**. Tout article récent (30 j) d'une source configurée entrait
sans filtre de pertinence. Pour une source large comme The Athletic (tous les
sports), ça inonde une veille étroite (NBA). Le floor « la source est un boost,
pas un free-pass » (validé par `prove_veille_curation.py`) **ne tournait jamais**
en prod pour les sources configurées (elles passent par le Bloc A, pas le Bloc B).

**Aggravant structurel.** La taxonomie ML n'a que ~50 topics grossiers
(`app/services/ml/topic_theme_mapper.py`) : **tous les sports → un seul slug
`sport`**. Le topic `nba` n'existe pas → `Content.topics.overlap(["nba"])` ne
matche jamais → le bonus topic (+50) est **mort pour la NBA**. Le seul axe de
pertinence qui fonctionne pour un topic granulaire comme NBA est le **mot-clé**
(regex mot-entier).

> Règle d'or PO (mémoire `feedback_highlight_no_brute_rules`,
> `feedback_calibration_no_overfit`) : **mesure avant règle**. On instrumente, on
> chiffre, puis on règle un levier mesuré contre un gold. Pas de stoplist / règle
> métier en dur — le gate-all est un invariant structurel (« la source est un
> boost »), pas un jugement éditorial.

## Décisions PO

1. **Curation** : gater **TOUTES** les sources configurées (zéro laisser-passer,
   le plus strict).
2. **Analyse** : dataset fixture **monté à la main** + script d'évaluation,
   **sans** pipeline de labelling LLM ni revue PO (le gold est écrit à la main).
3. **Livraison** : 1 seule PR (curation backend + UI mobile), base `main`.

## Livrables

| Fichier | Rôle |
|---------|------|
| `app/services/veille/feed_filter.py` | Fix : Bloc A `apply_floor=True, apply_threshold=True` ; `_matched_axes` en mot-entier (`matches_word_boundary`). |
| `scripts/evaluate_veille_curation.py` | Harness sur la **vraie** porte (`_score_block`/`_matched_axes`) : P/R/F1, FP par bloc, FP par chemin, FN par raison, couverture d'axe, `--sweep`, `--compare`. |
| `tests/fixtures/veille_curation_gold.json` | Gold écrit à la main (`dataset_kind: veille_curation`) : configs NBA (topic ML mort) + IA (topic ML vivant), 27 articles. |
| `tests/scripts/test_evaluate_veille_curation.py` | Tests purs : anti-drift (symboles réels), toy à confusion connue, attribution. |
| `tests/scripts/fixtures/toy_veille_curation.json` | Toy : FP Bloc A `source_only` planté ; off_angle « agentic » (mot-entier) ; FN mot-clé-absent. |
| `.context/veille-curation-*.json\|.md` | Généré, gitignored. |

## Schéma du gold (`dataset_kind: veille_curation`)

```json
{
  "schema_version": 1, "dataset_kind": "veille_curation",
  "configs": [{
    "config_key": "nba", "theme_id": "sport", "theme_label": "Sport",
    "angles": [{"topic_id": "nba", "label": "NBA", "keywords": ["nba", "lebron", ...]}],
    "global_keywords": [],
    "sources": [{"source_id": "athletic", "name": "The Athletic", "kind": "curated"}],
    "articles": [{
      "id": "A1", "title": "...", "description": "", "topics": ["sport"],
      "source_id": "athletic", "source_name": "The Athletic",
      "published_at": "2026-06-09T10:00:00+00:00", "label": "relevant"
    }]
  }]
}
```

`label ∈ {relevant, off_angle}`. Le `source_id` d'un article peut référencer une
source **hors** `sources` (article externe → candidat Bloc B). Le repro est
encodé explicitement : The Athletic (suivie) avec cricket/hockey/baseball
`off_angle` (`topics:["sport"]`, sans mot-clé NBA) ; un article NBA avec mot-clé
(`relevant`) ; un article NBA **paraphrasé sans mot-clé littéral** (`relevant`,
mesure le faux-négatif) ; une source niche dédiée (BasketUSA).

## Comment ça marche (anti-drift)

Le harness **rejoue la vraie porte** — il importe et appelle
`feed_filter._score_block` et `_matched_axes` (un fork casserait
`test_harness_uses_real_gate_symbols`). Il reconstruit le `ScoringContext` via le
**vrai** `build_veille_scoring_context` (stub de session, sans DB) et des
`Content`/`Source` transitoires (pattern de `prove_veille_curation.py`). Il
partitionne les candidats en Bloc A (source configurée) / Bloc B (topics/mots-clés
hors sources, via le **vrai** prédicat mot-entier `matches_word_boundary`), puis
rejoue `_score_block` par bloc. La décision garder/écarter vient de la fonction de
prod ; le harness n'attribue que le *chemin* d'acceptation et la *raison* de rejet.

## Workflow

```bash
cd packages/api
# Baseline (avant — laisser-passer Bloc A = prod actuelle)
PYTHONPATH=. python scripts/evaluate_veille_curation.py \
    --dataset tests/fixtures/veille_curation_gold.json \
    --tag baseline --block-a-policy passthrough
# Sweep du levier Bloc A {laisser-passer | floor | floor+seuil} (+ seuil)
PYTHONPATH=. python scripts/evaluate_veille_curation.py \
    --dataset tests/fixtures/veille_curation_gold.json --tag baseline --sweep \
    --block-a-policy passthrough
# After (gate-all = nouvelle prod)
PYTHONPATH=. python scripts/evaluate_veille_curation.py \
    --dataset tests/fixtures/veille_curation_gold.json \
    --tag iter1 --block-a-policy floor_threshold
# Delta
PYTHONPATH=. python scripts/evaluate_veille_curation.py --compare \
    ../../.context/veille-curation-baseline-<date>.json \
    ../../.context/veille-curation-iter1-<date>.json
```

> ⚠️ Le `--sweep` n'écrit dans le JSON principal que les métriques de
> `--block-a-policy` ; pour un `--compare` propre, lancer deux runs distincts
> (`passthrough` puis `floor_threshold`).

### Sweep du levier Bloc A (gold)

| Réglage | P | R | F1 | FP | FP_blocA | FP_source_only | FN |
|---------|---|---|----|----|----------|----------------|----|
| passthrough | 0.786 | 0.846 | 0.815 | 3 | 3 | 3 | 2 |
| floor | 1.000 | 0.846 | 0.917 | 0 | 0 | 0 | 2 |
| floor_threshold @44 | 1.000 | 0.846 | 0.917 | 0 | 0 | 0 | 2 |
| floor_threshold @48 | 1.000 | 0.846 | 0.917 | 0 | 0 | 0 | 2 |
| floor_threshold @52 | 1.000 | 0.846 | 0.917 | 0 | 0 | 0 | 2 |

Le floor seul suffit à supprimer les 3 FP `source_only` du Bloc A ; le seuil
n'ajoute aucun FP/FN sur le gold (les off_angle source-seuls sont déjà tués par le
floor, les on-angle à mot-clé passent largement le seuil 48). On retient
**floor+seuil** (le plus strict, décision PO) puisqu'il **ne coûte aucun rappel**
ici.

## Journal de calibration (append-only)

| Iter | Date | Param | P | R | FP_blocA | FP_source_only | FN_floor | ΔP | Notes |
|------|------|-------|---|---|----------|----------------|----------|----|-------|
| 0 | 2026-06-09 | baseline (Bloc A laisser-passer) | 0.786 | 0.846 | 3 | 3 | 0 | — | gold main 27 articles / 2 configs ; les 3 FP sont tous `source_only` Bloc A (cricket/hockey/baseball The Athletic+ESPN survivant au cap) — preuve directe du diagnostic. Les 2 FN sont `diversity_capped` (paraphrases sans mot-clé). |
| 1 | 2026-06-09 | Bloc A `apply_floor=True, apply_threshold=True` + `_matched_axes` mot-entier | 1.000 | 0.846 | 0 | 0 | 2 | +0.214 | **FP −3 (→0)** : le floor tue tous les `source_only` Bloc A. **Rappel inchangé** (0.846) : les 2 FN basculent de `diversity_capped` (baseline) à `floor_source_only` (paraphrases NBA sans mot-clé littéral) — déjà perdues en baseline via le cap, donc gate-all = **précision gratuite**. F1 0.815 → 0.917. |

> **Couverture d'axe** (parmi les 13 `relevant`) : 3 avec topic ML, **8
> mot-clé-seul (61,5 %)**, 2 source-seul (15,4 %). Quantifie le trou « nba » : la
> NBA n'a **aucun** axe topic (topic ML mort) → tout repose sur les mots-clés.
> Les 2 `relevant` source-seul (paraphrases NBA sans mot-clé) sont le **coût en
> rappel structurel** du gate-all — pas un trou à corriger ici (les corriger
> demanderait un topic ML granulaire ou des embeddings, cf. *Suite*). En face, la
> config IA (topic `ai` **vivant**) a P=R=1.0 sans rien perdre au gate-all : le
> topic porte le rappel.

## Garde-fou mesuré (topic granulaire sans slug ML)

Le garde-fou « le floor ne doit pas avoir 0 axe » est déjà assuré côté écriture de
config : l'`angle_suggester` produit une grappe de mots-clés non vide pour chaque
angle. La couverture d'axe ci-dessus confirme qu'**aucune enforcement
supplémentaire n'est nécessaire** sur le gold : le rappel ne bouge pas (0.846).
On documente donc l'invariant sans l'activer (respecte « pas de règle métier en
dur »). Si un gold futur révèle un vrai trou de rappel (relevant source-seul en
hausse), l'enforcement « `topic_id ∉ TOPIC_TO_THEME` ⇒ grappe de mots-clés
obligatoire » (import du vrai `topic_theme_mapper.TOPIC_TO_THEME`) sera activé.

## Tests

```bash
cd packages/api
PYTHONPATH=. python -m pytest \
    tests/scripts/test_evaluate_veille_curation.py \
    tests/test_veille_curation.py -v
# (les 2 tests DB de fetch_veille_feed exigent DATABASE_URL vers facteur_test :
#  export DATABASE_URL="postgresql+psycopg://facteur:facteur@localhost:54322/facteur_test")
PYTHONPATH=. python scripts/prove_veille_curation.py   # VERDICT GLOBAL : OK
```

## Pièges

1. Le `--sweep` réutilise le JSON principal de `--block-a-policy` ; lancer deux
   runs pour un `--compare` propre (cf. avertissement plus haut).
2. Le gold est **petit** (27 articles) → les FP/FN sont en unités, pas en
   centaines (contrairement au harness clustering sur données prod). C'est voulu :
   décision PO « fixture montée à la main ». La **direction** et le **mécanisme**
   (FP `source_only` Bloc A → 0) sont la preuve, pas la magnitude.
3. `_matched_axes` était la **dernière** couche en sous-chaîne (le pilier
   Pertinence et le prédicat SQL étaient déjà en mot-entier) ; l'aligner empêche
   un mot-clé générique de survivre sur un fragment (« nets » ⊂ « internets »)
   dans le Bloc A, où la requête par source court-circuite le prédicat SQL.
4. Une config **purement source** (aucun topic/mot-clé) garde le laisser-passer :
   `floor_active = apply_floor and bool(topic_slugs or keywords)` reste `False`.
   Le gate ne mord que sur les configs avec un axe topic/mot-clé.
5. PR base `main` obligatoire ; `staging` bloqué par hook.

## Suite (hors PR — actés, non implémentés)

Le trou de rappel résiduel (paraphrases NBA sans mot-clé littéral) ne se règle pas
au niveau de la porte : il demande soit un **topic ML granulaire** (`nba` comme
slug à part entière dans la taxonomie), soit des **embeddings** (similarité
sémantique angle ↔ article). Le gold + harness de cette PR deviennent le banc de
mesure de cette refonte (chaque itération mesurée, journal append-only).
