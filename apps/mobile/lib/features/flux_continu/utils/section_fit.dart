/// Pure, unit-testable height-budget estimator deciding **how many articles a
/// Flux Continu section may show so its rendered stack never exceeds the usable
/// viewport** — the data-layer half of « estimer pour contrôler, mesurer pour
/// vérifier ». Calqué sur `section_snap.dart` : arithmétique seule, aucun
/// binding Flutter, donc testable sans le bootstrap Hive/Supabase du widget
/// suite.
///
/// Conservative by design: every estimate assumes each title at its `maxLines`
/// ceiling, so the function needs **one** input from the layout (the usable
/// height) — no width, no font measurement. Consequence accepted by the PO: on
/// a very small screen a section can drop to 2 (or 1); on a normal phone 3
/// always holds. The runtime measure (`_recomputeSnapAnchors` / `_tallSections`)
/// then confirms in QA that no card overflows — if the estimate is too strict
/// (hides the 3rd when there was room) the constants below are the knobs to
/// tune, never the call sites.
///
/// **Budget identique au snap** (sinon estimation et mesure divergent) :
/// ```
/// usableHeight = scrollViewportHeight − safeAreaBottom − kStickyBarHeight
/// ```
/// (cf. `_recomputeSnapAnchors` : une section est « tall » exactement quand sa
/// hauteur dépasse cette même valeur.)
/// Les hauteurs de cartes dépendent du mode d'affichage choisi par
/// l'utilisateur : elles vivent dans [DisplayModeSpec] (normal = les
/// constantes historiques ci-dessous, conservées pour les tests et comme
/// documentation de la décomposition).
library;

import '../../settings/models/display_mode_spec.dart';

// ── Regular section (banner + N article cards + trailing gap) ────────────────

/// Realistic height (px) of one regular article card
/// ([FluxContinuArticleCard]). The 78px thumbnail **floors the head row**, so a
/// typical ≤3-line title is dominated by the thumb, not the text — modelling the
/// 4-line worst case (the old 164) over-cut articles and left screens too empty.
/// Breakdown: outer padding (0+12) + inner padding (14+14) + thumb-floored head
/// row 78 + gap 10 + footer row ≈ 20 = 148. A rare 4-line title spills a few px
/// past this; the runtime snap net (`[fit-net]`) flags it if it ever does.
/// Réglé au plancher réel mesuré (146) pour fitter 3 cartes plus souvent.
const double kRegularCardHeight = 146;

/// Crédit (px) de la marge basse de la **dernière** carte d'une section. Chaque
/// carte régulière réserve [kRegularCardHeight] px **dont 12px de marge basse**
/// (`FluxContinuArticleCard` : `Padding.fromLTRB(12, 0, 12, 12)`). La marge basse
/// de la *dernière* carte visible n'a aucun contenu — c'est de l'espace blanc qui
/// peut passer sous le pli sans rien tronquer. On la crédite **une seule fois** au
/// budget de fit pour ne pas amputer une section à N−1 cartes alors qu'une Nᵉ tient
/// à 12px près (symptôme : « 3 cartes alors qu'il y a la place pour 4 »). N'élargit
/// jamais le budget au point de tronquer du contenu réel.
const double kLastCardBottomMargin = 12;

/// Banner height (px) for a section **without** a blurb (theme / source):
/// `minHeight 46` + vertical margin (2+4). Post-compaction (banner moins
/// proéminent), le `minHeight` a été relevé 40 → 46 pour aérer le tiret
/// d'accent en haut de section — doit matcher la hauteur rendue par
/// `SectionBanner` sinon le fit ne profite pas du gain de place.
const double kBannerHeightNoBlurb = 52;

/// Banner height (px) for a section **with** a blurb (Actus du jour, Bonnes
/// Nouvelles, veille): `minHeight 70` + vertical margin (2+4). Post-compaction.
const double kBannerHeightWithBlurb = 76;

/// Footer height (px): le CTA « Tout lire » a disparu (le banner de section
/// est devenu cliquable) — il ne reste que le spacing de fin de section
/// (SizedBox 16 du SectionBlock).
const double kSectionFooterHeight = 16;

