# fix(perspectives): aligner la couverture médiatique sur les sources réellement disponibles

## Contexte

Bug P1 : une carte pouvait annoncer « 14 sources » alors que le reader ne
proposait qu'un seul autre média. Le compteur visible mélangeait quatre notions
distinctes :

- `source_count` : nombre de domaines du cluster, **signal de ranking** ;
- `perspective_count` : compteur partiel des alternatives, filtré par biais ;
- `response.perspectives.length` : ce qui est réellement consultable ;
- `coverageCount` mobile : `max(source_count, perspective_count)`, qui masquait
  l'écart.

Cause racine : `source_count` était exposé comme un compteur de couverture, et le
pipeline ne persistait que les perspectives au biais connu. Les médias au biais
`unknown` disparaissaient donc du snapshot sans pouvoir être ouverts.

Doc : `docs/bugs/bug-couverture-medias-disponibles.md`.

## Invariant public introduit

`coverage_count` = nombre total de domaines éditoriaux couvrant le même sujet,
**média courant inclus**. Pour tout article de ce snapshot,
`GET /contents/{id}/perspectives` renvoie exactement `coverage_count - 1` autres
domaines.

Les sources au biais `unknown` comptent et restent consultables ; elles sont
exclues uniquement de `bias_distribution`, du niveau de polarisation et des
visualisations politiques.

## Ce que fait la PR

**Backend**

- `PerspectiveService.build_coverage_universe()` : univers commun pivot + cluster
  + résultats internes/Google News, passé au filtre de cohérence thématique déjà
  utilisé par la recherche interne, dédupliqué **par domaine**, avec les biais
  `unknown` conservés. Les agrégateurs sans production éditoriale (Reddit, Google
  News, hosts listicle) sont écartés.
- `perspective_to_dict()` devient la forme sérialisée unique, partagée entre le
  snapshot du pipeline et la réponse live du routeur : un champ ajouté arrive des
  deux côtés d'un coup.
- Persistance dans le JSONB existant : `coverage_count`, `coverage_articles`
  (pivot inclus) et `coverage_sources`. **Aucune migration Alembic.**
- `GET /contents/{id}/perspectives` retire **tout le domaine** actuellement lu
  (plus seulement son URL) et renvoie `coverage_count` avec la liste.
- Contrats Digest et Essentiel : ajout de `coverage_count` et `coverage_sources`,
  avec fallback legacy `perspective_count + 1` (jamais `source_count`).
- Logs structurés : candidats, rejets hors sujet, doublons de domaine, sources
  connues/inconnues, et `invariant_ok` sur les trois chemins (pipeline, live,
  snapshot).

**Mobile**

- Toutes les surfaces visibles passent sur `coverageCount` : cartes, « À la une »,
  badge « Couvert par N sources », Essentiel, triage, CTA d'analyse et reader. Le
  seuil multi-source devient `coverage_count >= 2`.
- Les anciens caches Hive retombent sur `perspectiveCount + 1` ; `source_count`
  ne pilote plus aucune copy visible.
- Carrousel : biais connus de gauche à droite, puis un séparateur vertical
  « Autres sources » et toutes les sources inconnues. Leurs cartes n'affichent ni
  point politique ni `?`, mais gardent source, fiabilité et date.
- Fin de la limite de huit cartes : `ListView.builder` virtualisé (les
  `RepaintBoundary` explicites disparaissent, `addRepaintBoundaries` les fournit).
  Le tap sur la barre de biais tient compte du séparateur.
- `EssentielArticle.copyWith` remplace une reconstruction manuelle qui perdait
  silencieusement des champs au passage « lu » (couverture, chapô, fiabilité).

## Rétrocompatibilité

`source_count` et `perspective_count` restent dans les payloads (ranking et
anciens clients). Les snapshots restent dans le JSONB de `daily_digests.items` :
pas de DDL, donc rien à étaler sur deux cycles hebdo.

## Tests

- Backend : univers de 14 domaines dont un seul biais connu, chacun des 14
  articles obtenant exactement 13 alternatives ; rejet des hors-sujet, des
  doublons de domaine et des agrégateurs ; snapshot complet retrouvé depuis
  n'importe quel `content_id` membre ; fallback legacy sur les anciens digests ;
  normalisation de domaine.
- Mobile : `coverage_count` explicite gagne sur la longueur des alternatives ;
  payload legacy `source_count=14`, `perspective_count=1` affiche `2` ; snapshot
  Hive sans les champs parse en défauts ; carrousel > 8 cartes consultable dans la
  liste virtualisée ; séparateur présent/absent/groupe entièrement `unknown` ;
  aucune puce politique sur une source inconnue.
- Suites complètes vertes : `pytest` (3110 passed), `flutter test` (baseline
  inchangée), `ruff check`/`ruff format` sur `app/`, `flutter analyze` sans erreur.
