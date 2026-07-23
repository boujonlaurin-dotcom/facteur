# Maintenance — Fluidité scroll readers : isolation raster (carrousel + chrome vertical)

> Type : Maintenance (perf). Surface : 100 % Dart mobile. Branche : `boujonlaurin-dotcom/reader-scroll-fluidity`.
> Regroupe **PR 1** (carrousel horizontal + nettoyage) **et PR 2** (audit V1 + micro-fix) du plan
> `.context/attachments/97Nbws/plan.md` en une seule PR, à la demande du PO.

## Contexte

Léger jank au scroll dans les readers, sous la barre de qualité :
- **Horizontal** — carrousel « comparaison de points de vue » (symptôme le plus aigu).
- **Vertical** — corps d'article + chrome (le PO confirme le jank sur des articles **sans** carrousel).

Acquis antérieurs : PR #962/#963 (blur au repos, cache offsets, dédup progression, barre sans
TweenAnimationBuilder, déferral WebView), PR #970 (BackdropFilter retiré). Le chrome vertical est
déjà propre en steady-state (header à hauteur constante, footer composité en `Transform.translate`,
progression via `ValueNotifier`+`RepaintBoundary`, pas de `setState` par frame).

## Insight central (vérifié dans le code)

`FacteurCard` n'isole ses cartes que via `webRepaintBoundary` /`webShadows`
(`core/web/web_perf.dart:52,37`), **no-op hors web** (`if (!kWebPerf) return child;`). Donc sur
iOS/Android natif **aucune** carte du carrousel n'était isolée : tout le `Row` (jusqu'à 8
`CoverageComparisonCard`, chacune avec ombre `blurRadius: 6` + `DiffTitle` multi-span + favicon)
pouvait se re-rastériser ensemble à chaque frame de translation. Le code *croyait* isoler les cartes,
mais seulement sur web.

## Changements

### PR 1 — Carrousel + nettoyage (`perspectives_bottom_sheet.dart`, `content_detail_screen.dart`)

1. **`RepaintBoundary` explicite par carte + par CTA** dans `_buildCarousel` (le vrai
   `RepaintBoundary`, pas le helper web-only). Chaque carte devient son propre layer, composité tel
   quel pendant le scroll → plus de re-raster du Row entier. `RepaintBoundary` est invisible → zéro
   impact visuel.
2. **`RepaintBoundary` par squelette** dans `_buildLoadingSkeleton` pour isoler le shimmer (animation
   continue) de son voisin.
3. **N2** — `RepaintBoundary` autour des deux `PerspectivesInlineSection` du reader
   (`content_detail_screen.dart`, chemin natif + chemin WebView) pour isoler les animations d'intro
   de la bande (`AnimatedOpacity`/`AnimatedSize`, fondu carrousel) du corps vertical au-dessus.
4. **Nettoyage** — suppression de `_FadeScrollRow` (code mort : classe définie, jamais instanciée ;
   le `ShaderMask`+`setState` par scroll qu'un agent avait pris pour une source de jank ne tournait
   pas). −82 lignes.

#### Décision : H1 (Row + RepaintBoundary) plutôt que H2 (ListView virtualisée)

Le plan proposait de remplacer `SingleChildScrollView`+`Row` par une `ListView.builder` horizontale
(H2, « superset » de H1). L'implémentation H2 a été écrite puis **écartée** après analyse : pour un
carrousel court (≤ 8 cartes), la virtualisation introduit deux régressions que H1 évite :

- **`maxScrollExtent` devient une *estimation*** tant que la liste n'a pas été défilée jusqu'au bout
  → `_onSpectrumSegmentTap` (tap sur la barre de biais) sous-scrollerait le segment le plus à droite.
  Le `Row` est layouté en entier → extent **exact** aujourd'hui.
- **Hitch de construction paresseuse** : une `ListView` construit/peint chaque carte quand elle entre
  dans le viewport → drop de frame *pendant* le scroll qu'on cherche justement à lisser.

H1 délivre le gain cœur (isolation par carte sur natif) avec **zéro risque comportemental et zéro
churn de test** (le `CrossAxisAlignment.stretch` du Row continue de borner la hauteur des cartes,
l'extent reste exact). Le culling lazy ne vaut ~rien pour 8 cartes et les layers `RepaintBoundary`
sont de toute façon réutilisés à la translation.

### PR 2 — Audit V1 + micro-fix (`content_detail_screen.dart`)

- **N3** — `RepaintBoundary` autour du `Transform.scale` animé par `_ctaPulseController`. NB : ce pulse
  est un **one-shot 280 ms** (`forward(from: 0)` au passage `_footerPermanent` → orange), **pas** une
  animation répétée pendant la lecture comme le supposait le plan. Le boundary confine son raster au
  bouton si le pulse coïncide avec un scroll.
- **`PivotWashTitle` : key laissée telle quelle.** Sa key (`ValueKey('article-title-wash-$_showPivot-
  ...pivot.start-...end')`) est rekeyée **intentionnellement** à l'arrivée de `_perspectivesResponse`
  pour relancer l'animation de « wash ». C'est une mutation **async** (one-time), pas du jank par
  frame de scroll. La « stabiliser » (suggestion conditionnelle du plan) casserait le déclencheur
  d'animation sans bénéfice mesuré → écarté.

## Vérification

- **`flutter analyze`** (fichiers touchés) : **0 nouvelle issue**. Les warnings/infos restants
  (`_maybeRequestReadOnSiteNudge` non référencé, 7 `unawaited_futures`) sont **pré-existants**, sur
  des lignes non modifiées.
- **`flutter test`** (suites `feed/widgets` perspectives + `detail`) : **0 nouvel échec**.
  Échecs restants tous **confirmés pré-existants via baseline HEAD** (worktree) :
  - `perspectives_inline_intro_test.dart` « badge à l'échelle 1.0 » : source hardcode `scale: 1.6`
    (`perspectives_bottom_sheet.dart:1985`), test attend `1.0` — non touché par ce diff.
  - `perspectives_bottom_sheet_intro_test.dart` « phrase d'intro présente » : échoue déjà sur HEAD.
  - `notification_test.dart` : 4 stubs `fail(...)` pré-existants (−4 constant).
- **Profiling (preuve du gain) : étape PO device.** Le gain perf **ne se mesure pas sur web**
  (CanvasKit). À faire en `flutter run --profile` overlay perf, viser **< 16 ms/frame**, sur un long
  article (The Conversation / Le Grand Continent) + le carrousel « comparaison de points de vue ».

## Hors scope (non inclus dans cette PR)

- **PR 3 / V2 — virtualisation du corps `flutter_html`.** C'est **le** levier pour le jank du *corps*
  des articles sans carrousel (rasterisation d'un seul arbre `flutter_html` très haut). Non engagé
  ici (risque plus élevé : casse `_measureArticleExtent` + le marqueur `_articleEndKey`, cf. N4 du
  plan). À ouvrir si le profiling on-device montre encore > 16 ms/frame sur longs articles après ce
  lot.
- **V3** (renderer maison / `flutter_widget_from_html_core`) — dernier recours.
- Activer `webRepaintBoundary`/`webShadows` sur mobile globalement (N1) — blast radius trop large ;
  on se limite au point chaud (carrousel).
