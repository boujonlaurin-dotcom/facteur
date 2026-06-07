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
library;

// ── Regular section (banner + N article cards + « Tout lire » footer) ─────────

/// Realistic height (px) of one regular article card
/// ([FluxContinuArticleCard]). The 78px thumbnail **floors the head row**, so a
/// typical ≤3-line title is dominated by the thumb, not the text — modelling the
/// 4-line worst case (the old 164) over-cut articles and left screens too empty.
/// Breakdown: outer padding (0+12) + inner padding (14+14) + thumb-floored head
/// row 78 + gap 10 + footer row ≈ 20 = 148. A rare 4-line title spills a few px
/// past this; the runtime snap net (`[fit-net]`) flags it if it ever does.
const double kRegularCardHeight = 148;

/// Banner height (px) for a section **without** a blurb (theme / source):
/// `minHeight 60` + vertical margin (3+5).
const double kBannerHeightNoBlurb = 68;

/// Banner height (px) for a section **with** a blurb (Actus du jour, Bonnes
/// Nouvelles, veille): `minHeight 92` + vertical margin (3+5).
const double kBannerHeightWithBlurb = 100;

/// Footer height (px): the always-present "Tout lire (+N)" CTA (≈54) plus the
/// section's trailing 16px gap.
const double kSectionFooterHeight = 70;

// ── Hero card (« Ton Essentiel » — lead + up to 4 mediums) ────────────────────

/// Non-tile chrome of the hi-fi hero card (px): card margins (8+16) + container
/// padding (12+12, post-compaction) + the fixed 132px date/weather badge slot
/// that drives the header height (kept per PO) + header→lead gap (12,
/// post-compaction) + the SectionBlock trailing 16px gap.
const double kHeroChromeHeight = 208;

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

/// Conservative height of one regular article card. Exposed as a function (not
/// just the constant) so call sites read intent and a future per-card refinement
/// has a single seam.
double estimateRegularCardHeight() => kRegularCardHeight;

/// Largest article count in `[minCount, maxCount]` whose stack
/// (`bannerHeight + count·cardHeight + footerHeight`) fits within
/// [usableHeight]. **Never returns 0** — a section always shows at least
/// [minCount] card even when nothing fits (the snap then treats it as a tall
/// section and the QA net flags it). [maxCount] is the section's default cap
/// kept as a **ceiling**: fit can only reduce it, never grow it.
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
