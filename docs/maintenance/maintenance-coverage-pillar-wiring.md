# Maintenance — Câbler le bonus de pluralité (couverture multi-sources) sur le digest

> Discipline « reco-quality step-up » : **un seul levier mesuré à la fois**, jauge
> avant/après, **zéro migration**, commit révocable. Fil lié : reco quality PR0 (#1034)
> / PR1 (#1035).

## Problème

`PertinencePillar._score_coverage` (`pillars/pertinence.py`) calcule un bonus
log-calibré pour les clusters multi-sources (`2→+12, 3→+19, 4→+24, cap 30`), mais
c'était **du code mort sur toutes les surfaces** : aucun call site ne passait
`cluster_source_counts` au `ScoringContext`, et la garde `content.cluster_id`
tombait sur `None` pour ~99 % des candidats (`contents.cluster_id` est NULL à 99 %
en base — 298 / 29 414 sur 14j, et l'ID est un `uuid4` régénéré par run).

## Décision (GO PO Laurin, 30/07)

- **Allumer d'abord sur le chemin `topics` uniquement** (cœur digest « l'essentiel
  couvert par plusieurs rédactions »). Tournée/curation et flat éditorial : cycle
  ultérieur, une fois la jauge lue.
- **`COVERAGE_CAP=30` inchangé** cette PR (levier unique = allumage du signal ;
  le cap est un 2e levier reporté). Note : `max_src=4` en prod ⇒ plafond effectif
  de facto **+24**.
- **Ne PAS allumer le flat éditorial** (`_project_editorial_for_user`) : double
  comptage avec `subject_importance` (`compute_coverage_score(source_count)`).

## Implémentation (5 fichiers, 0 migration, 0 mutation ORM)

Voie choisie : porter le count du cluster **directement sur le `ScoringContext`**
plutôt que muter `content.cluster_id` (attribut ORM → risque d'autoflush vers la
DB prod partagée). Le contexte est construit **par cluster** dans
`_score_and_select_articles`, donc `len(cluster.source_domains)` s'applique à tous
ses contents.

- `scoring_engine.py` — `ScoringContext` : nouveau champ optionnel
  `coverage_source_count: int | None`.
- `pillars/pertinence.py` — `_score_coverage` : fast-path context-carried
  (prioritaire), fallback dict `cluster_source_counts` inchangé.
- `topic_selector.py` — `_build_scoring_context(..., coverage_source_count)` +
  call site passant `len(cluster.source_domains)`.
- Tests : `test_pertinence_coverage.py` (3 cas context-carried : bonus sans
  `cluster_id`, mono-source = 0, priorité sur dict) + `test_topic_selector.py`
  (2 cas intégration threading : cluster ≥3 sources → « Couvert par 3 sources »,
  mono-source → rien).

## Mesure (jauge)

`scripts/evaluate_feed_ranking.py` → `by_pillar_band["pertinence"]`. Baseline =
« coverage = 0 partout » (signal mort avant merge). **Forward-only** : bandes
vides avant date de merge, prévoir fenêtre post-merge ≥7j. **Puissance faible** :
~13 clusters ≥3 src / 14j ⇒ absence de mouvement CTR ≠ preuve d'inefficacité.

## Non-régression

Flat legacy (`digest_selector._score_candidates`) et toutes surfaces hors `topics`
laissent `coverage_source_count=None` ⇒ comportement inchangé (fallback dict, vide).
Suite reco + digest : 119 passed.
