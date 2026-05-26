import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/widgets/flux_continu_article_card.dart';
import 'package:facteur/features/flux_continu/widgets/plus_de_button.dart';
import 'package:facteur/features/flux_continu/widgets/section_block.dart';
import 'package:facteur/features/sources/models/source_model.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Content _content(String id) {
  return Content(
    id: id,
    title: 'title-$id',
    url: 'https://x.test/$id',
    contentType: ContentType.article,
    publishedAt: DateTime(2026, 1, 1),
    source: Source(id: 's', name: 'S', type: SourceType.article),
  );
}

DigestTopicSection _digestTopicSection({
  int topics = 5,
  int coreVisibleCount = 3,
}) {
  return DigestTopicSection(
    kind: SectionKind.bonnes,
    label: 'Actus du jour',
    accent: const Color(0xFFD35400),
    coreVisibleCount: coreVisibleCount,
    topics: List.generate(
      topics,
      (i) => DigestTopic(
        topicId: 't$i',
        label: 'Topic $i',
        articles: [DigestItem(contentId: 'c$i', title: 'A$i')],
      ),
    ),
  );
}

FeedThemeSection _themeSection({
  int items = 7,
  int coreVisibleCount = 3,
  bool hasMore = false,
}) {
  return FeedThemeSection(
    kind: SectionKind.theme,
    label: 'Tech',
    accent: const Color(0xFF2C3E50),
    coreVisibleCount: coreVisibleCount,
    themeSlug: 'tech',
    items: List.generate(items, (i) => _content('c$i')),
    hasMore: hasMore,
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('SectionBlock — coreVisibleCount slice', () {
    testWidgets(
        'FeedThemeSection renders only coreVisibleCount cards when closed',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      expect(find.byType(FluxContinuArticleCard), findsNWidgets(3));
    });

    testWidgets(
        'SeeAllSectionButton label uses (+N) where N = totalCount - '
        'coreVisibleCount', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      // 7 items - 3 visible = +4 hidden.
      expect(find.text('Lire plus (+4)'), findsOneWidget);
    });

    testWidgets(
        'SeeAllSectionButton hidden when nothing left to show (no overflow, '
        'no hasMore)', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 2, coreVisibleCount: 3),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      expect(find.byType(SeeAllSectionButton), findsNothing);
    });

    testWidgets(
        'SeeAllSectionButton appears with hasMore-suffix when backend has '
        'more pages even if coreVisibleCount exhausts the local items',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 3, coreVisibleCount: 3, hasMore: true),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      // hiddenCount = 0 → label falls back to "Lire plus" (no suffix).
      expect(find.text('Lire plus'), findsOneWidget);
    });
  });

  group('SectionBlock — DigestTopicSection CTA', () {
    testWidgets(
        'DigestTopicSection with onSeeAll uses SeeAllSectionButton (→) instead '
        'of PlusDeButton (↓)', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _digestTopicSection(topics: 5, coreVisibleCount: 3),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      expect(find.byType(SeeAllSectionButton), findsOneWidget);
      expect(find.byType(PlusDeButton), findsNothing);
    });
  });

  group('SectionBlock — Sujet suivant button', () {
    testWidgets('renders the button when onNextSection is provided',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
          onNextSection: () {},
        ),
      ));

      expect(find.byType(NextSectionButton), findsOneWidget);
      expect(find.text('Section suivante'), findsOneWidget);
    });

    testWidgets('hides the button when onNextSection is null', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
          // onNextSection deliberately omitted (null)
        ),
      ));

      expect(find.byType(NextSectionButton), findsNothing);
    });

    testWidgets('switches to "Passé" non-interactive state when '
        'isMarkedForNextSession is true', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
          isMarkedForNextSession: true,
          onNextSection: () => taps++,
        ),
      ));

      expect(find.text('Passé'), findsOneWidget);
      expect(find.text('Section suivante'), findsNothing);

      // Tap should be a no-op (parent passes onTap=null when already marked).
      await tester.tap(find.byType(NextSectionButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('uses arrow_downward when not marked', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
          onNextSection: () {},
        ),
      ));

      final iconInNext = find.descendant(
        of: find.byType(NextSectionButton),
        matching: find.byIcon(Icons.arrow_downward),
      );
      expect(iconInNext, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NextSectionButton),
          matching: find.byIcon(Icons.arrow_forward),
        ),
        findsNothing,
      );
    });

    testWidgets('Passé state has neutral grey background + green check_circle',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
          isMarkedForNextSession: true,
          onNextSection: () {},
        ),
      ));

      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(NextSectionButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(
        decoration.color,
        FacteurPalettes.light.textPrimary.withValues(alpha: 0.05),
      );
      expect(
        find.descendant(
          of: find.byType(NextSectionButton),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'optimistic flip: tap shows "Passé" + neutral grey background on the '
        'next frame even when isMarkedForNextSession stays false',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
          isMarkedForNextSession: false,
          onNextSection: () {},
        ),
      ));
      expect(find.text('Section suivante'), findsOneWidget);

      await tester.tap(find.byType(NextSectionButton));
      await tester.pump();

      expect(find.text('Passé'), findsOneWidget);
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(NextSectionButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        (container.decoration as BoxDecoration).color,
        FacteurPalettes.light.textPrimary.withValues(alpha: 0.05),
      );
    });
  });

  group('SectionBlock — Footer Row', () {
    testWidgets('wraps Lire plus and Section suivante in the same Row',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
          onNextSection: () {},
        ),
      ));

      final voirPlus = find.byType(SeeAllSectionButton);
      final sujetSuivant = find.byType(NextSectionButton);
      expect(voirPlus, findsOneWidget);
      expect(sujetSuivant, findsOneWidget);

      // Both buttons must share a Row ancestor (the footer row).
      final voirPlusRows =
          find.ancestor(of: voirPlus, matching: find.byType(Row));
      final sujetRows =
          find.ancestor(of: sujetSuivant, matching: find.byType(Row));
      final voirPlusRowSet =
          tester.widgetList<Row>(voirPlusRows).toSet();
      final sujetRowSet = tester.widgetList<Row>(sujetRows).toSet();
      final shared = voirPlusRowSet.intersection(sujetRowSet);
      expect(shared, isNotEmpty,
          reason: 'Lire plus and Section suivante must share a Row ancestor.');

      // Lire plus sits to the left of Section suivante.
      final voirPlusLeft = tester.getTopLeft(voirPlus).dx;
      final sujetLeft = tester.getTopLeft(sujetSuivant).dx;
      expect(voirPlusLeft < sujetLeft, isTrue);

      // 1:1 ratio — both buttons must have roughly the same width
      // (flex 1 / flex 1 in _SectionFooterRow). Allow a small delta to
      // account for sub-pixel rounding on different DPRs.
      final leftWidth = tester.getSize(voirPlus).width;
      final rightWidth = tester.getSize(sujetSuivant).width;
      expect(
        (leftWidth - rightWidth).abs() < 2.0,
        isTrue,
        reason:
            'Lire plus et Section suivante doivent avoir des largeurs égales '
            '(flex 1/1). Got left=$leftWidth right=$rightWidth.',
      );
    });

    testWidgets('tap fires onNextSection exactly once when not marked',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
          onNextSection: () => taps++,
        ),
      ));

      await tester.tap(find.byType(NextSectionButton));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
