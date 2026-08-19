# Bug: couverture médiatique gonflée par le compteur de ranking

## Statut

- [ ] En cours d'investigation
- [ ] En cours de correction
- [x] Corrigé

## Sévérité

- P1 — 🟠 Haute

## Description

Les cartes peuvent afficher jusqu'à 14 sources alors que le reader ne propose
qu'un autre média. Le nombre visible mélange deux concepts différents :

- `source_count`, nombre de domaines du cluster utilisé pour le ranking ;
- `perspective_count`, ancien nombre partiel d'alternatives, filtré par biais ;
- `response.perspectives.length`, articles réellement consultables ;
- `coverageCount`, calcul mobile historique `max(source_count,
  perspective_count)`.

## Étapes de reproduction

1. Servir un payload avec `source_count=14` et `perspective_count=1`.
2. Ouvrir une carte puis le reader.
3. Constater « 14 sources » sur la carte mais une seule alternative dans le
   carrousel.

## Cause racine

Le signal de ranking `source_count` est exposé comme un compteur de couverture.
En parallèle, le pipeline persiste surtout les perspectives dont le biais est
connu. Les médias au biais `unknown` sont donc supprimés du snapshot et ne
peuvent pas être consultés, tandis que le client masque l'écart avec un `max`.

## Invariant public

`coverage_count` est le nombre total de domaines éditoriaux qui couvrent le
même sujet, média courant inclus. Pour chaque article appartenant à ce snapshot,
`GET /contents/{id}/perspectives` renvoie exactement `coverage_count - 1`
autres domaines.

Les sources au biais `unknown` comptent et restent consultables. Elles sont
exclues uniquement de `bias_distribution`, du niveau de polarisation et des
visualisations politiques. L'analyse neutre peut utiliser toutes les sources.

## Solution

- [x] Construire un univers commun pivot + cluster + résultats internes/Google
  News, filtré par cohérence thématique et dédupliqué par domaine.
- [x] Exclure les agrégateurs sans production éditoriale et conserver les biais
  `unknown`.
- [x] Persister dans le JSONB existant `coverage_count`, `coverage_articles` et
  `coverage_sources`, pivot inclus ; aucune migration SQL.
- [x] Faire retirer par le reader le domaine actuellement lu et exposer le
  compteur total stable.
- [x] Ajouter les champs aux contrats Digest et Essentiel, avec fallback legacy
  `perspective_count + 1`.
- [x] Basculer toutes les copies mobiles sur `coverage_count`, sans utiliser
  `source_count`.
- [x] Afficher les biais connus de gauche à droite, puis un séparateur vertical
  « Autres sources » et toutes les sources inconnues.
- [x] Retirer la limite de huit cartes et virtualiser le carrousel.
- [x] Ajouter les tests d'invariant, de déduplication, de fallback et d'UI.

## Fichiers concernés

- `packages/api/app/services/perspective_service.py`
- `packages/api/app/services/editorial/pipeline.py`
- `packages/api/app/services/editorial/schemas.py`
- `packages/api/app/routers/contents.py`
- `packages/api/app/schemas/digest.py`
- `packages/api/app/schemas/essentiel.py`
- `packages/api/app/services/digest_service.py`
- `packages/api/app/services/essentiel_service.py`
- `apps/mobile/lib/features/digest/models/digest_models.dart`
- `apps/mobile/lib/features/flux_continu/models/flux_continu_models.dart`
- `apps/mobile/lib/features/feed/repositories/feed_repository.dart`
- `apps/mobile/lib/features/feed/widgets/perspectives_bottom_sheet.dart`
- `apps/mobile/lib/features/feed/widgets/coverage_comparison_card.dart`
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart`

## Notes

`source_count` reste dans les payloads pour le ranking et la rétrocompatibilité,
mais ne doit plus piloter une copy de couverture. `perspective_count` est gardé
temporairement pour les anciens clients. Les snapshots restent dans le JSONB de
`daily_digests.items`.

Validation ciblée : 75 tests backend, 106 tests mobile, `ruff check`,
`compileall` et analyse Flutter sans erreur. Les tests d'intégration PostgreSQL
locaux restent dépendants de l'instance de test.
