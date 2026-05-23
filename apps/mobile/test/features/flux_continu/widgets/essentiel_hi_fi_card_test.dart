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
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('EssentielHiFiCard', () {
    testWidgets('renders title, kicker and the lead article', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      expect(find.textContaining('L’Essentiel du jour'), findsOneWidget);
      expect(find.textContaining('5 ACTUS À SUIVRE'), findsOneWidget);
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
  });
}
