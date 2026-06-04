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
import 'package:facteur/features/sources/widgets/source_logo_avatar.dart';
import 'package:facteur/widgets/design/facteur_image.dart';

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

FeedThemeSection _sourceSection({
  int items = 3,
  String? logoUrl = 'https://logo.test/x.png',
}) {
  return FeedThemeSection(
    kind: SectionKind.source,
    label: 'Le Monde',
    accent: const Color(0xFF8E44AD),
    coreVisibleCount: 3,
    sourceId: 'src1',
    sourceLogoUrl: logoUrl,
    items: List.generate(items, (i) => _content('c$i')),
    hasMore: false,
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('SectionBlock — section source (PR Sources dans la Tournée)', () {
    testWidgets('hero rend le logo source (SourceLogoAvatar) avec les cartes',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _sourceSection(items: 3),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      // Logo source rendu dans le hero (pas d'illustration thème).
      expect(find.byType(SourceLogoAvatar), findsOneWidget);
      expect(find.byType(FacteurImage), findsOneWidget);
      expect(find.byType(FluxContinuArticleCard), findsNWidgets(3));
      // Le titre du hero = nom de la source.
      expect(find.text('Le Monde'), findsOneWidget);
    });

    testWidgets(
        'source sans article : état vide TOUJOURS visible + CTA curation',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _sourceSection(items: 0),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      // Aucune carte, mais la section reste rendue avec son état vide + CTA.
      expect(find.byType(FluxContinuArticleCard), findsNothing);
      expect(find.text('Voir toute la curation'), findsOneWidget);
      expect(find.byType(SourceLogoAvatar), findsOneWidget);
    });
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
        'SeeAllSectionButton ALWAYS shown for FeedThemeSection even when the '
        'section fits (no overflow, no hasMore) — deep-dive is the only route '
        'to carousels/Explorer/next-CTA', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 2, coreVisibleCount: 3),
          isOpen: false,
          onToggleMore: () {},
          onTapArticle: (_, __) {},
          onSeeAll: () {},
        ),
      ));

      // hiddenCount = 2 - 3 = -1 → clamped to 0 → label "Tout lire" (no suffix).
      expect(find.byType(SeeAllSectionButton), findsOneWidget);
      expect(find.text('Tout lire'), findsOneWidget);
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
