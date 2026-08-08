import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/widgets/divergence_inline_badge.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/models/weather_location.dart';
import 'package:facteur/features/flux_continu/models/weather_snapshot.dart';
import 'package:facteur/features/flux_continu/providers/essentiel_triage_provider.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:facteur/features/flux_continu/providers/weather_location_provider.dart';
import 'package:facteur/features/flux_continu/providers/weather_provider.dart';
import 'package:facteur/features/flux_continu/utils/section_fit.dart';
import 'package:facteur/features/flux_continu/widgets/edition_timeline_sheet.dart';
import 'package:facteur/features/flux_continu/widgets/ephemeral_rattraper_label.dart';
import 'package:facteur/features/flux_continu/widgets/essentiel_hi_fi_card.dart';
import 'package:facteur/features/flux_continu/widgets/essentiel_triage_stack.dart';
import 'package:facteur/features/flux_continu/widgets/triage_stack_skeleton.dart';
import 'package:facteur/features/flux_continu/widgets/triage_swipe_card.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/gamification/models/streak_activity_model.dart';
import 'package:facteur/features/gamification/providers/streak_activity_provider.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/shared/widgets/completion_stamp.dart' show kStampGreen;
import 'package:facteur/shared/widgets/read_state_mark.dart';
import 'package:facteur/widgets/design/facteur_thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// État de tri **inerte** : `hydrated: false` ⇒ la carte reste sur sa liste
/// passive. Sans cet override, l'hydratation SharedPreferences se termine à un
/// nombre de frames imprévisible et la carte bascule en pile à trier au milieu
/// d'un test — les assertions ci-dessous ne passeraient plus que par chance.
/// Le rendu de la pile est couvert séparément (« pile à trier » plus bas).
/// Neutralise le tri pour les tests qui portent sur la **liste passive** (lead
/// + mediums) : un tri **déjà terminé, tout gardé** sur les `contentId`
/// déterministes de [_article]. La carte rend alors ses tuiles habituelles,
/// dans l'ordre du slate.
///
/// Un état vide ne convient plus : depuis la passe design, `hydrated == false`
/// ou un slate pas encore figé rend la **silhouette** de la pile, pas la liste
/// passive — précisément pour que l'attente ne montre plus une mise en page
/// qui va disparaître.
Override _inertTriage() => essentielTriageProvider.overrideWith(
      (ref) => EssentielTriageNotifier(
        ref,
        initialState: EssentielTriageState(
          dayKey: 'test',
          slate: const ['c-1', 'c-2', 'c-3', 'c-4', 'c-5', 'c-6'],
          decisions: {
            for (var i = 1; i <= 6; i++)
              'c-$i': TriageEntry(
                contentId: 'c-$i',
                decision: TriageDecision.keep,
                rank: i,
                via: TriageVia.swipe,
              ),
          },
          hydrated: true,
        ),
      ),
    );

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  bool inertTriage = true,
}) {
  return ProviderScope(
    overrides: [
      weatherProvider.overrideWith(
        () => _FakeWeatherNotifier(_testWeatherForecast()),
      ),
      weatherLocationProvider.overrideWith(_FakeLocationNotifier.new),
      // Spec lu via Hive en prod — court-circuité dans les widget tests.
      displayModeSpecProvider.overrideWith((ref) => DisplayModeSpec.normal),
      // `inertTriage: false` laisse tourner le VRAI notifier (hydratation
      // SharedPreferences + startIfNeeded) — nécessaire pour exercer la chaîne
      // d'activation réelle du tri, cf. « activation via le vrai notifier ».
      if (inertTriage) _inertTriage(),
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
  String? divergenceLevel,
  String? description,
  String? thumbnailUrl,
  String? title,
  String? sourceId,
}) {
  return EssentielArticle(
    contentId: 'c-$rank',
    sourceId: sourceId,
    title: title ?? 'Titre $rank',
    url: 'https://example.com/$rank',
    description: description,
    thumbnailUrl: thumbnailUrl,
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
    divergenceLevel: divergenceLevel,
  );
}

/// Item de carrousel (« Voir d'autres articles »).
Content _carouselItem(String id) => Content(
      id: id,
      title: 'Carrousel $id',
      url: 'https://example.com/$id',
      contentType: ContentType.article,
      publishedAt: DateTime(2026, 5, 23),
      source: Source(id: 's-$id', name: 'Source $id', type: SourceType.article),
    );

FeedCarouselData _carousel(List<String> ids) => FeedCarouselData(
      carouselType: 'test',
      title: 'Le carrousel',
      emoji: '',
      position: 5,
      items: [for (final id in ids) _carouselItem(id)],
      badges: const [],
    );

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
            // Ce test porte sur la pastille météo (dans l'en-tête), pas sur la
            // pile de tri : on garde la carte en liste passive (plus courte) —
            // sans quoi la pile, plus haute depuis les grandes images (item 1),
            // déborde ce Scaffold non scrollable de 600 px de haut.
            _inertTriage(),
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

    testWidgets(
        'la pastille « N nouveaux articles » a été retirée (décision PO 33.1) '
        '— rendue nulle part, même avec un delta > 0', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          newSinceMorning: 9,
          onTapArticle: (_) {},
        ),
      ));

      expect(find.textContaining('nouveaux articles'), findsNothing);
      expect(find.textContaining('nouvel article'), findsNothing);
      expect(find.text('9+'), findsNothing);
    });
  });

  // ── Pile à trier (Story 33.1) ─────────────────────────────────────────────

  group('EssentielHiFiCard — pile à trier', () {
    /// État de tri déterministe : slate figé sur les `contentId` de [_article].
    Override triageWith({
      required List<String> slate,
      Map<String, TriageEntry> decisions = const {},
    }) =>
        essentielTriageProvider.overrideWith(
          (ref) => EssentielTriageNotifier(
            ref,
            initialState: EssentielTriageState(
              dayKey: 'test',
              slate: slate,
              decisions: decisions,
              hydrated: true,
            ),
          ),
        );

    testWidgets('tri en cours : la pile remplace la liste passive',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [triageWith(slate: const ['c-1', 'c-2'])],
      ));
      await tester.pump();

      // Le haut de la pile est rendu, la barre d'actions aussi.
      expect(find.text('Titre 1'), findsWidgets);
      expect(find.text('Je garde'), findsOneWidget);
      // Plus de compteur « N sur M triés » (décision PO) : la barre de
      // progression segmentée porte seule l'avancement.
      expect(find.textContaining('sur 2 triés'), findsNothing);
    });

    testWidgets('un article gardé apparaît sous la pile', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2'],
            decisions: const {
              'c-1': TriageEntry(
                contentId: 'c-1',
                decision: TriageDecision.keep,
                rank: 1,
                via: TriageVia.swipe,
              ),
            },
          ),
        ],
      ));
      await tester.pump();

      // Ancre stable : la ligne du gardé elle-même, plutôt qu'un compteur
      // (retiré) dont le libellé bougeait à chaque itération de copy.
      expect(find.byKey(const ValueKey('triage-kept-row-c-1')), findsOneWidget);
      expect(find.textContaining('sur 2 triés'), findsNothing);
    });

    testWidgets(
        'la carte de tri porte l\'image, la couverture et la polarisation, '
        'et plus de chapô', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(
              rank: 1,
              description: 'Un chapô qui ne doit plus être rendu.',
              thumbnailUrl: 'https://example.com/1.jpg',
              sourceCount: 4,
              divergenceLevel: 'high',
            ),
            _article(rank: 2),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [triageWith(slate: const ['c-1', 'c-2'])],
      ));
      await tester.pump();

      expect(find.byKey(const Key('triage-coverage-chip')), findsOneWidget);
      expect(find.text('4 sources'), findsOneWidget);
      // Seule la carte du dessus porte le signal : `c-2` n'a pas de niveau.
      expect(find.byType(DivergenceInlineBadge), findsOneWidget);
      // Le chapô a quitté la carte : à ce stade on choisit, on ne lit pas.
      expect(find.text('Un chapô qui ne doit plus être rendu.'), findsNothing);
    });

    testWidgets(
        'un article sans image ne rend aucun bandeau : carte texte plus '
        'courte, pas d\'aplat gris', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          // Les deux cartes de la pile sont sans image : plus de placeholder
          // imposé (décision PO), et le slot prend la hauteur « texte ».
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [triageWith(slate: const ['c-1', 'c-2'])],
      ));
      await tester.pump();

      expect(find.byKey(const Key('triage-card-banner')), findsNothing);
      expect(
        tester.getSize(find.byType(TriageSwipeCard)).height,
        kTriageCardTextOnlyHeight,
      );
    });

    testWidgets('un article avec image garde son bandeau pleine hauteur',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1, thumbnailUrl: 'https://example.com/1.jpg'),
            _article(rank: 2, thumbnailUrl: 'https://example.com/2.jpg'),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [triageWith(slate: const ['c-1', 'c-2'])],
      ));
      await tester.pump();

      final banners = find.byKey(const Key('triage-card-banner'));
      expect(banners, findsNWidgets(2));
      for (final size in tester.widgetList(banners).map(
            (w) => tester.getSize(find.byWidget(w)),
          )) {
        expect(size.height, kTriageCardImageHeight);
      }
      expect(
        tester.getSize(find.byType(TriageSwipeCard)).height,
        kTriageCardHeight,
      );
    });

    testWidgets(
        'un titre long tient ses 4 lignes dans la carte, sans déborder '
        'ni rogner le pied', (tester) async {
      // Le point à ne pas rater du budget : la carte a une hauteur FIGÉE. Si
      // l'arithmétique de `kTriageCardHeight` était trop serrée, le titre
      // perdrait des lignes en silence (ou le pied sauterait). On vérifie sur
      // le pire cas réel : un titre qui remplit ses 4 lignes.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const longTitle =
          'Un titre de presse particulièrement long qui occupe sans peine '
          'quatre lignes entières sur un écran de trois cent quatre-vingt-dix '
          'pixels de large, et même davantage si on le laissait faire';

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(
              rank: 1,
              title: longTitle,
              // Avec image ⇒ carte pleine hauteur et titre plafonné à 4 lignes,
              // le pire cas que `kTriageCardHeight` doit tenir.
              thumbnailUrl: 'https://example.com/1.jpg',
              sourceCount: 4,
              divergenceLevel: 'high',
            ),
            _article(rank: 2),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [triageWith(slate: const ['c-1', 'c-2'])],
      ));
      await tester.pump();

      // 4 lignes de Fraunces 19 · height 1.3 ≈ 98,8 px. La boîte du titre doit
      // les tenir : en dessous, le plafond `maxLines: 4` serait décoratif et le
      // titre se ferait rogner par la hauteur figée de la carte.
      final titleHeight = tester.getSize(find.text(longTitle)).height;
      expect(titleHeight, greaterThanOrEqualTo(4 * 19 * 1.3));

      // Et le pied reste rendu **sous** le titre, dans la carte.
      final chip = find.byKey(const Key('triage-coverage-chip'));
      expect(chip, findsOneWidget);
      expect(
        tester.getTopLeft(chip).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text(longTitle)).dy),
      );
    });

    testWidgets(
        'long-press sur la carte de tri ouvre l\'aperçu ; un drag horizontal '
        'ne l\'arme pas (arène de gestes swipe × long press)', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [triageWith(slate: const ['c-1', 'c-2'])],
      ));
      await tester.pump();

      final card = tester.getCenter(find.text('Titre 1').first);

      // 1. Drag horizontal court (sous le seuil de décision) : le swipe gagne
      //    l'arène, l'aperçu ne doit jamais s'ouvrir sous le doigt.
      final drag = await tester.startGesture(card);
      await tester.pump(const Duration(milliseconds: 50));
      await drag.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(FacteurThumbnail), findsNothing);
      await drag.up();
      await tester.pumpAndSettle();

      // 2. Appui maintenu sans mouvement : l'aperçu s'ouvre.
      final press = await tester.startGesture(card);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(FacteurThumbnail), findsOneWidget);

      await press.up();
      await tester.pumpAndSettle();
      expect(find.byType(FacteurThumbnail), findsNothing);
    });

    testWidgets(
        'les gardés se construisent sous la barre d\'actions, sans compteur',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1),
            _article(rank: 2),
            _article(rank: 3),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3'],
            decisions: const {
              'c-1': TriageEntry(
                contentId: 'c-1',
                decision: TriageDecision.keep,
                rank: 1,
                via: TriageVia.swipe,
              ),
            },
          ),
        ],
      ));
      await tester.pump();

      // Ancre stable (la ligne du gardé et le bouton « Je garde ») plutôt que
      // le libellé d'un compteur : la zone d'interaction reste figée en haut,
      // la liste grandit vers le bas.
      final keptRowY =
          tester.getTopLeft(find.byKey(const ValueKey('triage-kept-row-c-1'))).dy;
      final actionBarY = tester.getTopLeft(find.text('Je garde')).dy;
      expect(keptRowY, greaterThan(actionBarY));
      // Plus aucun « N sur M triés » nulle part.
      expect(find.textContaining('sur 3 triés'), findsNothing);
    });

    testWidgets(
        'tri terminé : la carte n\'affiche que les articles gardés '
        '(les rejetés ne réapparaissent pas) et propose « Trier à nouveau »',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1),
            _article(rank: 2),
            _article(rank: 3),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3'],
            decisions: const {
              'c-1': TriageEntry(
                contentId: 'c-1',
                decision: TriageDecision.keep,
                rank: 1,
                via: TriageVia.swipe,
              ),
              'c-2': TriageEntry(
                contentId: 'c-2',
                decision: TriageDecision.pass,
                rank: 2,
                via: TriageVia.swipe,
              ),
              'c-3': TriageEntry(
                contentId: 'c-3',
                decision: TriageDecision.later,
                rank: 3,
                via: TriageVia.swipe,
              ),
            },
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Trier à nouveau'), findsOneWidget);
      expect(find.text('Je garde'), findsNothing);
      // Gardés (« Je garde » + « Plus tard »), dans l'ordre du slate.
      expect(find.text('Titre 1'), findsOneWidget);
      expect(find.text('Titre 3'), findsOneWidget);
      // Le rejeté a disparu de la vue finale — c'est le fix du décalage
      // « liste finale ≠ gardés ».
      expect(find.text('Titre 2'), findsNothing);
    });

    testWidgets(
        'tri terminé sans rien garder : état vide sobre + « Trier à nouveau »',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2'],
            decisions: const {
              'c-1': TriageEntry(
                contentId: 'c-1',
                decision: TriageDecision.pass,
                rank: 1,
                via: TriageVia.swipe,
              ),
              'c-2': TriageEntry(
                contentId: 'c-2',
                decision: TriageDecision.pass,
                rank: 2,
                via: TriageVia.swipe,
              ),
            },
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Rien gardé aujourd\'hui.'), findsOneWidget);
      expect(find.text('Trier à nouveau'), findsOneWidget);
      // Aucun article : ni gardé, ni rejeté « ressuscité ».
      expect(find.text('Titre 1'), findsNothing);
      expect(find.text('Titre 2'), findsNothing);
    });

    testWidgets(
        'activation via le VRAI notifier : hydratation → startIfNeeded → la '
        'pile de tri s\'affiche sans injecter d\'état', (tester) async {
      // Régression du bug « le tri ne s\'affiche pas » : aucun autre test ne
      // faisait tourner la vraie chaîne (hydrate → _scheduleStart →
      // startIfNeeded → isActive → rendu). Sans override d\'état, sur une
      // journée fraîche (SharedPreferences vide, cf. setUp), la pile doit
      // apparaître d\'elle-même.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        inertTriage: false,
      ));
      // Laisse l\'hydratation SharedPreferences se résoudre puis le post-frame
      // startIfNeeded figer le slate et faire basculer isActive.
      await tester.pumpAndSettle();

      expect(find.byType(EssentielTriageStack), findsOneWidget);
      expect(find.text('Je garde'), findsOneWidget);
      // Plus de compteur « N sur M triés » (décision PO) : la barre de
      // progression segmentée porte seule l'avancement.
      expect(find.textContaining('sur 2 triés'), findsNothing);
    });

    testWidgets('une édition passée ne déclenche jamais le tri', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2']),
          selectedEditionDateProvider.overrideWith(
            (ref) => EditionPastDay(DateTime(2026, 5, 20)),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Je garde'), findsNothing);
      expect(find.text('Titre 2'), findsOneWidget);
    });

    testWidgets(
        'tri terminé avec 0 gardé + carrousel : « Plus d\'articles » '
        'injecte et rouvre la pile', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          carousel: _carousel(const ['x-1', 'x-2']),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2'],
            decisions: const {
              'c-1': TriageEntry(
                contentId: 'c-1',
                decision: TriageDecision.pass,
                rank: 1,
                via: TriageVia.swipe,
              ),
              'c-2': TriageEntry(
                contentId: 'c-2',
                decision: TriageDecision.pass,
                rank: 2,
                via: TriageVia.swipe,
              ),
            },
          ),
        ],
      ));
      await tester.pump();

      // Le pied de fin de tri porte les deux actions, toujours (l'encart
      // conditionnel « en voir d'autres ? » a disparu).
      expect(find.text('Plus d\'articles'), findsOneWidget);
      expect(find.text('Trier à nouveau'), findsOneWidget);
      expect(find.text('Rien gardé aujourd\'hui.'), findsOneWidget);

      await tester.tap(find.text('Plus d\'articles'));
      await tester.pump(); // extendSlate synchrone + rebuild
      await tester.pump(const Duration(milliseconds: 300)); // AnimatedSize

      // La pile rouvre sur le 1er article injecté du carrousel.
      expect(find.byType(EssentielTriageStack), findsOneWidget);
      expect(find.text('Je garde'), findsOneWidget);
      expect(find.text('Carrousel x-1'), findsWidgets);
    });

    testWidgets(
        'tri terminé, 1 gardé + carrousel : « Plus d\'articles » proposé, le '
        'gardé reste affiché', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          carousel: _carousel(const ['x-1']),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2'],
            decisions: const {
              'c-1': TriageEntry(
                contentId: 'c-1',
                decision: TriageDecision.keep,
                rank: 1,
                via: TriageVia.swipe,
              ),
              'c-2': TriageEntry(
                contentId: 'c-2',
                decision: TriageDecision.pass,
                rank: 2,
                via: TriageVia.swipe,
              ),
            },
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Plus d\'articles'), findsOneWidget);
      expect(find.text('Trier à nouveau'), findsOneWidget);
      expect(find.text('Titre 1'), findsOneWidget); // le gardé
    });

    testWidgets(
        'tri terminé sans carrousel : « Plus d\'articles » est masqué (pool '
        'injectable vide)', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2'],
            decisions: const {
              'c-1': TriageEntry(
                contentId: 'c-1',
                decision: TriageDecision.pass,
                rank: 1,
                via: TriageVia.swipe,
              ),
              'c-2': TriageEntry(
                contentId: 'c-2',
                decision: TriageDecision.pass,
                rank: 2,
                via: TriageVia.swipe,
              ),
            },
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Plus d\'articles'), findsNothing);
      expect(find.text('Rien gardé aujourd\'hui.'), findsOneWidget);
      expect(find.text('Trier à nouveau'), findsOneWidget);
    });

    testWidgets(
        'tri indéterminé (SharedPrefs pas encore lu) : silhouette de pile, '
        'jamais la liste passive', (tester) async {
      // Le vrai bug : sur un boot tiède (snapshot frais ⇒ pas de squelette
      // d'écran), la carte rendait l'ancienne mise en page puis la pile.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        inertTriage: false,
        overrides: [
          essentielTriageProvider.overrideWith(
            (ref) => EssentielTriageNotifier(
              ref,
              // `hydrated: false` ⇒ tri indéterminé, l'échappatoire de test du
              // notifier court-circuitant l'hydratation asynchrone.
              initialState: const EssentielTriageState(dayKey: 'test'),
            ),
          ),
        ],
      ));
      await tester.pump();

      expect(find.byType(TriageStackSkeleton), findsOneWidget);
      expect(find.byType(EssentielTriageStack), findsNothing);
      // Aucune tuile de la liste passive n'a clignoté.
      expect(find.text('Titre 1'), findsNothing);
      expect(find.text('Titre 2'), findsNothing);
    });

    testWidgets(
        'coche « suivie » / étoile « favorite » à droite du nom de source',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1, sourceId: 's-fav'),
            _article(rank: 2, sourceId: 's-followed'),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2']),
          userSourcesStateProvider.overrideWith(_FakeSourcesState.new),
        ],
      ));
      await tester.pump();

      // Carte du dessus (favorite) et carte du dessous (suivie) portent chacune
      // leur signal — l'idiome canonique `InterestStateVisuals`, pas un
      // nouveau.
      expect(
        find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.fill)),
        findsOneWidget,
      );
      expect(
        find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)),
        findsOneWidget,
      );
    });

    testWidgets('une source neutre ne porte aucun signal', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1, sourceId: 's-neutral'),
            _article(rank: 2, sourceId: 's-neutral'),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2']),
          userSourcesStateProvider.overrideWith(_FakeSourcesState.new),
        ],
      ));
      await tester.pump();

      expect(
        find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.fill)),
        findsNothing,
      );
      expect(
        find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)),
        findsNothing,
      );
    });
  });
}

/// État de sources déterministe : `s-fav` favorite, `s-followed` suivie, tout
/// le reste neutre.
class _FakeSourcesState extends UserSourcesStateNotifier {
  @override
  Future<UserSourcesState> build() async => const UserSourcesState(
        sources: [
          SourceInterest(
            sourceId: 's-fav',
            state: InterestState.favorite,
            priorityMultiplier: 1,
          ),
          SourceInterest(
            sourceId: 's-followed',
            state: InterestState.followed,
            priorityMultiplier: 1,
          ),
        ],
        favorites: [SourceFavoriteRef(sourceId: 's-fav', position: 0)],
        favoriteCount: 1,
        favoriteCap: 3,
      );
}
