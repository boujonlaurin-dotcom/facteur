feat(onboarding): sources spécialisées par sujet — re-mapping taxonomie 51-slugs + badge « Spécialisé en X » (Epic 12)

Aligne le vocabulaire des `granular_topics` des **sources** sur la taxonomie **51-slugs** des users/articles et garantit, dans l'écran de reco onboarding, **≥1 source spécialisée visible par sujet sélectionné** (badge « Spécialisé en X »). Livré en **1 PR groupée** (backend data + mobile UI) vers `main`. Additif, **aucune migration Alembic** (`granular_topics`/`is_curated` existent déjà → backfill data gaté PO).

## Problème

Le recommender d'onboarding score `source.granularTopics ∩ user.selectedSubtopics`, mais les deux vivaient dans des **taxonomies incompatibles** : sources en ancien vocab (`social-justice`, `energy-transition`, `data-privacy`…), users/articles en 51-slugs (`inequality`, `energy`, `privacy`…). Résultat : le bonus « spécialiste » ne se déclenchait quasi jamais (~35/51 subtopics sans source curée correspondante) → pas d'effet « wow ». Le catalogue curé (66/296 actives) était aussi trop mince.

## Ce que ça change (user-visible)

- **Un spécialiste par sujet, dès l'inscription.** Chaque sous-sujet choisi obtient au moins une carte « 🎯 Spécialisé en {sujet} », en tête des suggestions et pré-cochée.
- **Cartes spécialistes distinctes par sujet** (quand la data le permet), libellés FR via `getTopicLabel` (51 slugs couverts).

## Technique (additif, sans migration)

### Backend / data
- **`scripts/retag_and_promote_sources.py`** (nouveau, scaffolding CLI dry-run/`--apply`/`--allow-prod`/backup JSON repris d'`apply_source_evaluations.py`) :
  - **A1 — dérivation `granular_topics`** : sur 90 j, agrège `unnest(contents.topics)` par topic ; `share = n_topic / n_total` ; retient si `n ≥ MIN_COUNT(4)` **et** `share ≥ MIN_SHARE(0.10)`, capé `TOP_K(6)`, **ordonné par share desc** (1er = spécialité dominante = badge). Dérivation vide → on **conserve** les slugs déjà valides et purge l'ancien vocab (jamais de wipe d'un vrai spécialiste mince).
  - **A2 — promotion catalogue** : `is_active ∧ ¬is_curated ∧ bias≠unknown ∧ reliability∈{medium,high} ∧ articles_30d ≥ 20` → `is_curated=true`.
  - Sorties : mutation DB gatée + backup JSON ; `--write-csv` régénère `granular_topics`/`Status` de `sources_master.csv` (diff relisible PO, ajoute les promues) ; **audit de couverture** 51 subtopics (≥1 spécialiste partout).
- **`scripts/validate_taxonomy.py`** : supprime le `VALID_TOPICS` local (ancien vocab) → importe `VALID_TOPIC_SLUGS` (51) + `VALID_THEMES` (9) canoniques. Ferme l'Epic 12 côté sources.
- **`scripts/_backfill_new_yt.py` + `backfill_youtube_deep.py`** : `granular_topics` hardcodés re-mappés en 51-slugs (sinon ré-introduisaient l'ancien vocab au prochain seed).
- **NE TOUCHE PAS `secondary_themes`** (vocab macro-thème, consommé par le pipeline digest). Aucune logique digest ne matche sur `granular_topics`.

### Mobile / UI
- **`source_recommender.dart`** : `RecommendationTagType.specialist` ; badge « Spécialisé en X » quand `granularTopics.first ∈ selectedSubtopics` (pas de double chip thème). **Garantie de couverture** `_computeSpecialists` : pour chaque subtopic non couvert par un spécialiste dominant de `matched`, tire le meilleur spécialiste curé restant (dominant → score → fiabilité → volume) ; nouveau champ `SourceRecommendation.specialists` (disjoint, inclus dans `preselectedIds`).
- **`sources_question.dart`** : spécialistes placés **en tête** des suggestions (survivent au cap 18) + dédup par id.
- **`source_recommendation_card.dart`** : rendu du chip spécialiste (préfixe 🎯, teinte primary).

## Apply prod (gaté PO, étape séparée post-merge)

`cd packages/api && python3 scripts/retag_and_promote_sources.py --write-csv` (dry-run lecture prod → diff CSV + audit), revue PO, puis `--apply --allow-prod`. Backup JSON conservé. La reco prod en bénéficie aussi (subtopics users prod déjà en 51-slugs), sans régression de matching attendue.

## Tests
- **Backend** : `tests/scripts/test_retag_and_promote_sources.py` (19 tests purs) — dérivation (seuils, ordre par share, top-K, vocab 51), résolution conservatrice, promotion, audit couverture, régénération CSV.
- **Mobile** : `source_recommender_test.dart` (+5 tests) — badge dominant, pas de badge sur subtopic non dominant, garantie hors-matched, pas de doublon, cartes distinctes par sujet.
- `validate_taxonomy` importe 51 slugs + 9 thèmes (vérifié). `flutter analyze` propre sur les fichiers touchés.

## Changelog
Entrée `unreleased` : `{ "tag": "Sources", "summary": "Des sources spécialisées sur chacun de tes sujets dès l'inscription." }`
