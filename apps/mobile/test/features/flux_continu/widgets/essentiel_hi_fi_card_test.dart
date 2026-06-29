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
import 'package:facteur/features/flux_continu/widgets/edition_timeline_sheet.dart';
import 'package:facteur/features/flux_continu/widgets/essentiel_hi_fi_card.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/widgets/design/facteur_thumbnail.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      weatherProvider.overrideWith(
        () => _FakeWeatherNotifier(_testWeatherForecast()),
      ),
      weatherLocationProvider.overrideWith(_FakeLocationNotifier.new),
      // Spec lu via Hive en prod — court-circuité dans les widget tests.
      displayModeSpecProvider.overrideWith((ref) => DisplayModeSpec.normal),
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
        ),
      ));

      await tester.tap(find.text('Titre 1'));
      await tester.pumpAndSettle();
      expect(tapped?.contentId, 'c-1');
    });

    testWidgets('le bouton « personnaliser » a été retiré (décision PO)',
        (tester) async {
      // Point d'entrée unique des préférences = l'inline « GÉRER » de
      // MyInterestsIntro ; la carte Essentiel n'expose plus de bouton perso.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
      ));

      expect(find.byIcon(Icons.tune_rounded), findsNothing);
    });

    testWidgets(
        'long-press on the lead opens the article preview overlay',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
      ));

      // La carte elle-même est text-only (aucune FacteurThumbnail) ; l'aperçu
      // overlay en rend une → signal propre de présence de l'aperçu.
      expect(find.byType(FacteurThumbnail), findsNothing);

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Titre 1')));
      // Dépasse la deadline long-press (500 ms par défaut du GestureDetector).
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(find.byType(FacteurThumbnail), findsOneWidget,
          reason: 'Long-press should reveal the preview overlay.');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('long-press on a medium tile opens the preview overlay',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
      ));

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Titre 2')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(find.byType(FacteurThumbnail), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('renders up to 5 articles (lead + 2 mediums + 2 lights)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: List.generate(5, (i) => _article(rank: i + 1)),
          onTapArticle: (_) {},
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
        ),
      ));

      expect(find.text('Ton Essentiel'), findsOneWidget);
    });

    testWidgets(
        'affiche le déclencheur rewind avec le libellé du scope courant '
        '(défaut = Aujourd\'hui)', (tester) async {
      // EPIC « Lettre du jour » — refonte timeline overlay : le déclencheur
      // « rewind » vit dans l'en-tête de la carte (sélection par défaut = today).
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
      ));

      expect(find.byType(EditionRewindTrigger), findsOneWidget);
      final trigger = tester.widget<EditionRewindTrigger>(
        find.byType(EditionRewindTrigger),
      );
      expect(trigger.label, 'Aujourd’hui');
    });

    testWidgets('le déclencheur rewind est présent, sans bouton perso',
        (tester) async {
      // Le bouton « personnaliser » a été retiré partout ; le rewind, lui, reste
      // toujours présent (today ET lettre passée).
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
      ));

      expect(find.byType(EditionRewindTrigger), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
    });

    testWidgets(
        'lead Actu du jour badge rendu sans chip section (Bonus 10.1) ; '
        'lead sans Actu du jour : aucun badge', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1, isActuDuJour: true)],
          onTapArticle: (_) {},
        ),
      ));

      expect(find.text('Actu du jour'), findsOneWidget);
      // Le chip section (themeMap : 'tech' → 'Technologie') a été retiré
      // des tuiles pour alléger la carte.
      expect(find.text('Technologie'), findsNothing);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
      ));
      expect(find.text('Actu du jour'), findsNothing);
    });

    testWidgets('lead Actu du jour badge uses forced sectionEssentiel orange',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1, isActuDuJour: true)],
          onTapArticle: (_) {},
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
            displayModeSpecProvider
                .overrideWith((ref) => DisplayModeSpec.normal),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [FacteurPalettes.light]),
            home: Scaffold(
              body: EssentielHiFiCard(
                articles: [_article(rank: 1)],
                onTapArticle: (_) {},
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
      // Mid-flip les deux faces (pastille date + badge météo) sont montées et
      // portent chacune un libellé « Météo » → assertion précise reportée après
      // la fin du flip (cf. plus bas).
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
      expect((richText.text as TextSpan).style?.fontSize, 17);

      await tester.pump(const Duration(milliseconds: 250));
      expect(temperatures.scale.value, greaterThan(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(temperatures.scale.value, closeTo(1, 0.001));
      expect(find.byIcon(Icons.keyboard_return_rounded), findsNothing);
      // Flip terminé → seul le badge météo subsiste, avec son libellé discret
      // souligné « Météo » (remplace l'ancien chevron).
      expect(find.text('Météo'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);

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
        ),
      ));

      // 5 articles → 1 lead + 4 mediums → 4 hairlines, no dotted divider.
      for (var i = 2; i <= 5; i++) {
        expect(find.text('Titre $i'), findsOneWidget);
      }
    });
  });
}
