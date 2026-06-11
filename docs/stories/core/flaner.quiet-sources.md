# Story — Flâner : carrousel « Tes sources discrètes » + ajustements carrousels

## Statut

Implémentée (backend-only, 1 PR).

## Contexte

Les sources suivies qui publient peu (1x/2 semaines, 1x/mois) passent au travers
de l'Essentiel quotidien (digest pré-généré qui exclut les sources suivies par
design) et du feed Flâner (noyées par le volume). Le PO veut un carrousel
horizontal dans Flâner montrant le dernier article de chaque source suivie
« rare ».

**Décisions actées (brainstorm)** :

- Flâner uniquement (pas l'Essentiel).
- Source « rare » = source suivie avec **< 3 articles publiés dans les 30 derniers jours**.
- Contenu = **dernier article de chaque source rare, fenêtre 60 j, non lu** (non consommé).

**Découverte clé** : le pipeline carrousels est entièrement server-driven.
`flaner_screen.dart` (`_buildFeedList`) rend génériquement tout carrousel de
`state.carousels`, et le fallback badge existe (`editorial_badge.dart`, code
inconnu → chip emoji+label couleur `textSecondary`). **Aucune modification
mobile nécessaire.**

**Bonus actés dans la même PR** (tout vit dans `recommendation_service.py`) :

1. « Plus tard, c'est maintenant ! » (`saved`) : tri du plus récemment
   sauvegardé au plus ancien (`coalesce(saved_at, created_at).desc()`).
2. Désactivation du carrousel `deep` « Ouvrir ses horizons » via flag
   module-level `DEEP_CAROUSEL_ENABLED = False` (code conservé).
3. Ré-ordre des positions de base des carrousels.

## Implémentation

### `packages/api/app/services/recommendation_service.py`

- **`_CAROUSEL_BASE_POSITIONS`** : `{"favorite": 5, "quiet_sources": 11,
  "saved": 17, "decale": 17, "new_source": 23, "hot": 29, "community": 35,
  "deep": 41}`. Ordre à valider à la review (le PO n'a pas tranché l'ordre
  final — ajustable par simple édition du dict). `deep` reste dans le dict
  (collision resolver) mais n'est plus émis.
- **Nouveau bloc `quiet_sources` dans `_build_carousels()`** (Phase B, entre
  `new_source` et `community`) :
  - Requête 1 — sources rares : `UserSource` (state FOLLOWED/FAVORITE) join
    `Source` (is_active) outerjoin `Content` (published_at ≥ now−30j),
    `GROUP BY HAVING count < 3`. Index existant `ix_contents_source_published`
    couvre — pas de migration.
  - Requête 2 — dernier article par source rare : `DISTINCT ON (source_id)`,
    `published_at ≥ now−60j`, exclusion `promoted_ids | consumed_ids`,
    tri final `published_at.desc()`, cap `MAX_CAROUSEL_ITEMS` (5).
  - Seuil `MIN_DISPLAY_ITEMS` (2) sinon pas de carrousel.
    `carousel_type="quiet_sources"`, titre « Tes sources discrètes »,
    emoji 🤫, badge par item `{"code": "quiet_source", "label": <nom source>,
    "emoji": "🔎"}`. Ids ajoutés à `promoted_ids` (dédup feed).
- **Saved desc** : `order_by(coalesce(saved_at, created_at).desc())`.
- **Deep off** : `DEEP_CAROUSEL_ENABLED = False`, early-skip du bloc, code et
  `find_perspectives_for_read_article` conservés.

### Tasks

- [x] Mapping `_CAROUSEL_BASE_POSITIONS` ré-ordonné
- [x] Bloc `quiet_sources` (2 requêtes agrégées, pas de N+1)
- [x] Saved trié desc (coalesce saved_at/created_at)
- [x] Flag `DEEP_CAROUSEL_ENABLED = False`
- [x] Tests `tests/test_feed_carousels_quiet_sources.py` (DB-driven)
- [x] MAJ tests existants (`test_feed_carousels.py`, `test_feed_carousels_ordering.py`)
- [x] Changelog `apps/mobile/assets/changelog.json` (unreleased)

### Fichiers modifiés

- `packages/api/app/services/recommendation_service.py`
- `packages/api/tests/test_feed_carousels_quiet_sources.py` (nouveau)
- `packages/api/tests/test_feed_carousels.py`
- `packages/api/tests/test_feed_carousels_ordering.py`
- `apps/mobile/assets/changelog.json`

## Edge cases / risques

- Risque faible : bloc additif isolé, pas de DDL, pas de changement API.
- Cas vides (aucune source rare / tout lu / rien ≤60j) → carrousel absent.
- YouTube/newsletters = `Content` normaux → inclus naturellement.
- Perf : +1-2 requêtes par feed non-caché, index existants.
- Old app versions afficheront aussi le carrousel (rendu générique + fallback badge).
