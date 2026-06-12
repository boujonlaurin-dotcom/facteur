import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/flux_continu/utils/section_fit.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';

void main() {
  group('fitVisibleCount', () {
    // Section chrome = banner + footer. With the no-blurb banner that is
    // 68 + 16 = 84 px of fixed chrome, then each card is 146 px.
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
      // 84 + 2·146 = 376 fits, 84 + 3·146 = 522 does not.
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
      // Same usable height, the with-blurb banner (100) leaves 32 px less.
      // Pick a height where the extra 32 px tips 3 → 2.
      // no-blurb: 84 + 3·146 = 522 ; with-blurb: 116 + 3·146 = 554.
      const usable = 540.0;
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
    int fit(double usable, {int maxCount = 5, int minCount = 1}) => fitHeroCount(
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
        expect(minimal, greaterThanOrEqualTo(normal),
            reason: 'usable=$usable');
        expect(playful, lessThanOrEqualTo(normal), reason: 'usable=$usable');
      }
    });

    test('sectionFitCeiling: null en normal/ludique (le nominal reste le '
        'plafond), 7 en minimaliste', () {
      expect(DisplayModeSpec.normal.sectionFitCeiling, isNull);
      expect(DisplayModeSpec.playful.sectionFitCeiling, isNull);
      expect(DisplayModeSpec.minimal.sectionFitCeiling, 7);
    });

    test(
        'minimal : le fit MONTE au-dessus du cap nominal (3) selon le '
        'viewport — +4/+5/+7 quand l\'écran le permet', () {
      // Réplique le calcul du provider : maxCount =
      // max(nominal, min(ceiling, totalCount)).
      int minimalFit(double usable, {int nominal = 3, int totalCount = 10}) {
        final ceiling = DisplayModeSpec.minimal.sectionFitCeiling!;
        final raised = ceiling < totalCount ? ceiling : totalCount;
        return fitVisibleCount(
          usableHeight: usable,
          bannerHeight: kBannerHeightNoBlurb,
          footerHeight: kSectionFooterHeight,
          cardHeight: estimateRegularCardHeight(DisplayModeSpec.minimal),
          maxCount: raised > nominal ? raised : nominal,
        );
      }

      // Chrome 84 + N·126 : 4 cartes = 588, 5 = 714, 7 = 966.
      expect(minimalFit(600), 4);
      expect(minimalFit(720), 5);
      expect(minimalFit(1000), 7);
      // Le pool réel borne la montée (min(ceiling, totalCount)).
      expect(minimalFit(1000, totalCount: 4), 4);
      // Petit écran : le fit redescend sous le nominal comme avant.
      expect(minimalFit(300), 1);
    });

    test('normal/ludique restent plafonnés au cap nominal même sur écran '
        'géant', () {
      for (final spec in [DisplayModeSpec.normal, DisplayModeSpec.playful]) {
        final fit = fitVisibleCount(
          usableHeight: 5000,
          bannerHeight: kBannerHeightNoBlurb,
          footerHeight: kSectionFooterHeight,
          cardHeight: estimateRegularCardHeight(spec),
          maxCount: 3,
        );
        expect(fit, 3);
      }
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
