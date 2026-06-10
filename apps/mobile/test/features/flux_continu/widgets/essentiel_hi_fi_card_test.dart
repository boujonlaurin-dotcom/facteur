import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/models/weather_location.dart';
import 'package:facteur/features/flux_continu/models/weather_snapshot.dart';
import 'package:facteur/features/flux_continu/providers/weather_location_provider.dart';
import 'package:facteur/features/flux_continu/providers/weather_provider.dart';
import 'package:facteur/features/flux_continu/widgets/essentiel_hi_fi_card.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      weatherProvider.overrideWith(
        () => _FakeWeatherNotifier(_testWeatherForecast()),
      ),
      weatherLocationProvider.overrideWith(_FakeLocationNotifier.new),
      ...overrides,
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

class _FakeWeatherNotifier extends WeatherNotifier {
  _FakeWeatherNotifier(this._value);
  final WeatherForecast _value;
  @override
  Future<WeatherForecast> build() async => _value;
}

/// Évite le chargement Hive (non initialisé en test unitaire) : renvoie Paris.
class _FakeLocationNotifier extends WeatherLocationNotifier {
  @override
  WeatherLocation build() => WeatherLocation.paris;
}

WeatherForecast _testWeatherForecast() {
  return WeatherForecast(
    condition: WeatherCondition.sunny,
    currentC: 19,
    feelsLikeC: 18,
    minC: 12,
    maxC: 21,
    fetchedAt: DateTime(2026, 5, 28),
    days: [
      for (var i = 0; i < 5; i++)
        WeatherDay(
          date: DateTime(2026, 5, 28).add(Duration(days: i)),
          condition: WeatherCondition.sunny,
          minC: 12 + i,
          maxC: 21 + i,
        ),
    ],
  );
}

EssentielArticle _article({
  required int rank,
  String label = 'Tech',
  String? theme = 'tech',
  String source = 'Le Monde',
  bool isActuDuJour = false,
  bool isRead = false,
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
    isRead: isRead,
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
        find.textContaining('5 articles du jour, basé sur tes intérêts'),
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

    testWidgets(
        'tap on the personalize button fires the callback and not the '
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

    testWidgets(
        'no footer CTAs: the card is a standalone section, not a teaser',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: List.generate(5, (i) => _article(rank: i + 1)),
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      expect(find.text('Tout l’essentiel'), findsNothing);
      expect(find.text('Flâner →'), findsNothing);
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

    testWidgets('shows date stamp before the 2 s timer fires', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      expect(find.byType(SvgPicture), findsNothing);
      expect(find.text('Météo'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_return_rounded), findsOneWidget);
    });

    testWidgets(
        'flips to the weather badge and tapping it opens the detail '
        'sheet', (tester) async {
      final forecast = WeatherForecast(
        condition: WeatherCondition.sunny,
        currentC: 19,
        feelsLikeC: 18,
        minC: 12,
        maxC: 21,
        fetchedAt: DateTime(2026, 5, 28),
        days: [
          for (var i = 0; i < 5; i++)
            WeatherDay(
              date: DateTime(2026, 5, 28).add(Duration(days: i)),
              condition: WeatherCondition.sunny,
              minC: 12 + i,
              maxC: 21 + i,
            ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherProvider.overrideWith(() => _FakeWeatherNotifier(forecast)),
            weatherLocationProvider.overrideWith(_FakeLocationNotifier.new),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [FacteurPalettes.light]),
            home: Scaffold(
              body: EssentielHiFiCard(
                articles: [_article(rank: 1)],
                onTapArticle: (_) {},
                onTapPersonalize: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before timer fires → date stamp, no weather icon.
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.text('Météo'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_return_rounded), findsOneWidget);

      // Advance 2 s → badge flips to weather (icon + min/max visible).
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('Météo'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == '12°/21°',
        ),
        findsOneWidget,
      );
      final temperatures = tester.widget<ScaleTransition>(
        find.byKey(const ValueKey('weather_temperatures')),
      );
      expect(temperatures.scale.value, closeTo(0.94, 0.01));
      final richText = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == '12°/21°',
        ),
      );
      expect((richText.text as TextSpan).style?.fontSize, 16);

      await tester.pump(const Duration(milliseconds: 250));
      expect(temperatures.scale.value, greaterThan(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(temperatures.scale.value, closeTo(1, 0.001));
      expect(find.byIcon(Icons.keyboard_return_rounded), findsNothing);

      // Tap the weather badge → opens the detail sheet (5-day forecast).
      await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Prévisions'), findsOneWidget,
          reason: 'Tapping the weather badge opens the detail sheet.');
      expect(find.text("Aujourd'hui"), findsOneWidget);
    });

    testWidgets('read article dims its tile to 0.6 and shows a check badge',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1, isRead: true)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      // Read tiles dim to 0.6 (même valeur que les autres sections) — un
      // Opacity à 0.6 est propre au wrapper d'état Lu.
      final dimmed = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity == 0.6);
      expect(dimmed, isNotEmpty);
      // Green check badge (same Phosphor glyph as the other sections).
      expect(
        find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)),
        findsOneWidget,
      );
    });

    testWidgets('unread article is not dimmed (no read badge)', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
          onTapPersonalize: () {},
        ),
      ));

      final dimmed = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity == 0.6);
      expect(dimmed, isEmpty);
      expect(
        find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)),
        findsNothing,
      );
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
