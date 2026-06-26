import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/widgets/flux_continu_article_card.dart';
import 'package:facteur/features/feed/widgets/feedback_inline.dart';
import 'package:facteur/features/flux_continu/widgets/section_banner.dart';
import 'package:facteur/features/flux_continu/widgets/section_block.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/models/theme_suggestions_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/widgets/source_logo_avatar.dart';
import 'package:facteur/widgets/design/facteur_image.dart';

Widget _wrap(
  Widget child, {
  DisplayModeSpec spec = DisplayModeSpec.normal,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    // Le spec du mode d'affichage est lu via Hive en prod — court-circuité ici
    // pour ne pas exiger le bootstrap Hive dans les widget tests. Les sections
    // thème rendent le footer « Étoffer » (cf. etofferThemeProvider) : on neutralise
    // l'appel réseau par défaut pour ne pas exiger Supabase.
    overrides: [
      displayModeSpecProvider.overrideWith((ref) => spec),
      etofferThemeProvider.overrideWith(
        (ref, slug) async =>
            ThemeSuggestions(theme: slug, label: 'Tech', suggestions: const []),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Content _content(String id, {String? thumbnailUrl}) {
  return Content(
    id: id,
    title: 'title-$id',
    url: 'https://x.test/$id',
    contentType: ContentType.article,
    publishedAt: DateTime(2026, 1, 1),
    thumbnailUrl: thumbnailUrl,
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
  bool withThumbnails = false,
}) {
  return FeedThemeSection(
    kind: SectionKind.theme,
    label: 'Tech',
    accent: const Color(0xFF2C3E50),
    coreVisibleCount: coreVisibleCount,
    themeSlug: 'tech',
    items: List.generate(
      items,
      (i) => _content(
        'c$i',
        thumbnailUrl: withThumbnails ? 'https://img.test/c$i.jpg' : null,
      ),
    ),
    hasMore: hasMore,
  );
}

FeedThemeSection _sourceSection({
  int items = 3,
  String? logoUrl = 'https://logo.test/x.png',
  bool noRecentSource = false,
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
    noRecentSource: noRecentSource,
  );
}

/// Finder du chevron « › » de navigation, désormais rendu comme glyphe texte
/// intégré au titre du banner (Text.rich) plutôt qu'une icône Phosphor.
Finder _chevron() => find.textContaining('›', findRichText: true);

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
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      // Logo source rendu dans le hero (pas d'illustration thème).
      expect(find.byType(SourceLogoAvatar), findsOneWidget);
      expect(find.byType(FacteurImage), findsOneWidget);
      expect(find.byType(FluxContinuArticleCard), findsNWidgets(3));
      // Le titre du hero = nom de la source.
      expect(find.textContaining('Le Monde'), findsOneWidget);
    });

    testWidgets(
        'source sans article : état vide TOUJOURS visible + CTA curation',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _sourceSection(items: 0),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      // Aucune carte, mais la section reste rendue avec son état vide + CTA.
      expect(find.byType(FluxContinuArticleCard), findsNothing);
      expect(find.text('Voir toute la curation'), findsOneWidget);
      expect(find.byType(SourceLogoAvatar), findsOneWidget);
    });

    testWidgets(
        'source noRecentSource + articles anciens : note « Pas d\'article '
        'récent. » dans le banner + cartes', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _sourceSection(items: 3, noRecentSource: true),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      // Les cartes anciennes sont rendues (pas d'empty-state)…
      expect(find.byType(FluxContinuArticleCard), findsNWidgets(3));
      expect(find.text('Voir toute la curation'), findsNothing);
      // …et le banner signale l'absence d'article récent.
      expect(find.text('Pas d\'article récent.'), findsOneWidget);
    });

    testWidgets(
        'source noRecentSource mais SANS article : empty-state, pas la note',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _sourceSection(items: 0, noRecentSource: true),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      // Aucun article même ancien → empty-state, et la note ne s'affiche pas.
      expect(find.byType(FluxContinuArticleCard), findsNothing);
      expect(find.text('Voir toute la curation'), findsOneWidget);
      expect(find.text('Pas d\'article récent.'), findsNothing);
    });
  });

  group('SectionBlock — section thème vide (footer « Étoffer »)', () {
    testWidgets(
        'thème favori sans article : footer « Étoffer » déplié + accroche '
        '+ entrée de recherche câblée sur onAddSources', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 0),
          onTapArticle: (_) {},
          onSeeAll: () {},
          onAddSources: () => tapped = true,
        ),
      ));
      await tester.pumpAndSettle();

      // Aucune carte, mais la section reste rendue avec son footer « Étoffer ».
      expect(find.byType(FluxContinuArticleCard), findsNothing);
      expect(
        find.textContaining('Rien de neuf récemment sur Tech'),
        findsOneWidget,
      );
      // L'entrée de recherche (Tier 3) ouvre l'ajout de source (onAddSources).
      expect(find.text('Chercher une source Tech'), findsOneWidget);

      await tester.tap(find.text('Chercher une source Tech'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('thème à 1 article rend sa carte (pas d\'empty-state)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 1),
          onTapArticle: (_) {},
          onSeeAll: () {},
          onAddSources: () {},
        ),
      ));

      expect(find.byType(FluxContinuArticleCard), findsOneWidget);
      // Le footer « riche » reste replié : un simple bouton renommé qui mène
      // droit au catalogue filtré (plus de dépli in-place).
      expect(find.text('Plus de sources (Tech)'), findsOneWidget);
      expect(find.text('Chercher une source Tech'), findsNothing);
    });
  });

  group('SectionBlock — coreVisibleCount slice', () {
    testWidgets('nudge anchor targets first card not pending feedback',
        (tester) async {
      final anchor = GlobalKey();
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 3),
          onTapArticle: (_) {},
          onDismissArticle: (_) {},
          pendingFeedbackIds: const {'c0'},
          firstSwipeableCardAnchor: anchor,
        ),
      ));

      expect(find.byType(FeedbackInline), findsOneWidget);
      expect(anchor.currentContext, isNotNull);
      expect(
        find.descendant(
          of: find.byKey(anchor),
          matching: find.text('title-c1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('FeedThemeSection renders only coreVisibleCount cards',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      expect(find.byType(FluxContinuArticleCard), findsNWidgets(3));
    });

    testWidgets('DigestTopicSection renders only coreVisibleCount cards',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _digestTopicSection(topics: 5, coreVisibleCount: 3),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      expect(find.byType(FluxContinuArticleCard), findsNWidgets(3));
    });
  });

  group('SectionBlock — banner cliquable (Story 10.1, ex-CTA « Tout lire »)',
      () {
    testWidgets(
        'le banner porte le chevron de navigation, sans « +X » (retiré PO)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      // Le « +X » d'overflow a été retiré : seul le chevron signale la nav.
      expect(find.textContaining(RegExp(r'\+\d')), findsNothing);
      expect(_chevron(), findsOneWidget);
      // L'ancien CTA de bas de section a disparu.
      expect(find.textContaining('Tout lire'), findsNothing);
    });

    testWidgets(
        'coreVisibleCount réduit dynamiquement → moins de cartes — '
        '« cartes ≤ écran »', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 2),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      expect(find.byType(FluxContinuArticleCard), findsNWidgets(2));
      expect(find.textContaining(RegExp(r'\+\d')), findsNothing);
    });

    testWidgets(
        'chevron TOUJOURS rendu quand onSeeAll est câblé, même sans overflow '
        '(deep-dive = seule route vers carrousels/Explorer) ; pas de +X à 0',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 2, coreVisibleCount: 3),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
      ));

      expect(_chevron(), findsOneWidget);
      // hiddenCount = 2 - 3 = -1 → clampé à 0 → pas de « +X » (le « + » nu des
      // footers de cartes — source non suivie — ne compte pas).
      expect(find.textContaining(RegExp(r'\+\d')), findsNothing);
    });

    testWidgets('tap sur le banner déclenche onSeeAll', (tester) async {
      var opened = false;
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          onTapArticle: (_) {},
          onSeeAll: () => opened = true,
        ),
      ));

      await tester.tap(find.byType(SectionBanner));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });

    testWidgets('DigestTopicSection avec onSeeAll : banner cliquable aussi',
        (tester) async {
      var opened = false;
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _digestTopicSection(topics: 5, coreVisibleCount: 3),
          onTapArticle: (_) {},
          onSeeAll: () => opened = true,
        ),
      ));

      expect(_chevron(), findsOneWidget);
      await tester.tap(find.byType(SectionBanner));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });

    testWidgets(
        'l\'étoile favorite reste un hit target indépendant du banner '
        'cliquable', (tester) async {
      var opened = false;
      var starred = false;
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          onTapArticle: (_) {},
          onSeeAll: () => opened = true,
          onTapFavorite: () => starred = true,
        ),
      ));

      await tester.tap(
        find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.fill)),
      );
      await tester.pumpAndSettle();
      expect(starred, isTrue);
      expect(opened, isFalse);
    });

    testWidgets('sans onSeeAll : pas de chevron, banner non cliquable',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(items: 7, coreVisibleCount: 3),
          onTapArticle: (_) {},
        ),
      ));

      expect(_chevron(), findsNothing);
      expect(find.textContaining('+4'), findsNothing);
    });
  });

  group('SectionBlock — mode Lisible : cap images par section', () {
    testWidgets(
        '3 cartes avec image → seules les 2 premières affichent leur image '
        '(la 3ᵉ tombe en layout texte)', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionBlock(
          section: _themeSection(
            items: 3,
            coreVisibleCount: 3,
            withThumbnails: true,
          ),
          onTapArticle: (_) {},
          onSeeAll: () {},
        ),
        spec: DisplayModeSpec.playful,
      ));

      // 3 cartes rendues, mais seulement 2 images plein-largeur (pas de logo
      // hero sur une section thème → toute FacteurImage est une image de carte).
      expect(find.byType(FluxContinuArticleCard), findsNWidgets(3));
      expect(find.byType(FacteurImage), findsNWidgets(2));
    });
  });
}
