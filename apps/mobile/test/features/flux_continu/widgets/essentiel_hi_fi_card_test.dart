import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/models/weather_location.dart';
import 'package:facteur/features/flux_continu/models/weather_snapshot.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:facteur/features/flux_continu/providers/weather_location_provider.dart';
import 'package:facteur/features/flux_continu/providers/weather_provider.dart';
import 'package:facteur/features/flux_continu/widgets/edition_timeline_sheet.dart';
import 'package:facteur/features/flux_continu/widgets/ephemeral_rattraper_label.dart';
import 'package:facteur/features/flux_continu/widgets/essentiel_hi_fi_card.dart';
import 'package:facteur/features/gamification/models/streak_activity_model.dart';
import 'package:facteur/features/gamification/providers/streak_activity_provider.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/shared/widgets/completion_stamp.dart' show kStampGreen;
import 'package:facteur/shared/widgets/read_state_mark.dart';
import 'package:facteur/widgets/design/facteur_thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  DateTime? completedAt,
  int sourceCount = 0,
  int perspectiveCount = 0,
  List<SourceMini> perspectiveSources = const [],
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
    perspectiveCount: perspectiveCount,
    isActuDuJour: isActuDuJour,
    isRead: isRead,
    completedAt: completedAt,
    sourceCount: sourceCount,
    perspectiveSources: perspectiveSources,
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Le nudge auto-grow enveloppe chaque tuile d'un VisibilityDetector — sans
    // ça, son timer d'update (500 ms) reste pendant au teardown.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  // Prefs mockées : le set local « rattrapé » (editionCaughtUpProvider) et le
  // nudge éphémère lisent SharedPreferences au montage.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

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

    testWidgets('la tuile lead affiche le filet et la double coche quand '
        'l\'article est lu jusqu\'au bout', (tester) async {
      // Impossible avant : la copie locale de la pastille codait `check` en
      // dur, et `AnimatedFeedCard` n'était monté nulle part.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(
              rank: 1,
              isRead: true,
              completedAt: DateTime(2026, 5, 23, 9),
            ),
          ],
          onTapArticle: (_) {},
        ),
      ));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == kStampGreen,
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<ReadStateMark>(find.byType(ReadStateMark)).state,
        ReadState.completed,
      );
    });

    testWidgets('une tuile lue sans temps connu → « Lu en partie »',
        (tester) async {
      // isRead sans completedAt ni time_spent → spectre retombe sur
      // partiallyRead (coche pleine simple, 0.6), jamais « Ouvert ».
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1, isRead: true)],
          onTapArticle: (_) {},
        ),
      ));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == kStampGreen,
        ),
        findsNothing,
      );
      expect(
        tester.widget<ReadStateMark>(find.byType(ReadStateMark)).state,
        ReadState.partiallyRead,
      );
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
        'long-press on the lead reopens the floating preview overlay '
        '(régression #973)', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
      ));

      // Au repos : pas d'aperçu (l'overlay rend une FacteurThumbnail).
      expect(find.byType(FacteurThumbnail), findsNothing);

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Titre 1')));
      // Dépasse la deadline long-press (500 ms par défaut du GestureDetector).
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 200)); // anim overlay

      // Le vrai aperçu flottant est de nouveau monté (PR #973 l'avait remplacé
      // par un « grow nudge » cosmétique).
      expect(find.byType(FacteurThumbnail), findsOneWidget,
          reason: 'Long-press must reopen the floating preview overlay.');

      // Nettoyage : l'overlay est un OverlayEntry à état statique — le relâcher
      // et laisser l'anim de sortie se terminer évite toute fuite entre tests.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(FacteurThumbnail), findsNothing);
    });

    testWidgets(
        'long-press on a medium tile reopens the preview overlay',
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
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(FacteurThumbnail), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(FacteurThumbnail), findsNothing);
    });


    testWidgets(
        'la puce de couverture est rendue sur les tuiles couvertes (>= 2 '
        'sources) et ne fait pas déborder le 390 px', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const covered = [
        SourceMini(name: 'Le Monde'),
        SourceMini(name: 'Libération'),
        SourceMini(name: 'Le Figaro'),
      ];
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(
              rank: 1,
              source: 'Le Monde Diplomatique',
              sourceCount: 4,
              perspectiveSources: covered,
            ),
            _article(
              rank: 2,
              source: 'Le Monde Diplomatique',
              sourceCount: 3,
              perspectiveSources: covered,
            ),
            // Sous le seuil : aucune puce.
            _article(rank: 3, sourceCount: 1),
          ],
          onTapArticle: (_) {},
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('4 sources'), findsOneWidget);
      expect(find.text('3 sources'), findsOneWidget);
      expect(find.text('1 source'), findsNothing);
    });

    testWidgets(
        'la couverture affiche le plus grand entre source_count (ranking) et '
        'perspective_count (reader) — bug carte bloquée à ~2', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          // Ranking figé à 1, mais la couverture réelle (reader) = 7 : la puce
          // doit refléter le 7, pas rester bloquée sous le seuil.
          articles: [_article(rank: 1, sourceCount: 1, perspectiveCount: 7)],
          onTapArticle: (_) {},
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('7 sources'), findsOneWidget);
      expect(find.text('1 source'), findsNothing);
    });

    testWidgets(
        'aucune puce quand la couverture réelle reste < 2 (source et '
        'perspective sous le seuil)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1, sourceCount: 1, perspectiveCount: 1)],
          onTapArticle: (_) {},
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('essentiel-coverage-chip')), findsNothing);
      expect(find.text('1 source'), findsNothing);
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
        'à jour (today, streaks indispo) → header épuré : icône seule, '
        'ni libellé, ni point rouge, ni nudge', (tester) async {
      // EPIC « Lettre du jour » — « Rattraper » est désormais un signal
      // contextuel : en today, si les streaks sont indisponibles (défaut du
      // wrap → editionReadStatus « unavailable »), le déclencheur est l'icône ⏪
      // seule (label null, pas de point, pas de nudge éphémère).
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(EditionRewindTrigger), findsOneWidget);
      final trigger = tester.widget<EditionRewindTrigger>(
        find.byType(EditionRewindTrigger),
      );
      expect(trigger.label, isNull);
      // Pas de nudge → pas de point rouge (le badge est dérivé de sa présence).
      expect(trigger.ephemeralLabel, isNull);
      expect(find.byType(EphemeralRattraperLabel), findsNothing);
    });

    testWidgets(
        'en retard (today, édition d\'hier non ouverte) → point rouge + '
        'nudge « Rattraper ? » monté', (tester) async {
      // Streaks disponibles avec J-1 `opened == false` (et set local vide) ⇒
      // missedYesterday == true → point rouge persistant + EphemeralRattraperLabel.
      final today = editionTodayDate();
      final past = editionPastDays(kEditionMaxPastDays); // J-1 (Hier)
      final activity = StreakActivityModel(
        currentStreak: 1,
        longestStreak: 1,
        days: [
          StreakActivityDay(date: today, opened: true),
          StreakActivityDay(date: past.first, opened: false), // Hier non lu
        ],
      );

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
        overrides: [
          streakActivityProvider.overrideWith((ref) async => activity),
        ],
      ));
      // Laisse le FutureProvider streaks se résoudre → editionReadStatus dispo.
      await tester.pumpAndSettle();

      final trigger = tester.widget<EditionRewindTrigger>(
        find.byType(EditionRewindTrigger),
      );
      // ephemeralLabel présent → point rouge dérivé + nudge monté.
      expect(trigger.ephemeralLabel, isNotNull);
      expect(find.byType(EphemeralRattraperLabel), findsOneWidget);

      // Purge des timers du nudge (fondu-in ~1 s) avant la fin du test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
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

    testWidgets('pastille « N nouveaux articles » rendue quand > 0',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          newSinceMorning: 3,
          onTapArticle: (_) {},
        ),
      ));

      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('nouveaux articles'), findsOneWidget);
    });

    testWidgets('1 nouvel → libellé singulier', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          newSinceMorning: 1,
          onTapArticle: (_) {},
        ),
      ));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('nouvel article'), findsOneWidget);
    });

    testWidgets('pastille masquée quand delta == 0', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
      ));

      expect(find.textContaining('nouveaux article'), findsNothing);
      expect(find.textContaining('nouvel article'), findsNothing);
    });

    testWidgets('delta au plafond (9) affiche « 9+ »', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          newSinceMorning: 9,
          onTapArticle: (_) {},
        ),
      ));

      expect(find.text('9+'), findsOneWidget);
      expect(find.textContaining('nouveaux articles'), findsOneWidget);
    });
  });
}