/// Hauteur réelle (px) réservée par le footer discret « Tout lire › »
/// (`SectionBlock._seeAllFooter`) rendu en pied des sections **sans** footer
/// d'ajout de sources (Actus du jour, sources non vides). `TextButton` compact
/// (`minimumSize` (0, 32)) + marge basse ≈ 36. Doit être **retirée du budget de
/// fit** : contrairement au gap de fin de section, ce footer porte du contenu
/// (bouton cliquable) sous les cartes → `_recomputeSnapAnchors` le mesure
/// (`box.size.height`), donc l'estimation doit l'anticiper sous peine de bascule
/// *tall* parasite. Resserré (était 36) après rapprochement du CTA de sa
/// section (`minimumSize` 32→28 + marge haute −6, marge basse 2).
const double kSeeAllFooterHeight = 28;

/// Hauteur réelle (px) réservée par le footer replié « Ajouter plus de sources »
/// (`EtofferThemeFooter._collapsedButton`) en pied d'un thème riche : bouton
/// compact (`minimumSize` (0, 30)) + marge basse ≈ 40. Même raison que
/// [kSeeAllFooterHeight] : mesurée au runtime, donc réservée au fit.
const double kEtofferCollapsedFooterHeight = 40;

/// Plancher de plausibilité (px) du viewport utile mesuré. En dessous, la mesure
/// est considérée **non fiable** (mesure transitoire / render box détachée au
/// moment d'un changement de mode d'affichage ou d'une recompose hors-écran) :
/// le cap est court-circuité (cf. [usableHeight] == null) pour ne pas effondrer
/// toutes les sections à 1 carte. Même le plus petit téléphone (iPhone SE,
/// ~480px utiles dans le feed) reste largement au-dessus, donc le « cartes ≤
/// écran » légitime n'est pas affecté.
const double kMinPlausibleUsableHeight = 360;

/// Hauteur utile (px) de **secours** quand aucune mesure fiable n'est encore
/// disponible (1ᵉʳ frame avant la mesure post-layout, ou mesure transitoire
/// rejetée). On applique malgré tout un cap **dépendant du mode** sur cette
/// référence plutôt que de retomber sur le compte nominal backend (mode-aveugle :
/// déborde en Lisible, sous-remplit en Minimaliste). Valeur d'un téléphone
/// moderne typique → Normal 3 / Minimaliste 4 / Lisible 2, affinés dès l'arrivée
/// de la vraie mesure.
const double kReferenceUsableHeight = 640;

// ── Hero card (« Ton Essentiel » — lead + up to 4 mediums) ────────────────────

/// Non-tile chrome of the hi-fi hero card (px): card margins (8+16) + container
/// padding (12+12, post-compaction) + the fixed 132px date/weather badge slot
/// that drives the header height (kept per PO) + header→lead gap (12,
/// post-compaction) + the SectionBlock trailing 16px gap. Réduit (était 208)
/// après compaction du header (titre 18, tiret 24×2, paddings resserrés).
const double kHeroChromeHeight = 196;

/// Lead tile height (px), title at a **realistic 3-line height** (post-compaction)
/// rather than the 4-line worst case (the old 181, which over-cut the hero):
/// padding (12+12) + chips row ≈ 22 + gap 8 + title 3 lines (Fraunces 19 ·
/// height 1.3 ≈ 74) + gap 8 + source row ≈ 20 = 160.
const double kHeroLeadHeight = 160;

/// One medium tile height (px) **including its hairline separators**, title at a
/// **realistic 2-line height** (post-compaction) rather than the 3-line worst
/// case (the old 105): gaps 8+0.6+8 + tile (pad 4 + meta row 18 + gap 4 + title
/// 2 lines Fraunces 16 · height 1.3 ≈ 42) ≈ 88.
const double kHeroMediumHeight = 88;

/// Conservative height of one regular article card, for the user's current
/// display mode. Exposed as a function (not just the constant) so call sites
/// read intent and a future per-card refinement has a single seam.
double estimateRegularCardHeight([
  DisplayModeSpec spec = DisplayModeSpec.normal,
]) => spec.regularCardHeight;

