import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/flux_continu/utils/section_fit.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';

void main() {
  group('fitVisibleCount', () {
    // Section chrome = banner + footer. With the no-blurb banner that is
    // 54 + 16 = 70 px of fixed chrome, then each card is 146 px.
    const banner = kBannerHeightNoBlurb;
    const footer = kSectionFooterHeight;
    final card = estimateRegularCardHeight();

    int fit(double usable, {int maxCount = 3, int minCount = 1}) =>
        fitVisibleCount(
          usableHeight: usable,
          bannerHeight: banner,
          footerHeight: footer,
          cardHeight: card,
          maxCount: maxCount,
          minCount: minCount,
        );

    test('a tall screen fits the full default cap (3)', () {
      expect(fit(2000), 3);
    });

    test('a mid screen drops to 2', () {
      // 70 + 2·146 = 362 fits, 70 + 3·146 = 508 does not.
      expect(fit(500), 2);
    });

    test('a small screen floors to 1 — never 0', () {
      // Budget for cards is positive but below one card height.
      expect(fit(200), 1);
    });

    test('a degenerate (≤ chrome) budget still returns minCount, never 0', () {
      expect(fit(50), 1);
      expect(fit(50, minCount: 2), 2);
    });

    test('the default cap is a ceiling — fit never grows past maxCount', () {
      expect(fit(5000, maxCount: 4), 4);
      expect(fit(5000, maxCount: 2), 2);
    });

    test('minCount is honoured on a cramped screen', () {
      expect(fit(200, maxCount: 3, minCount: 2), 2);
    });

    test('a blurb banner reserves more chrome, so it can fit fewer cards', () {
      // Same usable height, the with-blurb banner (82) leaves 28 px less.
      // Pick a height where the extra 28 px tips 3 → 2.
      // no-blurb: 70 + 3·146 = 508 ; with-blurb: 98 + 3·146 = 536.
      const usable = 520.0;
      final noBlurb = fitVisibleCount(
        usableHeight: usable,
        bannerHeight: kBannerHeightNoBlurb,
        footerHeight: footer,
        cardHeight: card,
        maxCount: 3,
      );
      final withBlurb = fitVisibleCount(
        usableHeight: usable,
        bannerHeight: kBannerHeightWithBlurb,
        footerHeight: footer,
        cardHeight: card,
        maxCount: 3,
      );
      expect(noBlurb, 3);
      expect(withBlurb, 2);
    });
  });

  group('fitHeroCount', () {
    int fit(double usable, {int maxCount = 5, int minCount = 1}) =>
        fitHeroCount(
          usableHeight: usable,
          chromeHeight: kHeroChromeHeight,
          leadHeight: kHeroLeadHeight,
          mediumHeight: kHeroMediumHeight,
          maxCount: maxCount,
          minCount: minCount,
        );

    test('a tall screen keeps the full pool (capped by maxCount)', () {
      expect(fit(2000, maxCount: 5), 5);
      expect(fit(2000, maxCount: 3), 3);
    });

    test('a mid screen keeps the lead + one medium (2)', () {
      // chrome 196 + lead 160 = 356 ; one medium = 88.
      // 356 + 88 = 444 fits, 356 + 2·88 = 532 does not.
      expect(fit(500), 2);
    });

    test('a small screen keeps the lead alone — never 0', () {
      // Below chrome + lead (356) there is no room for any medium.
      expect(fit(360), 1);
      expect(fit(100), 1);
    });

    test('the lead is mandatory even when maxCount is 1', () {
      expect(fit(2000, maxCount: 1), 1);
      expect(fit(50, maxCount: 1), 1);
    });

    test('result never exceeds maxCount (= min(5, articles.length))', () {
      expect(fit(5000, maxCount: 2), 2);
      expect(fit(5000, maxCount: 4), 4);
    });
  });

  group('display modes', () {
    test('estimateRegularCardHeight defaults to the normal mode constant', () {
      expect(estimateRegularCardHeight(), kRegularCardHeight);
      expect(
        estimateRegularCardHeight(DisplayModeSpec.normal),
        kRegularCardHeight,
      );
    });

    int fitFor(DisplayModeSpec spec, double usable, {int maxCount = 5}) =>
        fitVisibleCount(
          usableHeight: usable,
          bannerHeight: kBannerHeightNoBlurb,
          footerHeight: kSectionFooterHeight,
          cardHeight: estimateRegularCardHeight(spec),
          maxCount: maxCount,
        );

    test('at equal viewport, minimal fits ≥ normal and playful fits ≤', () {
      for (final usable in [400.0, 600.0, 800.0, 1000.0]) {
        final minimal = fitFor(DisplayModeSpec.minimal, usable);
        final normal = fitFor(DisplayModeSpec.normal, usable);
        final playful = fitFor(DisplayModeSpec.playful, usable);
        expect(minimal, greaterThanOrEqualTo(normal), reason: 'usable=$usable');
        expect(playful, lessThanOrEqualTo(normal), reason: 'usable=$usable');
      }
    });

    test(
        'chaque mode porte son plafond de fit : normal 4, minimal 6, '
        'ludique 3', () {
      expect(DisplayModeSpec.normal.sectionFitCeiling, 4);
      expect(DisplayModeSpec.minimal.sectionFitCeiling, 6);
      expect(DisplayModeSpec.playful.sectionFitCeiling, 3);
    });

    // Réplique le calcul du provider `_capSectionToFit` :
    // maxCount = max(1, min(ceiling, totalCount)) ; minCount soft (1).
    int fitForMode(DisplayModeSpec spec, double usable, {int totalCount = 10}) {
      final ceiling = spec.sectionFitCeiling!;
      final maxCount =
          (ceiling < totalCount ? ceiling : totalCount).clamp(1, 1 << 30);
      return fitVisibleCount(
        usableHeight: usable,
        bannerHeight: kBannerHeightNoBlurb,
        footerHeight: kSectionFooterHeight,
        cardHeight: estimateRegularCardHeight(spec),
        maxCount: maxCount,
      );
    }

    test(
        'minimal : le fit MONTE jusqu\'au plafond 6 selon le viewport '
        '(cible 4-6)', () {
      // Chrome 70 + N·126 : 4 cartes = 574, 5 = 700, 6 = 826.
      expect(fitForMode(DisplayModeSpec.minimal, 600), 4);
      expect(fitForMode(DisplayModeSpec.minimal, 720), 5);
      // Écran géant : plafonné à 6 (et non 7+).
      expect(fitForMode(DisplayModeSpec.minimal, 1000), 6);
      // Le pool réel borne la montée (min(ceiling, totalCount)).
      expect(fitForMode(DisplayModeSpec.minimal, 1000, totalCount: 4), 4);
      // Petit écran : le fit redescend (plancher soft 1).
      expect(fitForMode(DisplayModeSpec.minimal, 300), 1);
    });

    test('normal : grandit jusqu\'à 4 quand l\'écran le permet (cible 3-4)',
        () {
      // Chrome 70 + N·146 : 3 = 508, 4 = 654.
      expect(fitForMode(DisplayModeSpec.normal, 600), 3);
      expect(fitForMode(DisplayModeSpec.normal, 700), 4);
      // Plafonné à 4 même sur écran géant.
      expect(fitForMode(DisplayModeSpec.normal, 5000), 4);
    });

    test('ludique : 2-3 cartes selon le viewport, plafonné à 3', () {
      // Chrome 70 + N·272 : 2 = 614, 3 = 886.
      expect(fitForMode(DisplayModeSpec.playful, 640), 2);
      expect(fitForMode(DisplayModeSpec.playful, 920), 3);
      // Plafonné à 3 même sur écran géant.
      expect(fitForMode(DisplayModeSpec.playful, 5000), 3);
    });

    test('hero fit follows the same ordering with mode heights', () {
      int heroFor(DisplayModeSpec spec) => fitHeroCount(
            usableHeight: 620,
            chromeHeight: kHeroChromeHeight,
            leadHeight: spec.heroLeadHeight,
            mediumHeight: spec.heroMediumHeight,
            maxCount: 5,
          );
      expect(heroFor(DisplayModeSpec.minimal),
          greaterThanOrEqualTo(heroFor(DisplayModeSpec.normal)));
      expect(heroFor(DisplayModeSpec.playful),
          lessThanOrEqualTo(heroFor(DisplayModeSpec.normal)));
    });
  });
}
