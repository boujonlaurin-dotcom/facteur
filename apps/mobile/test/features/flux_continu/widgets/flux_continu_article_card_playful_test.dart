import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/widgets/flux_continu_article_card.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';

Widget _wrap(Widget child, {required DisplayModeSpec spec}) {
  return ProviderScope(
    overrides: [displayModeSpecProvider.overrideWith((ref) => spec)],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Content _content({String? thumbnailUrl}) {
  return Content(
    id: 'c1',
    title: 'Un titre d\'article assez long pour tester le plafond de lignes '
        'du mode ludique sur plusieurs lignes de texte',
    url: 'https://x.test/c1',
    thumbnailUrl: thumbnailUrl,
    contentType: ContentType.article,
    publishedAt: DateTime(2026, 1, 1),
    source: Source(id: 's', name: 'S', type: SourceType.article),
  );
}

/// Finder du slot image pleine largeur du layout ludique (hauteur fixe spec).
Finder _headerImageSlot() => find.byWidgetPredicate(
      (w) =>
          w is SizedBox &&
          w.height == DisplayModeSpec.playful.regularImageHeight &&
          w.width == double.infinity,
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('FluxContinuArticleCard — mode ludique (image on top)', () {
    testWidgets(
        'avec thumbnail : image pleine largeur en haut (hauteur fixe 170) '
        'et titre plafonné à 3 lignes', (tester) async {
      await tester.pumpWidget(_wrap(
        FluxContinuArticleCard(article: _content(
          thumbnailUrl: 'https://img.test/x.jpg',
        )),
        spec: DisplayModeSpec.playful,
      ));

      expect(_headerImageSlot(), findsOneWidget);
      final title = tester.widget<Text>(
        find.textContaining('Un titre d\'article'),
      );
      expect(title.maxLines, DisplayModeSpec.playful.regularTitleMaxLines);
    });

    testWidgets('sans thumbnail : fallback layout texte standard',
        (tester) async {
      await tester.pumpWidget(_wrap(
        FluxContinuArticleCard(article: _content(thumbnailUrl: null)),
        spec: DisplayModeSpec.playful,
      ));

      expect(_headerImageSlot(), findsNothing);
      // Sans image dominante, le fallback gagne une ligne de titre
      // (regularTitleMaxLines + 1 = 4) : plus de place que les cartes avec
      // image (plafonnées à 3).
      final title = tester.widget<Text>(
        find.textContaining('Un titre d\'article'),
      );
      expect(title.maxLines, DisplayModeSpec.playful.regularTitleMaxLines + 1);
    });

    testWidgets('mode minimaliste : pas d\'image, titre 5 lignes',
        (tester) async {
      await tester.pumpWidget(_wrap(
        FluxContinuArticleCard(article: _content(
          thumbnailUrl: 'https://img.test/x.jpg',
        )),
        spec: DisplayModeSpec.minimal,
      ));

      expect(_headerImageSlot(), findsNothing);
      final title = tester.widget<Text>(
        find.textContaining('Un titre d\'article'),
      );
      expect(title.maxLines, 5);
    });
  });
}