/// Largest article count in `[minCount, maxCount]` whose stack
/// (`bannerHeight + count·cardHeight + footerHeight`) fits within
/// [usableHeight]. **Never returns 0** — a section always shows at least
/// [minCount] card even when nothing fits (the snap then treats it as a tall
/// section and the QA net flags it). [maxCount] is the **effective ceiling
/// decided by the caller** : historiquement le cap nominal de la section, mais
/// l'appelant peut le relever (mode minimaliste : `spec.sectionFitCeiling`)
/// pour que le fit révèle plus d'articles quand l'écran a de la place.
int fitVisibleCount({
  required double usableHeight,
  required double bannerHeight,
  required double footerHeight,
  required double cardHeight,
  required int maxCount,
  int minCount = 1,
}) {
  final lo = minCount < 1 ? 1 : minCount;
  if (maxCount <= lo) return lo;
  if (cardHeight <= 0) return lo;
  final budget = usableHeight - bannerHeight - footerHeight;
  if (budget <= 0) return lo;
  final fit = (budget / cardHeight).floor();
  return fit.clamp(lo, maxCount);
}

/// Hauteur (px) que le footer d'une section ajoute **réellement sous les
/// cartes** — donc à réserver dans le budget de fit pour que l'estimation
/// (`fitVisibleCount`) et la mesure runtime (`_recomputeSnapAnchors`, qui lit
/// `box.size.height` footer inclus) s'accordent. Sans cette réserve, une section
/// que le fit croit *courte* (footer ignoré) est mesurée *tall* (footer
/// compris) → un point de snap intermédiaire parasite se glisse et le scroll par
/// snaps se dérègle. Arithmétique pure côté section_fit ; la logique de *type*
/// (quel footer une section rend) reste côté provider, qui dérive les booléens.
///
/// - [isDigest] : Actus du jour → footer « Tout lire › » ([kSeeAllFooterHeight]).
/// - [isSourceNonEmpty] : section source avec articles → « Tout lire › ».
/// - [isRichThemeWithSlug] : thème riche (footer replié « Ajouter plus de
///   sources ») → [kEtofferCollapsedFooterHeight].
/// - Sinon (thème vide/maigre = footer déplié 0-1 carte, empty-states) → `0` :
///   la section est courte, le fit n'est pas contraignant.
double estimateSectionFooterReserve({
  required bool isDigest,
  required bool isSourceNonEmpty,
  required bool isRichThemeWithSlug,
}) {
  if (isDigest || isSourceNonEmpty) return kSeeAllFooterHeight;
  if (isRichThemeWithSlug) return kEtofferCollapsedFooterHeight;
  return 0;
}

/// Number of articles the hero card may show so it fits within [usableHeight].
/// The **lead is mandatory** (result ≥ 1, ≥ [minCount]); each additional
/// article is a medium tile. Capped by [maxCount] (typically
/// `min(5, articles.length)`). Ejected articles are dropped from the hero's
/// list **before** the inter-section dedup, so a downstream section carrying the
/// same `contentId` reclaims them automatically.
int fitHeroCount({
  required double usableHeight,
  required double chromeHeight,
  required double leadHeight,
  required double mediumHeight,
  required int maxCount,
  int minCount = 1,
}) {
  final lo = minCount < 1 ? 1 : minCount;
  if (maxCount <= 1) return 1;
  if (mediumHeight <= 0) return lo.clamp(1, maxCount);
  final budgetForMediums = usableHeight - chromeHeight - leadHeight;
  if (budgetForMediums <= 0) return lo.clamp(1, maxCount);
  final mediums = (budgetForMediums / mediumHeight).floor();
  final count = 1 + (mediums < 0 ? 0 : mediums);
  return count.clamp(lo.clamp(1, maxCount), maxCount);
}

// ── Pile de tri (« Ton Essentiel » triable au swipe — Story 33.1) ─────────────

/// Hauteur (px) du bandeau image en tête de la carte de tri, **quand l'article
/// porte une image**. Un article sans image ne replie pas le bandeau sur un
/// aplat de secours : il n'en rend aucun (décision PO « pas de placeholder ») et
/// la carte est simplement plus courte.
///
/// C'est la seule hauteur **figée** de la carte, et c'est ce qui borne sa
/// croissance : le reste (titre, méta) est du contenu, borné par `maxLines`.
///
/// Relevé 96 → 180 (itération PO 33.1 : « images trop petites ») : un vrai format
/// éditorial ~16:9 sur la largeur utile (~330px → 185, arrondi à 180). Le levier
/// de repli n'est plus « rétrécir » (96 → 80) mais « ne pas dépasser le
/// viewport » — tolérable depuis que la carte épouse son contenu (la kept-list
/// grandit sous la barre d'actions, via un `AnimatedSize` côté pile de tri),
/// donc une carte un peu haute pousse le feed vers le bas sans rien rogner.
const double kTriageCardImageHeight = 180;

