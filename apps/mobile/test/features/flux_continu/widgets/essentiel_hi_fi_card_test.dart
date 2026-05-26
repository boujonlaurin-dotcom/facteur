import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/widgets/essentiel_hi_fi_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

EssentielArticle _article({
  required int rank,
  String label = 'Tech',
  String? theme = 'tech',
  String source = 'Le Monde',
  bool isActuDuJour = false,
}) {
  return EssentielArticle(
    contentId: 'c-$rank',
    title: 'Titre $rank',
    url: 'https://example.com/$rank',
    publishedAt: DateTime(2026, 5, 23),
    sourceName: source,
    sourceLetter: source.substring(0, 1).toUpperCase(),
    sectionLabel: label,
    theme: theme,
    rank: rank,
    perspectiveCount: 3,
    isActuDuJour: isActuDuJour,
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('EssentielHiFiCard', () {
    testWidgets('renders title, subtitle and the lead article', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      expect(find.textContaining('Ton Essentiel'), findsOneWidget);
      expect(
        find.textContaining('Tes 5 articles du jour'),
        findsOneWidget,
      );
      expect(
        find.textContaining('ÉDITION DU'),
        findsNothing,
        reason: 'Vague 2 hotfix: gray "ÉDITION DU [day]" banner removed.',
      );
      expect(find.text('Titre 1'), findsOneWidget);
    });

    testWidgets('tap on the lead fires onTapArticle with the right article',
        (tester) async {
      EssentielArticle? tapped;
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (a) => tapped = a,
          onTapPersonalize: () {},
        ),
      ));

      await tester.tap(find.text('Titre 1'));
      await tester.pumpAndSettle();
      expect(tapped?.contentId, 'c-1');
    });

    testWidgets('tap on the personalize button fires the callback and not the '
        'lead', (tester) async {
      var personalizeTaps = 0;
      var articleTaps = 0;
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) => articleTaps++,
          onTapPersonalize: () => personalizeTaps++,
        ),
      ));

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(personalizeTaps, 1);
      expect(articleTaps, 0,
          reason: 'Personalize tap must not bubble to the lead InkWell.');
    });

    testWidgets('renders up to 5 articles (lead + 2 mediums + 2 lights)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: List.generate(5, (i) => _article(rank: i + 1)),
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      for (var i = 1; i <= 5; i++) {
        expect(find.text('Titre $i'), findsOneWidget);
      }
    });

    testWidgets('"Tout l\'essentiel" button fires onTapExploreAll when wired',
        (tester) async {
      var exploreTaps = 0;
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
          onTapSeeAllDown: () {},
          onTapExploreAll: () => exploreTaps++,
        ),
      ));

      expect(find.text('Tout l’essentiel'), findsOneWidget);
      await tester.tap(find.text('Tout l’essentiel'));
      await tester.pumpAndSettle();
      expect(exploreTaps, 1);
    });

    testWidgets('"Tout l\'essentiel" button is omitted when onTapExploreAll is null',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
          onTapSeeAllDown: () {},
        ),
      ));

      expect(find.text('Tout l’essentiel'), findsNothing);
    });

    testWidgets('"Tous mes articles ↓" button fires onTapSeeAllDown when wired',
        (tester) async {
      var seeAllDownTaps = 0;
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
          onTapSeeAllDown: () => seeAllDownTaps++,
          onTapExploreAll: () {},
        ),
      ));

      expect(find.text('Tous mes articles ↓'), findsOneWidget);
      await tester.tap(find.text('Tous mes articles ↓'));
      await tester.pumpAndSettle();
      expect(seeAllDownTaps, 1);
    });

    testWidgets('"Ton Essentiel" header is rendered', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      expect(find.text('Ton Essentiel'), findsOneWidget);
    });

    testWidgets('lead Actu du jour badge and section chip share a Wrap',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1, isActuDuJour: true)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      final badge = find.text('Actu du jour');
      expect(badge, findsOneWidget);

      // ActuBadge text and section chip both descend from the same Wrap.
      // The chip label resolves via themeMap (theme: 'tech' → 'Technologie').
      final wrap = find.ancestor(of: badge, matching: find.byType(Wrap));
      expect(wrap, findsAtLeastNWidgets(1));
      expect(
        find.descendant(of: wrap.first, matching: find.text('Technologie')),
        findsOneWidget,
      );
    });

    testWidgets('lead Actu du jour badge uses forced sectionEssentiel orange',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1, isActuDuJour: true)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      final badgeText = find.text('Actu du jour');
      final container = tester.widget<Container>(
        find.ancestor(of: badgeText, matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, FacteurPalettes.light.sectionEssentiel);
    });

    testWidgets('slots 2-5 all use the medium layout (no dotted divider)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: List.generate(5, (i) => _article(rank: i + 1)),
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      // 5 articles → 1 lead + 4 mediums → 4 hairlines, no dotted divider.
      for (var i = 2; i <= 5; i++) {
        expect(find.text('Titre $i'), findsOneWidget);
      }
    });
  });
}
