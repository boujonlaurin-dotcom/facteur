import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
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
      expect(find.text('Voir tout Tech (+4)'), findsOneWidget);
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

      // hiddenCount = 0 → label falls back to "Voir tout Tech" (no suffix).
      expect(find.text('Voir tout Tech'), findsOneWidget);
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
      expect(find.text('Sujet suivant'), findsOneWidget);
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

    testWidgets('switches to "Terminé" non-interactive state when '
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

      expect(find.text('Terminé'), findsOneWidget);
      expect(find.text('Sujet suivant'), findsNothing);
      expect(find.text('Lu'), findsNothing);

      // Tap should be a no-op.
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

    testWidgets('Terminé state has success background', (tester) async {
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
      expect(decoration.color, FacteurPalettes.light.success);
    });
  });

  group('SectionBlock — Footer Row', () {
    testWidgets('wraps Plus de… and Sujet suivant in the same Row',
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
          reason: 'Voir tout and Sujet suivant must share a Row ancestor.');

      // Voir tout sits to the left of Sujet suivant.
      final voirPlusLeft = tester.getTopLeft(voirPlus).dx;
      final sujetLeft = tester.getTopLeft(sujetSuivant).dx;
      expect(voirPlusLeft < sujetLeft, isTrue);
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
