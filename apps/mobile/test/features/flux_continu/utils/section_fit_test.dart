import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/flux_continu/utils/section_fit.dart';

void main() {
  group('fitVisibleCount', () {
    // Section chrome = banner + footer. With the no-blurb banner that is
    // 68 + 58 = 126 px of fixed chrome, then each card is 146 px.
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
      // 126 + 2·146 = 418 fits, 126 + 3·146 = 564 does not.
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
      // no-blurb: 126 + 3·146 = 564 ; with-blurb: 158 + 3·146 = 596.
      const usable = 590.0;
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
}
