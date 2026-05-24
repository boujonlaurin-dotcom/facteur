# PR 1 — Backend : Filtre par langue & `Source.language` (curation FR-first)

## Contexte

PR 1/2 du plan **language-aware curation**. Introduit la prise en compte
de la langue de la source dans les pipelines Essentiel / feed / digest,
contrôlée par une préférence user `hide_non_fr_sources` masquant les
cartes des sources non-FR — sauf si la source est explicitement suivie.

La couche mobile + section "Couverture à l'étranger" (panel perspectives)
arrivent en PR 2.

## Changements

### Données

- **Migration `lg02_source_language_user_pref`** (down_revision : `lg01`) :
  - `sources.language String(8) NULL, indexed` ; backfill par langue
    majoritaire (≥ 60 %) à partir de `Content.language`.
  - `user_personalization.hide_non_fr_sources` (Boolean, default `true`).
  - `user_personalization.language_filter_user_set` (Boolean, default
    `false`) — flag "mode auto".
  - Backfill `hide_non_fr_sources = false` pour les users qui suivent
    déjà ≥ 1 source étrangère (respect du choix implicite).

### Services

- `app/services/language_user_filter.py` (nouveau) :
  - `is_foreign_source`, `get_hide_non_fr_pref`, `apply_language_filter`
    (filtre Python), `language_filter_clause` (clause SQL partagée
    digest_selector ↔ recommendation_service), `recompute_auto_pref`
    (mode auto bascule sur follow/unfollow).
- `essentiel_service` : `EssentielUserContext.hide_non_fr_sources` +
  `_filter_articles_by_language` appliqué avant le scoring.
- `recommendation_service._get_candidates` : filtre SQL équivalent
  (followed sources jamais filtrées). Désactivé en mode "browse a
  specific source" (exploration).
- `digest_selector` : `DigestContext.hide_non_fr_sources` + filtre SQL
  sur le pool curated (les articles des sources suivies passent par
  `user_sources_query`, hors filtre par construction).
- `source_service.{trust,untrust,create,delete}_source` : appellent
  `recompute_auto_pref` après mutation.

### API

- `SourceMini.language: str | None` (forward-compat, propagé dans tous
  les schemas qui l'embarquent).
- `ContentResponse.language`, `DigestTopicArticle.language`,
  `EssentielArticle.language` (forward-compat — utile au debug et label
  éventuel côté mobile).
- `GET /api/personalization` expose `hide_non_fr_sources` +
  `language_filter_user_set`.
- `POST /api/personalization/toggle-hide-non-fr-sources` : toute MAJ
  flippe `language_filter_user_set = true` (gel du choix user).

### Background

- `app/jobs/recompute_source_language.py` (nouveau) : recalcule
  `sources.language` 1×/jour à partir de `Content.language` des 30
  derniers jours (seuil majoritaire 60 %).
- Scheduler : nouveau job `recompute_source_language` à 03h30 Paris.

## Tests

- `tests/services/test_language_user_filter.py` (nouveau) :
  - 8 unit tests pure-Python.
  - 6 tests DB pour `get_hide_non_fr_pref` + `recompute_auto_pref`
    (mode auto / manuel, no-op sans personalization row).
- Suite backend complète : **1285 passed, 1 skipped, 2 xfailed** sur DB
  locale post-migration `lg02`.

## Vérification

```
cd packages/api && python -m alembic heads          # → lg02_source_language_user_pref seule head
cd packages/api && python -m alembic upgrade head   # DB vide → OK (jouée localement)
cd packages/api && python -m pytest -q              # 1285 passed
```

## Points d'attention

- **`Source.language=NULL` → traité comme FR** (rétro-compat avec le
  client mobile et `editorial/writer.py:_looks_french`). Conséquence :
  une source dont la langue n'est pas encore détectée ne sera pas
  masquée.
- **Filtre désactivé en exploration source** (`source_id` query param) :
  on n'ampute pas le browse explicite.
- **`recompute_auto_pref` flushe avant SELECT** : la nouvelle
  UserSource doit être visible. Hooks placés après `db.flush()`.
- **Mobile (PR 2)** reste à faire : toggle "Masquer sources non-FR" +
  section "Couverture à l'étranger" dans le panel perspectives.

## Follow-ups identifiés

- La whitelist `is_french_source` peut mislabel certaines sources
  (Story 7.7 — labellisation manuelle du catalogue). Acceptable pour PR 1.
- Pas de migration côté Story 7.7 = on s'appuie sur le job daily pour
  rattraper les nouvelles sources.