/// Hauteur (px) d'une carte de tri **pleine** — bandeau image + titre long :
/// bandeau [kTriageCardImageHeight] 180 + padding haut 12 + méta source ≈ 16 +
/// gap 8 + titre 4 lignes (Fraunces 19 · height 1.3 = 98,8) + gap 8 + pied
/// (polarisation + couverture) ≈ 18 + padding bas 12 = 353, arrondi à 360. Le
/// chapô a disparu de la carte : à ce niveau de tri, l'image et la couverture
/// disent plus que deux lignes de description.
///
/// Depuis la reprise PO du 08/08, **la carte ne prend plus cette hauteur** : elle
/// épouse son contenu réel (un titre court ne laisse plus de blanc interne,
/// défaut « la carte ne s'adapte pas au contenu »). La constante ne sert donc
/// plus qu'à la **réserve du squelette** ([TriageStackSkeleton]) : à l'attente,
/// ni l'URL d'image ni la longueur du titre ne sont connues, et sur-réserver
/// fait *descendre* le contenu à l'hydratation plutôt que sauter la barre
/// d'actions sous le doigt.
const double kTriageCardHeight = 360;

/// Barre d'actions compacte (✕ · signet · bouton plein « Je garde ») :
/// bouton [kTriageActionButtonSize] + marges (10+10) = 64.
const double kTriageActionBarHeight = 64;

/// Côté des deux boutons ronds de la barre d'actions. Partagé entre la vraie
/// barre (`_ActionBar`) et sa silhouette (`TriageStackSkeleton`) : le défaut que
/// cette itération corrigeait était justement une attente qui annonçait une
/// barre inexistante, et re-transcrire les nombres à la main rouvrirait l'écart
/// au prochain ajustement.
const double kTriageActionButtonSize = 44;

/// Écart horizontal entre les éléments de la barre d'actions. Même raison de
/// partage que [kTriageActionButtonSize].
const double kTriageActionGap = 10;

/// Padding intérieur de la carte de tri, partagé avec sa silhouette pour la même
/// raison — et parce que ces deux valeurs entrent dans la décomposition de
/// [kTriageCardHeight].
const double kTriageCardPaddingH = 14;
const double kTriageCardPaddingV = 12;

/// Géométrie de la carte du **dessous** de la pile, au repos (avant toute
/// promotion). La vraie pile interpole de ces valeurs vers `1.0` au fil du
/// geste ; la silhouette les rend telles quelles, pour annoncer la géométrie
/// réelle.
const double kTriageBackCardScale = 0.96;
const double kTriageBackCardOpacity = 0.5;

/// Barre de progression, **segments seuls** : le segment en cours de décision
/// est épaissi (4 → 7 px), centré dans un slot de 14 (≈3,5 px de respiration de
/// part et d'autre). Elle porte seule l'avancement du tri : le compteur « N sur
/// M triés » a été retiré (décision PO), redondant avec les segments et avec la
/// liste des gardés juste en dessous. Rendue **sous la barre d'actions** depuis
/// la reprise PO du 08/08.
const double kTriageProgressHeight = 14;

/// Un article gardé dans la liste qui se construit sous la pile. Plus compact
/// qu'un medium ([kHeroMediumHeight]) : pas de hairline, titre sur 2 lignes
/// serrées ≈ 64.
///
/// Il n'y a **plus** de hauteur de pic à réserver pour la pile : la carte épouse
/// son contenu et la kept-list grandit *sous* la barre d'actions, donc rien ne
/// saute sous le doigt et le squelette n'a qu'à réserver la hauteur
/// d'ouverture (`progression + carte + barre d'actions`, composée directement
/// par `TriageStackSkeleton`). L'ancien `triageReservedHeight`, qui calculait ce
/// pic, n'avait plus d'appelant : il a été retiré plutôt que laissé en place
/// avec une doc qui se prétendait source de vérité.
const double kTriageKeptSlotHeight = 64;
