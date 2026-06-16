/// Knobs visuels dérivés du mode d'affichage choisi par l'utilisateur
/// (Normal / Minimaliste / Ludique). **Point de vérité unique** : les cartes
/// d'articles ET l'estimateur de fit (`section_fit.dart`) lisent la même
/// instance — jamais de `if (mode == ...)` dispersés dans les widgets, et le
/// budget fit reste cohérent avec le rendu réel par construction.
///
/// Objet const pur (aucun import Flutter) pour rester testable sans le
/// bootstrap Hive/Supabase de la suite widget.
library;

class DisplayModeSpec {
  /// Affiche les vignettes/images d'articles. `false` en minimaliste.
  final bool showImages;

  /// Multiplicateur appliqué aux tailles de titre des cartes.
  final double fontScale;

  /// Paddings internes resserrés (minimaliste).
  final bool dense;

  /// Hauteur estimée (px) d'une carte régulière [FluxContinuArticleCard] pour
  /// le budget fit de l'Essentiel. Normal = `kRegularCardHeight` (146) ; les
  /// autres valeurs suivent la même décomposition (cf. section_fit.dart) avec
  /// thumb/typo du mode. Calibrées via le filet QA `[fit-net]`.
  final double regularCardHeight;

  /// Hauteur estimée (px) du lead tile du hero « Ton Essentiel ».
  final double heroLeadHeight;

  /// Hauteur estimée (px) d'un medium tile du hero (séparateurs inclus).
  final double heroMediumHeight;

  /// Delta appliqué au `maxLines` des titres du **hero** uniquement (ludique :
  /// -1, les titres plus gros gardant la même hauteur de bloc). Les cartes
  /// régulières lisent [regularTitleMaxLines].
  final int titleMaxLinesDelta;

  /// Plafond `maxLines` des titres de [FluxContinuArticleCard] : 4 normal,
  /// 5 minimal (plus de place sans thumb), 3 ludique (l'image domine).
  final int regularTitleMaxLines;

  /// Ludique : image pleine largeur en haut de carte (type carrousel), texte
  /// dessous. `false` = thumb carré à droite (layout historique).
  final bool imageOnTop;

  /// Hauteur **fixe** (px) de l'image header quand [imageOnTop]. Fixe plutôt
  /// que ratio : `fitVisibleCount` ne connaît pas la largeur — un ratio
  /// rendrait [regularCardHeight] faux selon le device.
  final double regularImageHeight;

  /// Plafond d'articles par section quand le fit a de la place : le fit peut
  /// **monter** au-dessus du cap nominal jusqu'à `min(ceiling, totalCount)`.
  /// `null` = le cap nominal reste le plafond (comportement historique).
  final int? sectionFitCeiling;

  /// Côté (px) du thumb carré de [FluxContinuArticleCard]. Ignoré quand
  /// [showImages] est false.
  final double thumbSize;

  /// Ratio de l'image header des FeedCard. `null` = ratio du call site
  /// (16/9 feed, 2.1 carrousel) ; ludique force 16/10 (image plus haute).
  final double? feedImageAspectRatio;

  const DisplayModeSpec({
    required this.showImages,
    required this.fontScale,
    required this.dense,
    required this.regularCardHeight,
    required this.heroLeadHeight,
    required this.heroMediumHeight,
    required this.titleMaxLinesDelta,
    required this.regularTitleMaxLines,
    required this.thumbSize,
    this.imageOnTop = false,
    this.regularImageHeight = 0,
    this.sectionFitCeiling,
    this.feedImageAspectRatio,
  });

  /// Rendu actuel — les hauteurs sont les constantes historiques de
  /// `section_fit.dart` (146 / 160 / 88). `sectionFitCeiling: 4` : le fit peut
  /// **monter** jusqu'à 4 articles/section quand l'écran a de la place (cible
  /// 3-4) au lieu de rester bloqué au nominal backend.
  static const normal = DisplayModeSpec(
    showImages: true,
    fontScale: 1.0,
    dense: false,
    regularCardHeight: 146,
    heroLeadHeight: 160,
    heroMediumHeight: 88,
    titleMaxLinesDelta: 0,
    regularTitleMaxLines: 4,
    thumbSize: 78,
    sectionFitCeiling: 4,
  );

  /// Texte seul, compact. Sans thumb le head row n'est plus flooré à 78px —
  /// le titre 3 lignes réalistes domine (18·0.9 · 1.3 · 3 ≈ 63) : 63 + gap 10
  /// + footer 20 + paddings dense (20) + marge externe 12 ≈ 126 (les titres
  /// peuvent monter à 5 lignes — plafond rare, le filet `[fit-net]` couvre).
  /// Hero : lead 3 lignes Fraunces 17.1 ≈ 67 (vs 74) → 153 ; medium 2 lignes
  /// ≈ 38 → 84. `sectionFitCeiling: 6` : le fit peut révéler jusqu'à 6
  /// articles/section quand l'écran a de la place (cible 4-6).
  static const minimal = DisplayModeSpec(
    showImages: false,
    fontScale: 0.9,
    dense: true,
    regularCardHeight: 126,
    heroLeadHeight: 153,
    heroMediumHeight: 84,
    titleMaxLinesDelta: 0,
    regularTitleMaxLines: 5,
    thumbSize: 0,
    sectionFitCeiling: 6,
  );

  /// Image élément principal : pleine largeur en haut de carte (130px fixes),
  /// texte dessous. `regularCardHeight` : image 130 + pad top 12 + titre
  /// 3 lignes (18·1.05 · 1.3 · 3 ≈ 74) + gap 10 + footer 20 + pad bottom 14 +
  /// marge externe 12 ≈ 272 — image volontairement plus basse que les 170px
  /// d'origine pour que 2-3 cartes tiennent sous le bandeau sans dépasser
  /// l'écran (la carte restait « image-forward »). Hero (inchangé
  /// structurellement) : lead 3 lignes Fraunces 19.95 ≈ 78 → 164 ; medium
  /// 2 lignes ≈ 44 → 90. `sectionFitCeiling: 3` : cible 2-3 articles/section.
  static const playful = DisplayModeSpec(
    showImages: true,
    fontScale: 1.05,
    dense: false,
    regularCardHeight: 272,
    heroLeadHeight: 164,
    heroMediumHeight: 90,
    titleMaxLinesDelta: -1,
    regularTitleMaxLines: 3,
    thumbSize: 0,
    imageOnTop: true,
    regularImageHeight: 130,
    feedImageAspectRatio: 16 / 10,
    sectionFitCeiling: 3,
  );
}
