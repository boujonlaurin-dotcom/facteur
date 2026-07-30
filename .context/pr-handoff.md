# feat(reco): allumer le bonus de pluralité (couverture multi-sources) sur le digest

Base `main`. **Aucune migration.** Backend-only (0 fichier mobile).

## Résumé

Le pilier Pertinence calcule un bonus log-calibré pour les clusters multi-sources
(`2→+12, 3→+19, 4→+24, cap 30`) mais c'était **du code mort partout** : aucun call
site ne passait le count au `ScoringContext`, et la garde `content.cluster_id`
tombait sur NULL pour ~99 % des candidats (`contents.cluster_id` NULL à 99 % en
base — 298 / 29 414 sur 14j, uuid4 régénéré par run). Cette PR allume le signal
**pour la première fois**, sur le chemin `topics` (cœur digest).

Doc : `docs/maintenance/maintenance-coverage-pillar-wiring.md`.

## Approche — sûre, sans mutation ORM ni migration

Le count du cluster est porté **directement sur le `ScoringContext`** (construit par
cluster dans `_score_and_select_articles`, donc `len(cluster.source_domains)`
s'applique à tous ses contents), et non via une mutation de `content.cluster_id` —
muter cet attribut ORM sur des `Content` attachés à la session risquerait un
autoflush vers la **DB prod partagée** (la colonne même que le pipeline peuple avec
des uuid4 par-run).

- `ScoringContext.coverage_source_count: int | None` — nouveau champ optionnel.
- `_score_coverage` — fast-path context-carried (prioritaire), fallback dict
  `cluster_source_counts` inchangé.
- `topic_selector` — `_build_scoring_context(..., coverage_source_count=len(cluster.source_domains))`.

## Périmètre / discipline (GO PO Laurin)

- **Chemin `topics` seulement.** Tournée/curation + flat éditorial reportés (le flat
  `_project_editorial_for_user` double-compterait avec `subject_importance`).
- **`COVERAGE_CAP=30` inchangé** — levier unique = allumage du signal ; le cap est un
  2e levier reporté (de toute façon `max_src=4` en prod ⇒ plafond effectif +24).
- **0 migration, 0 mutation ORM.** Commit isolé/révocable.

## Tests

- `tests/recommendation/test_pertinence_coverage.py` : +3 cas context-carried
  (bonus sans `cluster_id`, mono-source = 0, priorité sur dict).
- `tests/test_topic_selector.py` : +2 cas d'intégration (cluster ≥3 sources →
  « Couvert par 3 sources » dans le breakdown ; mono-source → rien).
- Suite reco + digest : **119 passed**, 0 régression. `alembic heads` = 1 head
  (`sa02_alerts_v2`).

## Mesure post-merge (jauge)

`by_pillar_band["pertinence"]` (`scripts/evaluate_feed_ranking.py`). **Forward-only**
⇒ bandes vides avant date de merge, fenêtre d'observation ≥7j. **Puissance faible**
(~13 clusters ≥3 src / 14j) : absence de mouvement CTR ≠ preuve d'inefficacité.

## Hors périmètre

Aucun changement mobile, aucune migration, cap inchangé, Tournée/curation/flat non
touchés.
