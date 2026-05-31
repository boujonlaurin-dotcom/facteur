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
      expect(find.text('Tout lire (+4)'), findsOneWidget);
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

      // hiddenCount = 0 → label falls back to "Tout lire" (no suffix).
      expect(find.text('Tout lire'), findsOneWidget);
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

  group('SectionBlock — Footer Row', () {
    testWidgets('"Tout lire" button spans the full footer width', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      final voirPlus = find.byType(SeeAllSectionButton);
      expect(voirPlus, findsOneWidget);

      // With the "Section suivante" CTA removed, the footer renders the
      // overflow button alone — it should take (nearly) the full content
      // width inside its 12px horizontal padding.
      final footerWidth = tester.getSize(find.byType(SingleChildScrollView)).width;
      final buttonWidth = tester.getSize(voirPlus).width;
      expect(
        buttonWidth > footerWidth - 40,
        isTrue,
        reason: '"Tout lire" doit occuper toute la largeur du footer. '
            'Got button=$buttonWidth footer=$footerWidth.',
      );
    });
  });
}
