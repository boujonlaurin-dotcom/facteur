## perf(reader) — isolation raster : cartes carrousel + chrome vertical (RepaintBoundary natif)

Regroupe **PR 1 + PR 2** du plan fluidité scroll (`.context/attachments/97Nbws/plan.md`) en une
seule PR, à la demande du PO. 100 % Dart mobile — aucun backend, aucune migration.

### Problème

`FacteurCard` n'isole ses cartes que via `webRepaintBoundary` (`core/web/web_perf.dart:52`),
**no-op hors web**. Sur natif, aucune carte du carrousel « comparaison de points de vue » n'était
donc isolée : tout le `Row` (≤ 8 cartes, chacune ombre `blurRadius: 6` + `DiffTitle` multi-span +
favicon) pouvait se re-rastériser à chaque frame de translation.

### Changements

**PR 1 — carrousel + nettoyage**
- `RepaintBoundary` explicite par carte + par CTA dans `_buildCarousel` (le vrai boundary, pas le
  helper web-only) → chaque carte = son layer, composité tel quel au scroll. Invisible.
- `RepaintBoundary` par squelette dans `_buildLoadingSkeleton` (isole le shimmer).
- `RepaintBoundary` autour des 2 `PerspectivesInlineSection` (N2) → isole les animations d'intro de
  la bande du corps vertical.
- Suppression de `_FadeScrollRow` (code mort, jamais instancié). −82 lignes.
- **Choix H1 (Row + RepaintBoundary) plutôt que H2 (ListView virtualisée)** : pour ≤ 8 cartes, la
  virtualisation rendrait `maxScrollExtent` estimé (casse le tap-to-scroll de la barre de biais) et
  introduirait des hitches de build en cours de scroll. H1 délivre le gain cœur sans ces risques.
  Détail dans `docs/maintenance/maintenance-reader-scroll-carrousel-repaint.md`.

**PR 2 — audit V1 + micro-fix**
- `RepaintBoundary` autour du `Transform.scale` du `_ctaPulseController` (N3). NB : pulse one-shot
  280 ms, pas une animation répétée.
- `PivotWashTitle` : key laissée telle quelle (rekey intentionnel qui pilote l'animation « wash » ;
  la toucher casserait l'anim sans gain mesuré).

### Vérification

- `flutter analyze` (fichiers touchés) : 0 nouvelle issue (warnings restants pré-existants).
- `flutter test` (perspectives `feed/widgets` + `detail`) : 0 nouvel échec. Les échecs restants
  (badge `scale: 1.6` vs test `1.0` ; phrase d'intro ; 4 stubs `notification_test`) sont
  **confirmés pré-existants via baseline HEAD**.
- ⚠️ **Profiling < 16 ms/frame = étape PO device** : le gain ne se mesure pas sur web (CanvasKit).
  À vérifier en `flutter run --profile` (long article + carrousel).

### Hors scope

PR 3 / V2 (virtualisation du corps `flutter_html`) — **le** levier pour le jank du corps des
articles sans carrousel — non inclus (risque plus élevé, casse `_measureArticleExtent`). À ouvrir si
le profiling montre encore > 16 ms/frame sur longs articles après ce lot.
