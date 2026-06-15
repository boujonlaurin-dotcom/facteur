# Bug — Surlignage des titres : désalignement & qualité (precision-first)

> **Type** : Bug (qualité killer-feature) · **Story** : 7.4 (Couverture médiatique / perspectives)
> **PR** : cible `main` · **Périmètre** : PR1 (garde-fous structurels) + PR2 (prompt LLM) en **une seule PR** (décision PO)
> **Source de l'analyse** : `cluster_title_annotations` en prod (336 lignes / 151 spans LLM, MCP Supabase 2026-06-06).

## Symptôme

Le surlignage surligne encore des mots **neutres** (« % » dans « 18% », « Direct »
dans « En direct », gentilés, clauses entières) malgré de nombreuses calibrations.
Cadrage PO : **augmenter drastiquement la qualité, quitte à réduire la quantité**
(precision ≫ recall — mieux vaut ne rien surligner qu'un mot neutre).

## Diagnostic — 4 causes racines

1. **Le chemin spaCy surligne des déchets.** `fr_core_news_md` mal-étiquette
   ponctuation/nombres (`%` NOUN, `-`/`|` PROPN, dates, `105`, emoji) → ils passent
   `KEEP_POS` car non-stopwords et deviennent des `highlight_spans`.
2. **La sélection LLM est médiocre en queue de distribution** : fillers (« en
   direct »), spans ≥ 4 mots (18 %), gentilés neutres taggés `fact`, spans
   imbriqués/dupliqués, ponctuation de bord incluse.
3. **Dérive d'offset** entre tokenisation et rendu : front `.trim()` du titre
   alors que les offsets sont calculés non-trimmés ; serve qui clampe mais ne
   **valide pas** `served_title[start:end] == text`.
4. **La boucle de calibration data-driven n'a jamais tourné** — l'outillage existe
   (`build_highlight_dataset.py`, `evaluate_title_annotations.py`) mais le gold et
   la baseline F1 n'ont jamais été produits.

## Principe directeur (cadrage PO)

**Limiter au maximum les règles brutes.** On sépare strictement :

- **Garde-fous STRUCTURELS, indépendants du contexte** (légitimes en dur car vrais
  *quel que soit* le contexte) → PR1.
- **Qualité éditoriale dépendante du contexte** (« en direct » filler ou pas, un
  gentilé est-il un cadrage, où couper) → traitée **uniquement** par le prompt LLM,
  **mesurée au benchmark**, jamais par des stoplists/règles métier → PR2.

## Correctifs

### PR1 — Garde-fous structurels (coût LLM nul, réversible)

- **A. Garde « validité structurelle ».** `_is_real_word(text)` (rejette tout
  fragment < 2 caractères alphabétiques) appliqué dans `_doc_to_tokens` (point de
  passage unique → protège cache cluster ET chemin live) et défensivement au serve.
  `MODEL_VERSION` → `v2-spacy-fr_md` pour purger le cache `strong_tokens` pollué
  (filtré par `model_version`, **pas de migration DB**).
- **B. Invariant d'offset au serve.** `_enforce_offset_invariant` exige
  `served_title[start:end] == text` pour chaque span (LLM **et** spaCy) ; sinon
  re-localise via `find_span` ; sinon **drop**. + retrait du `.trim()` Dart
  (`perspectives_bottom_sheet.dart`).
- **C. Nettoyage structurel des `target_spans` LLM au serve** (`_refine_llm_target_spans`,
  fonction pure) : re-ancrage (B) → **gate `weight ≥ 0.5`** (`MIN_DISPLAY_WEIGHT`,
  réutilise le score 0.25/0.5/1.0 que le LLM produit déjà) → trim ponctuation de
  bord → validité structurelle (A) → dé-imbrication (réutilise `spans_overlap`,
  garde le span englobant). **Aucune stoplist, aucune règle de contenu.**
- **D. Chemin live/hors-cluster — politique D2.** `diff_spans` accepte
  `max_spans`/`allowed_pos` (keyword-only, rétro-compatibles). Hors-cluster restreint
  à **ADJ/VERB only + cap 2** (`OFF_CLUSTER_*`). In-cluster **inchangé**. Bascule D1
  (cap 0) possible via la constante.

### PR2 — Qualité éditoriale via prompt LLM + benchmark

- **Prompt** `SCHEMA_DESCRIPTION` révisé : budget **0-2 spans, ≤ 3 mots**, verbes
  chargés / framing nouns, **contre-exemples en contexte** (en direct, gentilés
  neutres, dates, clauses, ponctuation de bord), « vide vaut mieux que faible ».
  Contrat JSON (catégories/poids) **inchangé**.
- **`LLM_VERSION`** → `mistral-medium-latest-v3` : invalide les `semantic_equiv` v2
  → ré-annotation au prochain passage pipeline. Snapshot du prompt regénéré.

## Rollout / déploiement

- Aucune migration Alembic (les deux bumps sont des champs/version filtrés au read).
- **Au déploiement**, `LLM_VERSION=v3` invalide tout `semantic_equiv` v2 : tant que
  le pipeline n'a pas ré-annoté, les perspectives in-cluster retombent sur spaCy
  (cap 4) et le live sur D2 — comportement conservateur **assumé** (precision-first).
  Déclencher une ré-annotation pour repeupler `semantic_equiv` en v3.

## Mesure éditoriale = le benchmark (étape PO-synchrone, hors-code)

La qualité éditoriale n'est validée que par `evaluate_title_annotations.py` contre
le gold des ~62 titres prod (baseline v2 → after v3, `--compare`). Cette étape
nécessite un pull prod (MCP Supabase) + validation PO du gold + appels Mistral :
elle se déroule **au moment du rollout**, pas dans cette PR (le code/outillage est
prêt). Cf. [`docs/maintenance/maintenance-highlight-calibration.md`](../maintenance/maintenance-highlight-calibration.md).

## Tests

- `tests/services/test_title_annotation_service.py` : `_is_real_word` (keep
  `UE`/`IA`/`réforme` ; drop `%`/`-`/`|`/`04/06`/`105`/emoji), `_doc_to_tokens` drop,
  `diff_spans` kwargs (cap 2 / ADJ-VERB / D1) sans régression du défaut in-cluster.
- `tests/routers/test_contents_perspectives_highlights.py` : invariant d'offset
  (relocate vs drop vs out-of-bounds), nettoyage C (bord ponctuation trimé,
  « restitutions » ⊂ « restitutions de biens » dé-imbriqué, weight 0.25 non affiché,
  champs LLM préservés), politique off-cluster D2 (ADJ/VERB, cap 2), gate weight
  bout-en-bout. **Aucun test ne vérifie une règle de contenu** (en direct / gentilés)
  — c'est la responsabilité du benchmark.
- Suite Dart `diff_title` + `perspectives_bottom_sheet` restent vertes.
