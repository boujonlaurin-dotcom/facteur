# Veille — refonte curation deux blocs + UX fin de config

## Résumé

Le feed veille (`GET /api/veille/feed`, section `SectionKind.veille` du flux continu)
est refondu en **deux blocs** pour corriger deux bugs PO :
1. sources configurées invisibles (fenêtre 7 j + règle « floor » tuaient les flux
   niche/anglophones) ;
2. sources externes parasites (prédicat OR aspirait tout le pool global matchant un
   mot-clé).

## Backend (backward-safe — le mobile ignore `group` jusqu'au déploiement frontend)

- `scoring_config.py` : `VEILLE_CONFIGURED_RECENCY_HOURS=720` (30 j, Bloc A),
  `VEILLE_SOURCE_DIVERSITY_CAP=3`.
- `feed_filter.py` :
  - `VeilleFilters.source_intents` (charge `VeilleSource.why`).
  - `build_topic_keyword_predicate()` (= prédicat fort sans la clause source).
  - `_score_and_rank` → `_score_block(..., *, apply_floor, apply_threshold, diversity_cap)`.
  - `fetch_veille_feed()` : 2 requêtes (Bloc A `source_id IN` fenêtre 720 h, laisser-passer
    + cap diversité ; Bloc B topic/keyword `NOTIN` sources, fenêtre 168 h, floor+seuil),
    concaténées A→B, taguées `group`, paginées à plat. **Renvoie des 3-tuples
    `(Content, axes, group)`.**
- `scoring_context.py` : note d'intention `why` tokenisée (`_tokenize_intent`, stopwords FR
  + len≥4) → angle « Intention » (réutilise le bonus mots-clés existant).
- `schemas/veille.py` : `VeilleFeedArticle.group` (Literal sources/elargie, défaut
  `sources`) ; `VeilleSourceResponse.last_article_at` + `recent_article_count`.
- `routers/veille.py` : unpack 3-tuple + `group` ; agrégation santé source dans
  `GET /config`. **Pas de migration** (`why` existe déjà).

### Tests backend
- `tests/test_veille_curation.py` : Bloc A laisser-passer + cap diversité ; floor Bloc B ;
  end-to-end deux blocs ; tokenisation intent.
- `tests/services/test_veille_scoring.py` : intent `why` injecté ; split récence 30j/7j ;
  unpacking 3-tuples mis à jour.
- `tests/routers/test_veille_routes.py` : `group` par item ; ordre A→B ; pagination à la
  frontière ; santé source dans `/config`.
- **64 tests veille passent** ; suite backend complète **1524 passed** (la seule rouge —
  `test_notification_preferences::test_patch_increments_refusal_count` — est pré-existante,
  clock-dépendante, sans rapport).

## Frontend (dépend du backend)

- `feed/models/content_model.dart` : `Content.veilleGroup` (parse `json['group']`,
  copyWith, clearNote) — backward-safe nullable.
- `flux_continu/repositories/flux_continu_repository.dart` : passe `group` dans le JSON
  Content normalisé.
- `flux_continu/widgets/veille_group_header.dart` (nouveau) : `buildVeilleFeedRows()`
  (en-têtes dérivés au rendu sur transitions de group) + `VeilleGroupHeader`.
- `section_block.dart` + `theme_section_screen.dart` : en-têtes « Tes sources » /
  « Couverture élargie » pour `SectionKind.veille` (pagination plate inchangée — lignes
  reconstruites depuis la liste accumulée).
- `veille/screens/veille_config_screen.dart` : modal « Épingler à ta Tournée ? » en fin de
  **création** → insertion #1 (`markCustomized` + `setHidden(false)` +
  `setOrder([veille, ...rest])`).
- `veille/models/veille_config_dto.dart` : parse `last_article_at`/`recent_article_count`
  + getter `healthWarning`.

### Tests frontend
- `test/.../widgets/veille_group_header_test.dart` : transitions de group, backward-safe,
  index préservé, rendu du libellé — **5 passent**.
- `flutter analyze lib` : 0 erreur / 0 warning dans les fichiers touchés.

## Reporté (follow-up, hors de ce lot)
- Badge santé **visuel** dans la source card (DTO `healthWarning` prêt) + champs texte
  « Préciser » (why source / reason angle) dans step2/step3 — nécessite du state provider
  dans des écrans de 900+ lignes.
- Expansion EN des mots-clés (`suggest_angles`) — PR-3 légère derrière flag.

## Découpage proposé
PR-1 backend (backward-safe) puis PR-2 frontend, OU un seul PR cohérent (PO préfère
moins de PRs). À trancher au moment de la création.
