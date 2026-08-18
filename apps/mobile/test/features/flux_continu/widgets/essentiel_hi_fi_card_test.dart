import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:mocktail/mocktail.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/digest/widgets/divergence_inline_badge.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/services/read_sync_service.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/models/weather_location.dart';
import 'package:facteur/features/flux_continu/models/weather_snapshot.dart';
import 'package:facteur/features/flux_continu/providers/essentiel_extra_articles_provider.dart';
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

/// Un tri qui se **termine** dans le test déclenche un `flush()` immédiat vers
/// le backend ([EssentielTriageNotifier.decide]) : ce stub l'accepte hors
/// réseau — le vrai repository remonterait jusqu'à Supabase, non initialisé en
/// widget test.
class _AcceptingTriageRepository extends Fake implements EssentielRepository {
  @override
  Future<bool> postTriage({
    required String digestDate,
    required int slateSize,
    required List<Map<String, dynamic>> decisions,
  }) async =>
      true;
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

/// Le contrôle d'objectif rend le chiffre réglable **à part** des libellés :
/// `Garder [−] N [+] articles` (33.4). Un `find.text` sur la
/// phrase entière ne matcherait donc rien — ce helper vérifie les trois
/// morceaux, et qu'ils vivent bien dans le même contrôle.
///
/// [goal] est le nombre d'articles **à garder**, plus la taille du slate.
void expectGoalControl(WidgetTester tester, int goal, {String? reason}) {
  final control = find.byType(TriageGoalControl);
  expect(control, findsOneWidget, reason: reason);
  expect(
    find.descendant(of: control, matching: find.text('$goal')),
    findsOneWidget,
    reason: reason ?? 'le chiffre réglable est rendu entre les deux ronds',
  );
  expect(
    find.descendant(of: control, matching: find.text('Garder')),
    findsOneWidget,
    reason: reason,
  );
  expect(
    find.descendant(
      of: control,
      matching: find.text('articles'),
    ),
    findsOneWidget,
    reason: reason,
  );
  expect(
    find.textContaining('à trier'),
    findsNothing,
    reason: 'le reste à trier n\'est plus déterminé : l\'afficher mentirait',
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
      // B3 (passe PO 09/08) : la description dit le geste de la carte, pas un
      // décompte qui devenait faux dès « Plus d'articles ».
      expect(
        find.text('Choisis les articles que tu liras aujourd\'hui.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('5 articles du jour'),
        findsNothing,
        reason: 'ancienne description, remplacée',
      );
      expect(
        find.textContaining('ÉDITION DU'),
        findsNothing,
        reason: 'Vague 2 hotfix: gray "ÉDITION DU [day]" banner removed.',
      );
      expect(find.text('Titre 1'), findsOneWidget);
    });

    testWidgets(
        'la tuile lead affiche le filet et la double coche quand '
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

    testWidgets('long-press on a medium tile reopens the preview overlay',
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
        'B2 — la liste des gardés est homogène : aucune pastille « Actu du '
        'jour », aucun fond teinté, aucun filet d\'accent', (tester) async {
      // `_inertTriage()` = tri **terminé, tout gardé** ⇒ on est exactement dans
      // la liste des gardés, le seul rendu passif de la journée en cours.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1, isActuDuJour: true),
            _article(rank: 2),
          ],
          onTapArticle: (_) {},
        ),
      ));

      expect(find.text('Titre 1'), findsOneWidget);
      expect(find.text('Actu du jour'), findsNothing);
      // Le chip section (themeMap : 'tech' → 'Technologie') a été retiré des
      // tuiles bien avant ; il ne revient pas par la bande.
      expect(find.text('Technologie'), findsNothing);
      // Ni fond teinté ni filet gauche : plus aucun conteneur ne porte la
      // décoration du lead.
      final accent = FacteurPalettes.light.sectionEssentiel;
      final tinted = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        return d.color == accent.withValues(alpha: 0.06) || d.border is Border;
      });
      expect(
        tinted.evaluate().where((e) {
          final d = (e.widget as Container).decoration as BoxDecoration;
          final b = d.border;
          return d.color == accent.withValues(alpha: 0.06) ||
              (b is Border && b.left.width == 3);
        }),
        isEmpty,
        reason: 'un gardé est rendu comme les autres, sans traitement de lead',
      );
    });

    testWidgets(
        'B2 — une lettre passée garde son rendu éditorial : lead teinté + '
        'pastille « Actu du jour »', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1, isActuDuJour: true),
            _article(rank: 2),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          selectedEditionDateProvider.overrideWith(
            (ref) => EditionPastDay(DateTime(2026, 5, 20)),
          ),
        ],
      ));

      expect(find.text('Actu du jour'), findsOneWidget);
      // Orange Essentiel forcé, quel que soit le thème de l'article.
      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Actu du jour'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (container.decoration as BoxDecoration).color,
        FacteurPalettes.light.sectionEssentiel,
      );
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
        '— la carte ne l\'expose plus et n\'en rend aucune trace',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
      ));

      expect(find.textContaining('nouveaux articles'), findsNothing);
      expect(find.textContaining('nouvel article'), findsNothing);
    });
  });

  // ── Pile à trier (Story 33.1) ─────────────────────────────────────────────

  group('EssentielHiFiCard — pile à trier', () {
    /// État de tri déterministe : slate figé sur les `contentId` de [_article].
    Override triageWith({
      required List<String> slate,
      Map<String, TriageEntry> decisions = const {},
      int? goal,
      bool stopped = false,
      bool stopNudgeDismissed = false,
    }) =>
        essentielTriageProvider.overrideWith(
          (ref) => EssentielTriageNotifier(
            ref,
            initialState: EssentielTriageState(
              dayKey: 'test',
              slate: slate,
              decisions: decisions,
              goal: goal,
              stopped: stopped,
              stopNudgeDismissed: stopNudgeDismissed,
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
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      // Le haut de la pile est rendu, la barre d'actions aussi.
      expect(find.text('Titre 1'), findsWidgets);
      expect(find.text('Je garde'), findsOneWidget);
      // Progression 2A : la ligne « N sur M triés » sous les boutons (les
      // segments ont disparu avec le design 2A).
      expectGoalControl(tester, kTriageGoalDefault);
    });

    testWidgets(
        'la carte qui swipe est ROGNÉE au cadre de la pile (régression drift : '
        'le Transform.translate peignait hors des bornes du Stack)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      // Le `ClipRect` de la pile doit contenir la carte du dessus : c'est lui
      // qui empêche la carte draggée/sortante de balayer le feed à droite du
      // cadre (le `Stack` ne rogne jamais son enfant non positionné).
      final clip = find.ancestor(
        of: find.byType(TriageSwipeCard),
        matching: find.byType(ClipRect),
      );
      expect(clip, findsWidgets,
          reason: 'la carte du dessus doit vivre sous un ClipRect');
      expect(
        find.descendant(
          of: find.byType(EssentielTriageStack),
          matching: find.byType(ClipRect),
        ),
        findsWidgets,
        reason: 'le rognage appartient à la pile elle-même',
      );
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

      // La ligne du gardé, et la progression 2A qui compte le gardé.
      expect(find.byKey(const ValueKey('triage-kept-row-c-1')), findsOneWidget);
      expectGoalControl(tester, kTriageGoalDefault);
      // L'en-tête « TES ARTICLES » apparaît avec la liste.
      expect(find.text('TES ARTICLES'), findsOneWidget);
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
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
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
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      expect(find.byKey(const Key('triage-card-banner')), findsNothing);
      // Sans bandeau, la carte ne réserve plus la hauteur d'une carte image :
      // elle prend celle de son contenu (source + titre court + rien d'autre).
      expect(
        tester.getSize(find.byType(TriageSwipeCard)).height,
        lessThan(kTriageCardHeight - kTriageCardImageHeight),
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
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      final banners = find.byKey(const Key('triage-card-banner'));
      expect(banners, findsNWidgets(2));
      for (final size in tester.widgetList(banners).map(
            (w) => tester.getSize(find.byWidget(w)),
          )) {
        expect(size.height, kTriageCardImageHeight);
      }
      // Le bandeau est la seule part figée : la carte prend sa hauteur plus
      // celle de son texte, et reste sous la borne réservée par le squelette.
      final height = tester.getSize(find.byType(TriageSwipeCard)).height;
      expect(height, greaterThan(kTriageCardImageHeight));
      expect(height, lessThanOrEqualTo(kTriageCardHeight));
    });

    testWidgets(
        'un titre long tient ses 4 lignes dans la carte, sans déborder '
        'ni rogner le pied', (tester) async {
      // La carte épouse désormais son contenu, mais le titre reste plafonné à
      // `maxLines` : ce test vérifie que le plafond n'est pas décoratif — les 4
      // lignes sont bien rendues, et le pied reste sous le titre au lieu d'être
      // repoussé ou rogné. Pire cas réel : un titre qui remplit ses 4 lignes.
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
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
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
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
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
      final keptRowY = tester
          .getTopLeft(find.byKey(const ValueKey('triage-kept-row-c-1')))
          .dy;
      final actionBarY = tester.getTopLeft(find.text('Je garde')).dy;
      expect(keptRowY, greaterThan(actionBarY));
      // La ligne de progression 2A compte les triés et les gardés.
      expectGoalControl(tester, kTriageGoalDefault);
    });

    // ── Reprise E2E PO (08/08) ────────────────────────────────────────────
    //
    // Trois défauts que le PO a vus **dans l'app** alors que les tests
    // passaient au vert : les états injectés couvraient un chemin que le
    // chargement réel n'emprunte pas. Les tests ci-dessous visent donc l'état
    // cassé lui-même (slate irrésolvable) et des invariants de mise en page
    // mesurés, pas des libellés.

    testWidgets(
        'défaut #2 — la barre de progression est rendue SOUS les boutons',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      // Ordre définitif de la colonne (reprise PO 10/08) : actions → barre de
      // progression → contrôle d'objectif. Tout ce qui informe est sous les
      // boutons, jamais au-dessus de la pile.
      final actionBarBottom = tester.getBottomLeft(find.text('Je garde')).dy;
      final barY = tester.getTopLeft(find.byType(TriageProgressBar)).dy;
      final controlY = tester.getTopLeft(find.byType(TriageGoalControl)).dy;
      expect(barY, greaterThan(actionBarBottom));
      expect(controlY, greaterThan(barY));
    });

    testWidgets(
        'défaut #3 — la carte épouse son contenu : un titre court donne une '
        'carte plus courte qu\'un titre long, et la méta reste collée au titre',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const longTitle =
          'Un titre de presse particulièrement long qui occupe sans peine '
          'quatre lignes entières sur un écran de trois cent quatre-vingt-dix '
          'pixels de large, et même davantage si on le laissait faire';

      Future<double> heightFor(String title) async {
        await tester.pumpWidget(_wrap(
          EssentielHiFiCard(
            articles: [
              _article(
                rank: 1,
                title: title,
                thumbnailUrl: 'https://example.com/1.jpg',
                sourceCount: 4,
              ),
              _article(rank: 2),
            ],
            onTapArticle: (_) {},
          ),
          overrides: [
            triageWith(slate: const ['c-1', 'c-2'])
          ],
        ));
        await tester.pump();
        return tester.getSize(find.byType(TriageSwipeCard)).height;
      }

      final shortHeight = await heightFor('Court');
      final longHeight = await heightFor(longTitle);

      // Le cœur du défaut : avec une hauteur figée, les deux valaient 360 — le
      // titre court étirait du vide et repoussait la méta en bas de carte.
      expect(shortHeight, lessThan(longHeight));

      // Et la méta (pastille de couverture) suit le titre au lieu d'être
      // plaquée au bas d'un slot surdimensionné : sur la carte à titre court,
      // elle démarre bien avant le bas de la carte.
      await heightFor('Court');
      final chip = find.byKey(const Key('triage-coverage-chip'));
      final cardBottom = tester.getBottomLeft(find.byType(TriageSwipeCard)).dy;
      expect(tester.getBottomLeft(chip).dy,
          lessThanOrEqualTo(cardBottom - kTriageCardPaddingV));
    });

    testWidgets(
        'défaut #3 — une carte du dessous plus haute que celle du dessus ne '
        'déborde pas', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Le piège du slot intrinsèque : c'est la carte du DESSUS qui dimensionne
      // la pile. Une carte du dessous plus grande (image + titre long sous une
      // carte texte courte) débordait de la contrainte serrée qu'elle héritait.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1, title: 'Court'),
            _article(
              rank: 2,
              title: 'Un titre bien plus long qui, avec son bandeau image, '
                  'fait une carte nettement plus haute que celle du dessus',
              thumbnailUrl: 'https://example.com/2.jpg',
              sourceCount: 4,
              divergenceLevel: 'high',
            ),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      // `pumpWidget` fait échouer le test sur une exception de layout : arriver
      // ici sans erreur EST l'assertion. On vérifie en plus que la pile est
      // bien dimensionnée par la carte du dessus (la courte).
      expect(
        tester.getSize(find.byType(EssentielTriageStack)).height,
        lessThan(kTriageCardHeight + kTriageActionBarHeight),
      );
    });

    testWidgets(
        'défaut #4 — un slate figé qui pointe un article absent du pool rend '
        'la silhouette, jamais un corps vide', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          // Pool du jour, SANS carrousel : `x-99` a été injecté hier par
          // « Plus d'articles » et n'est plus adressable au cold-boot.
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['x-99', 'c-1', 'c-2'])
        ],
      ));
      // Pas de `pump()` supplémentaire : on regarde la frame **avant** que la
      // réparation postée ne s'applique — c'est la frame où l'ancienne version
      // ne rendait rien du tout.

      // Avant : `SizedBox.shrink()` → en-tête seul au-dessus d'un aplat de
      // fond, indéfiniment. C'est la capture rapportée par le PO.
      expect(find.byType(TriageStackSkeleton), findsOneWidget);
      expect(tester.getSize(find.byType(EssentielTriageStack)).height,
          greaterThan(kTriageCardHeight));
    });

    testWidgets(
        'défaut #4 — le slate se répare tout seul : l\'article introuvable '
        'est retiré et le tri reprend sur l\'article suivant', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['x-99', 'c-1', 'c-2'])
        ],
      ));
      // La réparation est postée après la frame (muter un provider pendant le
      // build est interdit) : c'est ce 2ᵉ pump qui la joue.
      await tester.pump();
      await tester.pump();

      // La pile est repartie sur le premier article réellement adressable, et
      // la progression ne compte plus l'article fantôme.
      expect(find.byType(TriageStackSkeleton), findsNothing);
      expect(find.text('Titre 1'), findsWidgets);
      expect(find.text('Je garde'), findsOneWidget);
    });

    testWidgets(
        'défaut #4 — un slate ENTIÈREMENT introuvable se re-gèle sur les '
        'articles du jour au lieu de laisser la silhouette tourner en rond',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Le piège du correctif : vider le slate rend `hasStarted` faux, or le
      // gel du slate est verrouillé **une fois par montage**. Il faut donc que
      // le slate ait d'abord été gelé par cette carte-ci — sinon le verrou
      // n'est pas encore posé et le scénario ne mord pas.
      final triage = triageWith(slate: const []);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [triage],
      ));
      await tester.pumpAndSettle();
      expect(find.text('Titre 1'), findsWidgets, reason: 'slate gelé sur c-1');

      // Le blend live renvoie un jeu d'articles entièrement différent : plus
      // aucun id du slate gelé n'est adressable.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 3), _article(rank: 4)],
          onTapArticle: (_) {},
        ),
        overrides: [triage],
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TriageStackSkeleton), findsNothing);
      expect(find.text('Titre 3'), findsWidgets);
      expect(find.text('Je garde'), findsOneWidget);
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

      expect(find.text('Refaire ?'), findsOneWidget);
      expect(find.text('Je garde'), findsNothing);
      // Gardés (« Je garde » + « Plus tard »), dans l'ordre du slate.
      expect(find.text('Titre 1'), findsOneWidget);
      expect(find.text('Titre 3'), findsOneWidget);
      // Le rejeté a disparu de la vue finale — c'est le fix du décalage
      // « liste finale ≠ gardés ».
      expect(find.text('Titre 2'), findsNothing);
    });

    testWidgets(
        'tri terminé : un gardé que le backend ne sert plus reste dans la '
        'liste au redémarrage (bug « articles gardés disparus »)',
        (tester) async {
      const slate = ['c-1', 'c-2', 'c-3'];
      final decisions = {
        for (var i = 1; i <= 3; i++)
          'c-$i': TriageEntry(
            contentId: 'c-$i',
            decision: TriageDecision.keep,
            rank: i,
            via: TriageVia.swipe,
          ),
      };

      // Session 1 : le pool porte les trois gardés → ils sont archivés.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [for (var i = 1; i <= 3; i++) _article(rank: i)],
          onTapArticle: (_) {},
        ),
        overrides: [triageWith(slate: slate, decisions: decisions)],
      ));
      await tester.pump();
      await tester.pump();

      // Kill de l'app : la portée Riverpod est détruite, seule
      // SharedPreferences survit.
      await tester.pumpWidget(const SizedBox.shrink());

      // Session 2 : l'utilisateur avait **lu** c-1 et c-3 ; passée la grâce de
      // 30 min, « L'Essentiel vivant » les a évincés de `GET /api/essentiel`.
      // Le pool ne porte plus que c-2 — exactement la répro du PO.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [triageWith(slate: slate, decisions: decisions)],
      ));
      await tester.pump();
      await tester.pump();

      for (var i = 1; i <= 3; i++) {
        expect(
          find.text('Titre $i'),
          findsOneWidget,
          reason: 'le gardé #$i doit survivre au kill de l\'app',
        );
      }
      // …et à sa place : l'ordre est celui du slate gelé, pas celui du pool.
      expect(
        tester.getTopLeft(find.text('Titre 1')).dy,
        lessThan(tester.getTopLeft(find.text('Titre 2')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Titre 2')).dy,
        lessThan(tester.getTopLeft(find.text('Titre 3')).dy),
      );
    });

    testWidgets(
        'tri terminé : un gardé re-servi par un refresh ne réapparaît pas '
        '(il n\'avait jamais disparu)', (tester) async {
      const slate = ['c-1', 'c-2', 'c-3'];
      final decisions = {
        for (var i = 1; i <= 3; i++)
          'c-$i': TriageEntry(
            contentId: 'c-$i',
            decision: TriageDecision.keep,
            rank: i,
            via: TriageVia.swipe,
          ),
      };
      final overrides = [triageWith(slate: slate, decisions: decisions)];

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [for (var i = 1; i <= 3; i++) _article(rank: i)],
          onTapArticle: (_) {},
        ),
        overrides: overrides,
      ));
      await tester.pump();
      await tester.pump();

      // Le blend live a évincé c-3 (lu) : il tient désormais par l'archive.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: overrides,
      ));
      await tester.pump();
      expect(find.text('Titre 3'), findsOneWidget);

      // Pull-to-refresh : le backend re-sert c-3. Le PO le voyait « apparaître
      // par magie au milieu de la liste » ; il doit maintenant être un
      // non-événement — même liste, même ordre, aucun doublon.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [for (var i = 1; i <= 3; i++) _article(rank: i)],
          onTapArticle: (_) {},
        ),
        overrides: overrides,
      ));
      await tester.pump();

      for (var i = 1; i <= 3; i++) {
        expect(find.text('Titre $i'), findsOneWidget);
      }
    });

    testWidgets(
        'tri terminé : tous les gardés restent accessibles au-delà du '
        'cinquième', (tester) async {
      final decisions = {
        for (var i = 1; i <= 6; i++)
          'c-$i': TriageEntry(
            contentId: 'c-$i',
            decision: TriageDecision.keep,
            rank: i,
            via: TriageVia.button,
          ),
      };
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [for (var i = 1; i <= 6; i++) _article(rank: i)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3', 'c-4', 'c-5', 'c-6'],
            decisions: decisions,
          ),
        ],
      ));
      await tester.pump();

      for (var i = 1; i <= 6; i++) {
        expect(find.text('Titre $i'), findsOneWidget,
            reason: 'le gardé #$i doit rester ouvrable dans la vue finale');
      }
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
      expect(find.text('Refaire ?'), findsOneWidget);
      // Aucun article : ni gardé, ni rejeté « ressuscité ».
      expect(find.text('Titre 1'), findsNothing);
      expect(find.text('Titre 2'), findsNothing);
    });

    // ── Révélation de fin de tri (fade + scale-in one-shot) ─────────────────

    /// L'enveloppe privée `_TriageDoneReveal`, repérée par son runtimeType.
    Finder doneReveal() => find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_TriageDoneReveal');

    /// L'animation de révélation effectivement montée (absente quand la
    /// révélation est court-circuitée : cold-boot déjà terminé, reduce-motion).
    Finder doneRevealAnim() => find.descendant(
          of: doneReveal(),
          matching: find.byType(TweenAnimationBuilder<double>),
        );

    testWidgets(
        'fin de tri vécue : la liste des gardés se révèle (fade + scale-in), '
        'plus de bascule sèche', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielRepositoryProvider
              .overrideWithValue(_AcceptingTriageRepository()),
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
      expect(find.text('Je garde'), findsOneWidget, reason: 'pile active');

      // Dernière décision : le tri se termine sous les yeux de l'utilisateur.
      await tester.tap(find.text('Je garde'));
      await tester.pumpAndSettle();

      expect(find.text('Refaire ?'), findsOneWidget);
      expect(doneRevealAnim(), findsOneWidget,
          reason: 'transition vécue ⇒ la révélation est montée');
    });

    testWidgets(
        'tri déjà terminé au montage (cold-boot) : rendu direct, aucune '
        'révélation — la fin de tri est un événement, pas un état',
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
                decision: TriageDecision.keep,
                rank: 1,
                via: TriageVia.swipe,
              ),
              'c-2': TriageEntry(
                contentId: 'c-2',
                decision: TriageDecision.keep,
                rank: 2,
                via: TriageVia.swipe,
              ),
            },
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Refaire ?'), findsOneWidget);
      expect(doneReveal(), findsOneWidget);
      expect(doneRevealAnim(), findsNothing,
          reason: 'pas de transition vécue ⇒ pas d\'animation');
    });

    testWidgets(
        'fin de tri sous reduce-motion : l\'état final se rend d\'emblée, '
        'sans crash ni animation', (tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: EssentielHiFiCard(
              articles: [_article(rank: 1), _article(rank: 2)],
              onTapArticle: (_) {},
            ),
          ),
        ),
        overrides: [
          essentielRepositoryProvider
              .overrideWithValue(_AcceptingTriageRepository()),
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

      await tester.tap(find.text('Je garde'));
      await tester.pumpAndSettle();

      expect(find.text('Refaire ?'), findsOneWidget);
      expect(doneRevealAnim(), findsNothing,
          reason: 'reduce-motion court-circuite la révélation');
    });

    // ── Entrée de la ligne gardée (finition « Je garde ») ───────────────────

    testWidgets(
        'la ligne gardée qui vient d\'être ajoutée joue son entrée ; celles '
        'déjà présentes au montage restent statiques', (tester) async {
      // L'enveloppe d'entrée est construite PAR la ligne (la clé vit sur
      // `_KeptRow`, l'animation dans son build) : descendant, pas ancêtre.
      Finder rowEntryAnim(String id) => find.descendant(
            of: find.byKey(ValueKey('triage-kept-row-$id')),
            matching: find.byType(TweenAnimationBuilder<double>),
          );

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
            goal: 3,
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

      // Présente au montage : un état, pas un événement — aucune entrée.
      expect(find.byKey(const ValueKey('triage-kept-row-c-1')), findsOneWidget);
      expect(rowEntryAnim('c-1'), findsNothing);

      // Nouvelle gardée : l'entrée se joue — deux enveloppes montées (la
      // glissée + fondu de la ligne, et le pop easeOutBack de la coche).
      await tester.tap(find.text('Je garde'));
      await tester.pumpAndSettle();

      expect(rowEntryAnim('c-2'), findsNWidgets(2));
      expect(rowEntryAnim('c-1'), findsNothing);
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
      // La ligne de progression 2A part de zéro sur une journée fraîche.
      expectGoalControl(tester, kTriageGoalDefault);
    });

    testWidgets('une édition passée ne déclenche jamais le tri',
        (tester) async {
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

    /// Décisions déterministes sur `c-1..c-N` : les [keep] premiers gardés,
    /// le reste passé. Sert les bancs du pied de tri (« Plus d'articles ? »).
    Map<String, TriageEntry> decisionsKeeping(int keep, int total) => {
          for (var i = 1; i <= total; i++)
            'c-$i': TriageEntry(
              contentId: 'c-$i',
              decision: i <= keep ? TriageDecision.keep : TriageDecision.pass,
              rank: i,
              via: TriageVia.swipe,
            ),
        };

    List<EssentielArticle> articlesUpTo(int n) =>
        [for (var i = 1; i <= n; i++) _article(rank: i)];

    testWidgets(
        'le pied de fin de tri est le même quel que soit le nombre gardé',
        (tester) async {
      // Le CTA n'a plus aucun gate : ni sur les gardés, ni sur ce qu'il reste
      // à injecter (le slate porte déjà tout le pool local).
      for (final kept in [0, 1, 2, 3]) {
        await tester.pumpWidget(_wrap(
          EssentielHiFiCard(
            articles: articlesUpTo(3),
            onTapArticle: (_) {},
          ),
          overrides: [
            triageWith(
              slate: const ['c-1', 'c-2', 'c-3'],
              decisions: decisionsKeeping(kept, 3),
            ),
          ],
        ));
        await tester.pump();

        expect(find.text('Plus d\'articles ?'), findsOneWidget,
            reason: '$kept gardé(s) : le CTA est un engagement produit');
        // La sortie de secours, elle, reste toujours là.
        expect(find.text('Refaire ?'), findsOneWidget);
        // Et l'objectif n'y est **plus** : un tri qui s'arrête en deçà de la
        // cible ne doit jamais se lire comme un échec.
        expect(find.byType(TriageGoalControl), findsNothing);
      }
    });

    testWidgets(
        'fin de tri : un sous-titre de carte « Tes articles » ouvre la liste '
        'des gardés, dans la police de titre', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3'],
            decisions: decisionsKeeping(2, 3),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final title = find.text('Tes articles');
      expect(title, findsOneWidget,
          reason: 'sans lui, la liste des gardés commence par une tuile nue : '
              'rien ne marque la fin du tri');
      // Une **vraie** police de titre, pas le Courier capitales de l'en-tête
      // inline rendu *pendant* le tri (qui, lui, a disparu avec la pile).
      // `startsWith` : google_fonts suffixe la famille par la graisse
      // (`Fraunces_600`), ce que le test n'a pas à figer.
      expect(
        tester.widget<Text>(title).style!.fontFamily,
        startsWith('Fraunces'),
      );
      expect(
        tester.widget<Text>(title).style!.fontFamily,
        isNot(startsWith(GoogleFonts.courierPrime().fontFamily!.split('_').first)),
      );
      expect(find.text('TES ARTICLES'), findsNothing);

      // Il ouvre la liste : au-dessus de la première tuile gardée.
      expect(
        tester.getBottomLeft(title).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Titre 1').first).dy),
      );

      // Le titre est **incrusté dans le filet** : la règle le prolonge à sa
      // droite au lieu de le souligner.
      final rule = find
          .descendant(
            of: find.ancestor(of: title, matching: find.byType(Row)).first,
            matching: find.byType(Container),
          )
          .first;
      final ruleRect = tester.getRect(rule);
      expect(ruleRect.height, 1);
      expect(ruleRect.left, greaterThan(tester.getRect(title).right));
    });

    testWidgets('le sous-titre « Tes articles » n\'existe pas pendant le tri',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3'],
            decisions: decisionsKeeping(1, 1),
          ),
        ],
      ));
      await tester.pump();

      expect(find.byType(EssentielTriageStack), findsOneWidget);
      expect(find.text('Tes articles'), findsNothing,
          reason: 'pendant le tri, la liste des gardés porte son en-tête '
              'inline « TES ARTICLES » — le sous-titre marque la FIN du tri');
      expect(find.text('TES ARTICLES'), findsOneWidget);
    });

    testWidgets(
        'le carrousel entre dans le slate d\'emblée : la pile continue de '
        'proposer sans que rien ne soit à « injecter »', (tester) async {
      // Renversement de la 33.3 : il n'y a plus de « réserve locale » à
      // injecter au tap. Le carrousel fait partie du slate dès le premier
      // rendu, donc le tri de 3 articles ne termine rien.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          carousel: _carousel(const ['x-1', 'x-2']),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3'],
            decisions: decisionsKeeping(0, 3),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EssentielTriageStack), findsOneWidget);
      expect(find.text('Carrousel x-1'), findsWidgets);
      expect(find.text('Plus d\'articles ?'), findsNothing);
    });

    testWidgets(
        '« Plus d\'articles ? » pousse la cible et rouvre la pile sur la suite '
        'du slate', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          carousel: _carousel(const ['x-1', 'x-2']),
          onTapArticle: (_) {},
        ),
        overrides: [
          // Cible atteinte à 3 gardés : le tri est fini alors que le slate a
          // encore de quoi proposer.
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3', 'x-1', 'x-2'],
            decisions: decisionsKeeping(3, 3),
            goal: 3,
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Plus d\'articles ?'), findsOneWidget);
      expect(find.text('Refaire ?'), findsOneWidget);

      await tester.tap(find.text('Plus d\'articles ?'));
      await tester.pump(); // extendGoal synchrone + rebuild
      await tester.pump(const Duration(milliseconds: 300)); // AnimatedSize

      // La pile rouvre sur le 1er article encore à trier.
      expect(find.byType(EssentielTriageStack), findsOneWidget);
      expect(find.text('Je garde'), findsOneWidget);
      expect(find.text('Carrousel x-1'), findsWidgets);
      expectGoalControl(tester, 3 + kTriageGoalExtendStep);
    });

    testWidgets(
        'tri terminé avec 0 gardé : « rien gardé » + « Plus d\'articles ? »',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(2),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2'],
            decisions: decisionsKeeping(0, 2),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Rien gardé aujourd\'hui.'), findsOneWidget);
      expect(find.text('Plus d\'articles ?'), findsOneWidget);
      expect(find.text('Refaire ?'), findsOneWidget);
    });

    // ── « Plus d'articles ? » sans réserve locale (reprise PO 10/08) ──────
    //
    // Le CTA était gaté sur `injectableIds` : finir un tri sans carrousel le
    // faisait **disparaître**, et la fin de tri n'offrait plus qu'un « Trier à
    // nouveau ». Il est désormais un engagement produit — c'est son *action*
    // qui s'adapte (pool local, puis réseau, puis message sobre).

    /// Payload `GET /api/essentiel/more` — même forme que `/api/essentiel`.
    Map<String, dynamic> moreJson(String id) => {
          'content_id': id,
          'title': 'Réseau $id',
          'url': 'https://example.com/$id',
          'published_at': DateTime(2026, 5, 23).toIso8601String(),
          'source': {'id': 's-$id', 'name': 'Source $id'},
          'source_letter': 'S',
          'section_label': '',
          'rank': 1,
        };

    /// Tri **terminé** sur un slate de 2, sans carrousel : la réserve locale
    /// est vide, le CTA n'a que le réseau.
    Future<void> pumpDoneWithoutCarousel(
      WidgetTester tester,
      EssentielRepository repo,
    ) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielRepositoryProvider.overrideWithValue(repo),
          triageWith(
            slate: const ['c-1', 'c-2'],
            decisions: decisionsKeeping(0, 2),
          ),
        ],
      ));
      await tester.pump();
    }

    testWidgets(
        'tri terminé sans carrousel : « Plus d\'articles ? » reste VISIBLE et '
        'va chercher deux articles au réseau', (tester) async {
      final repo = _MockEssentielRepository();
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [moreJson('n-1'), moreJson('n-2')]);

      await pumpDoneWithoutCarousel(tester, repo);

      // Le CTA ne dépend plus de la composition momentanée du carrousel.
      expect(find.text('Plus d\'articles ?'), findsOneWidget);
      expect(find.text('Rien gardé aujourd\'hui.'), findsOneWidget);
      expect(find.text('Refaire ?'), findsOneWidget);

      await tester.tap(find.text('Plus d\'articles ?'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // L'exclusion porte tout ce que le client tient déjà : le slate ET les
      // articles décidés — un rejeté ne doit jamais revenir.
      final captured = verify(() => repo.fetchMore(
            excludeIds: captureAny(named: 'excludeIds'),
            limit: kTriagePrefetchBatch,
          )).captured.last as List<String>;
      expect(captured, containsAll(<String>['c-1', 'c-2']));

      // La pile rouvre sur les deux articles rapatriés.
      expect(find.byType(EssentielTriageStack), findsOneWidget);
      expect(find.text('Je garde'), findsOneWidget);
      expect(find.text('Réseau n-1'), findsWidgets);
    });

    testWidgets(
        'aucun inédit disponible : le CTA reste visible et le dit sobrement, '
        'sans rien ajouter au slate', (tester) async {
      final repo = _MockEssentielRepository();
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const []);

      await pumpDoneWithoutCarousel(tester, repo);
      await tester.tap(find.text('Plus d\'articles ?'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Plus d\'articles ?'), findsOneWidget,
          reason: 'jamais un bouton qui disparaît');
      expect(
        find.text('Pas de nouvel article pour l\'instant.'),
        findsOneWidget,
      );
      // Le tri reste terminé : rien n'a été injecté, aucune pile rouverte.
      expect(find.byType(EssentielTriageStack), findsNothing);
    });

    testWidgets('tap rapide répété : un seul appel réseau', (tester) async {
      final repo = _MockEssentielRepository();
      final gate = Completer<List<Map<String, dynamic>>?>();
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) => gate.future);

      await pumpDoneWithoutCarousel(tester, repo);
      await tester.tap(find.text('Plus d\'articles ?'));
      await tester.pump();

      // Attente non ambiguë, à la place exacte de l'icône : la zone garde sa
      // hauteur, et le CTA reste lisible pendant la requête.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Plus d\'articles ?'), findsOneWidget);

      await tester.tap(find.text('Plus d\'articles ?'));
      await tester.tap(find.text('Plus d\'articles ?'));
      await tester.pump();

      verify(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).called(1);

      gate.complete(const []);
      await tester.pump();
      await tester.pump();
    });

    testWidgets(
        'le réseau ne peut pas ré-injecter un article déjà trié : le doublon '
        'servi par le backend est écarté', (tester) async {
      final repo = _MockEssentielRepository();
      // Le backend renvoie un article DÉJÀ décidé (c-1) et un inédit.
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [moreJson('c-1'), moreJson('n-9')]);

      await pumpDoneWithoutCarousel(tester, repo);
      await tester.tap(find.text('Plus d\'articles ?'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Un seul article ajouté : le slate passe de 2 à 3, pas à 4 — et c'est
      // sur l'inédit que la pile rouvre, jamais sur le doublon déjà trié.
      expectGoalControl(tester, kTriageGoalDefault + kTriageGoalExtendStep);
      expect(find.text('Réseau n-9'), findsWidgets);
      expect(
        tester
            .widget<EssentielTriageStack>(find.byType(EssentielTriageStack))
            .triage
            .slate,
        const ['c-1', 'c-2', 'n-9'],
      );
    });

    testWidgets(
        'cold boot après un ajout réseau : l\'article rapatrié reste '
        'résolvable, la pile n\'est ni vidée ni élaguée', (tester) async {
      // Le piège documenté : « Plus d'articles » persiste dans le slate des
      // `contentId` que le pool du jour (héros + carrousel) ne porte pas. Sans
      // le provider d'extras, `pruneUnavailable` les retirerait au boot suivant
      // — le redémarrage annulerait la décision d'élargir la pile.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielExtraArticlesProvider.overrideWith(
            (ref) => EssentielExtraArticlesNotifier(
              ref,
              initialState: EssentielExtraArticlesState(
                articles: [
                  EssentielArticle.fromJson(moreJson('n-1')),
                ],
                hydrated: true,
              ),
            ),
          ),
          triageWith(
            slate: const ['c-1', 'c-2', 'n-1'],
            decisions: decisionsKeeping(2, 2),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // La pile est ouverte sur l'article rapatrié, pas sur une silhouette.
      expect(find.byType(TriageStackSkeleton), findsNothing);
      expect(find.text('Réseau n-1'), findsWidgets);
      // L'ordre du slate est intact : les deux gardés restent devant.
      expectGoalControl(tester, kTriageGoalDefault);
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

    // ── Story 33.2 — stepper, balises, tap, auto-keep ─────────────────────

    testWidgets('le stepper « Garder … articles » est rendu en tri du jour',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();
      expectGoalControl(tester, kTriageGoalDefault);
    });

    testWidgets('le stepper n\'apparaît jamais sur une lettre passée',
        (tester) async {
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
      expect(find.textContaining('à lire aujourd\'hui'), findsNothing,
          reason: 'une lettre passée est figée, rien à régler');
    });

    testWidgets(
        'le stepper règle le nombre de GARDÉS, sans jamais toucher au slate',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          carousel: _carousel(const ['x-1']),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2', 'c-3', 'x-1'])
        ],
      ));
      await tester.pump();

      expectGoalControl(tester, kTriageGoalDefault);

      await tester.tap(find.bySemanticsLabel('Plus d\'articles'));
      await tester.pump();
      expectGoalControl(tester, kTriageGoalDefault + 1);

      await tester.tap(find.bySemanticsLabel('Moins d\'articles'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Moins d\'articles'));
      await tester.pump();
      expectGoalControl(tester, kTriageGoalDefault - 1);

      // Le slate n'a pas bougé d'un pouce : la cible ne le borne plus.
      expect(
        tester
            .widget<EssentielTriageStack>(find.byType(EssentielTriageStack))
            .triage
            .slate,
        const ['c-1', 'c-2', 'c-3', 'x-1'],
      );
    });

    testWidgets(
        'les bornes du stepper ne dépendent plus du pool : [$kTriageGoalMin, '
        '$kTriageGoalMax]', (tester) async {
      // Un slate de 3 seulement — l'ancien stepper aurait été bloqué à 3.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2', 'c-3'])
        ],
      ));
      await tester.pump();

      for (var i = 0; i < kTriageGoalMax; i++) {
        await tester.tap(find.bySemanticsLabel('Plus d\'articles'));
        await tester.pump();
      }
      expectGoalControl(tester, kTriageGoalMax);

      for (var i = 0; i < kTriageGoalMax; i++) {
        await tester.tap(find.bySemanticsLabel('Moins d\'articles'));
        await tester.pump();
      }
      expectGoalControl(tester, kTriageGoalMin);
    });

    // ── Contrôle d'objectif : hiérarchie discrète (reprise PO 10/08) ──────

    testWidgets(
        'les ronds encadrent immédiatement le chiffre, ils ne sont plus aux '
        'deux extrémités de la largeur', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          carousel: _carousel(const ['x-1']),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2', 'c-3'])
        ],
      ));
      await tester.pump();

      final control = find.byType(TriageGoalControl);
      final controlBox = tester.getRect(control);
      final lead = tester.getRect(
        find.descendant(of: control, matching: find.text('Garder')),
      );
      final minus = tester.getRect(find.bySemanticsLabel('Moins d\'articles'));
      final plus = tester.getRect(find.bySemanticsLabel('Plus d\'articles'));
      final number = tester.getRect(
        find.descendant(
          of: control,
          matching: find.text('$kTriageGoalDefault'),
        ),
      );

      // Ordre horizontal : « Garder » − N + « articles ».
      expect(lead.right, lessThanOrEqualTo(minus.left));
      expect(minus.right, lessThanOrEqualTo(number.left));
      expect(plus.left, greaterThanOrEqualTo(number.right));

      // Groupés : les ronds **encadrent** le chiffre au lieu d'être poussés aux
      // deux extrémités de la largeur (le cercle visible n'est qu'un décor
      // centré dans la boîte tactile, d'où les ~9px d'écart de chaque côté).
      expect(number.left - minus.right, lessThan(12));
      expect(plus.left - number.right, lessThan(12));
      // Le `+` ne touche jamais le bord droit : c'est la fin de la phrase qui
      // occupe le reste de la largeur. L'ancien rendu le poussait au bord.
      final trailing = tester.getRect(
        find.descendant(of: control, matching: find.text('articles')),
      );
      expect(plus.right, lessThanOrEqualTo(trailing.left));
      expect(trailing.right, greaterThan(plus.right));
      expect(controlBox.right - plus.right, greaterThan(40));

      // Cible tactile réelle de 44 (le cercle visible, lui, reste à 26).
      expect(minus.height, moreOrLessEquals(kTriageTargetControlHeight));
      expect(minus.width, moreOrLessEquals(kTriageTargetControlHeight));
    });

    testWidgets(
        'le chiffre réglable est discret : 13px, medium, textSecondary — plus '
        'de Courier gras en accent', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2', 'c-3'])
        ],
      ));
      await tester.pump();

      final colors = FacteurPalettes.light;
      final number = tester.widget<Text>(
        find.descendant(
          of: find.byType(TriageGoalControl),
          matching: find.text('$kTriageGoalDefault'),
        ),
      );
      expect(number.style!.fontSize, lessThanOrEqualTo(13));
      expect(number.style!.fontWeight, FontWeight.w600);
      // `textSecondary` (reprise PO 11/08) : le chiffre reste le repère de la
      // ligne mais ne rivalise plus avec le titre de la carte.
      expect(number.style!.color, colors.textSecondary);
      expect(number.style!.color, isNot(colors.sectionEssentiel));
    });

    /// Le rond [label] est-il éteint **et** inerte ? (`onTap: null` ⇒
    /// l'`InkWell` ne prend même pas le tap — une opacité seule laisserait un
    /// bouton mort mais tappable.)
    void expectRoundDisabled(WidgetTester tester, String label) {
      final round = find.bySemanticsLabel(label);
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: round, matching: find.byType(InkWell)),
            )
            .onTap,
        isNull,
        reason: '$label ne doit plus être actionnable à sa borne',
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: round, matching: find.byType(Opacity)),
            )
            .opacity,
        lessThan(1.0),
        reason: '$label doit être visiblement éteint à sa borne',
      );
    }

    // ── Nudge « tu peux t'arrêter là » (33.4) ────────────────────────────

    /// Slate de 8, avec [passes] refus enchaînés en tête.
    Override triageAfterPasses(int passes, {bool stopNudgeDismissed = false}) =>
        triageWith(
          slate: [for (var i = 1; i <= 8; i++) 'c-$i'],
          decisions: {
            for (var i = 1; i <= passes; i++)
              'c-$i': TriageEntry(
                contentId: 'c-$i',
                decision: TriageDecision.pass,
                rank: i,
                via: TriageVia.swipe,
              ),
          },
          stopNudgeDismissed: stopNudgeDismissed,
        );

    Future<void> pumpAfterPasses(WidgetTester tester, int passes) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(8),
          onTapArticle: (_) {},
        ),
        overrides: [triageAfterPasses(passes)],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
        'le nudge n\'apparaît pas avant $kTriageStopNudgeThreshold refus '
        'enchaînés', (tester) async {
      // En deçà, un utilisateur qui écarte quatre papiers fait simplement son
      // travail de tri : le lui faire remarquer serait du bruit.
      await pumpAfterPasses(tester, kTriageStopNudgeThreshold - 1);

      expect(
        find.text('Rien ne t\'accroche ? Tu peux t\'arrêter là.'),
        findsNothing,
      );
    });

    testWidgets(
        'le nudge apparaît au ${kTriageStopNudgeThreshold}e refus enchaîné',
        (tester) async {
      await pumpAfterPasses(tester, kTriageStopNudgeThreshold);

      expect(
        find.text('Rien ne t\'accroche ? Tu peux t\'arrêter là.'),
        findsOneWidget,
      );
    });

    testWidgets('un article gardé fait disparaître le nudge, sans rien fermer',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(8),
          onTapArticle: (_) {},
        ),
        overrides: [triageAfterPasses(kTriageStopNudgeThreshold)],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Arrêter le tri'), findsOneWidget);

      await tester.tap(find.text('Je garde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Arrêter le tri'), findsNothing,
          reason: 'le compteur de refus enchaînés repart de zéro tout seul');
    });

    testWidgets('« Arrêter le tri » termine le tri sur les gardés obtenus',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(8),
          onTapArticle: (_) {},
        ),
        overrides: [triageAfterPasses(kTriageStopNudgeThreshold)],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Arrêter le tri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(EssentielTriageStack), findsNothing);
      // 0 gardé : l'état vide sobre, jamais un objectif non atteint affiché
      // comme un échec.
      expect(find.text('Rien gardé aujourd\'hui.'), findsOneWidget);
      expect(find.byType(TriageGoalControl), findsNothing);
    });

    testWidgets('la croix ferme le nudge sans arrêter le tri', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(8),
          onTapArticle: (_) {},
        ),
        overrides: [triageAfterPasses(kTriageStopNudgeThreshold)],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byTooltip('Fermer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Arrêter le tri'), findsNothing);
      expect(find.byType(EssentielTriageStack), findsOneWidget,
          reason: 'fermer le bandeau n\'arrête pas le tri');
    });

    testWidgets('un nudge déjà fermé ne réapparaît pas au remontage',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(8),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageAfterPasses(kTriageStopNudgeThreshold,
              stopNudgeDismissed: true),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Arrêter le tri'), findsNothing);
    });

    testWidgets(
        'ordre vertical avec le nudge : actions → nudge → barre → objectif → '
        'gardés', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(8),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: [for (var i = 1; i <= 8; i++) 'c-$i'],
            decisions: {
              'c-1': const TriageEntry(
                contentId: 'c-1',
                decision: TriageDecision.keep,
                rank: 1,
                via: TriageVia.swipe,
              ),
              for (var i = 2; i <= kTriageStopNudgeThreshold + 1; i++)
                'c-$i': TriageEntry(
                  contentId: 'c-$i',
                  decision: TriageDecision.pass,
                  rank: i,
                  via: TriageVia.swipe,
                ),
            },
          ),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final actionsBottom = tester.getBottomLeft(find.text('Je garde')).dy;
      final nudgeY = tester.getTopLeft(find.text('Arrêter le tri')).dy;
      final barY = tester.getTopLeft(find.byType(TriageProgressBar)).dy;
      final controlY = tester.getTopLeft(find.byType(TriageGoalControl)).dy;
      final keptY = tester.getTopLeft(find.text('TES ARTICLES')).dy;

      expect(nudgeY, greaterThan(actionsBottom));
      expect(barY, greaterThan(nudgeY));
      expect(controlY, greaterThan(barY));
      expect(keptY, greaterThan(controlY));
    });

    // ── Alimentation continue de la pile (33.4) ──────────────────────────

    testWidgets(
        'la pile va chercher la suite AVANT de sécher, sans aucune UI '
        'd\'attente', (tester) async {
      final repo = _MockEssentielRepository();
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [moreJson('n-1'), moreJson('n-2')]);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielRepositoryProvider.overrideWithValue(repo),
          // 1 décidé sur 3 ⇒ 2 restants = la ligne de flottaison.
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3'],
            decisions: decisionsKeeping(1, 1),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Un lot de 5, une seule fois — et rien qui clignote à l'écran.
      verify(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: kTriagePrefetchBatch,
          )).called(1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(EssentielTriageStack), findsOneWidget);

      // Les articles rapatriés rejoignent le slate, en queue.
      expect(
        tester
            .widget<EssentielTriageStack>(find.byType(EssentielTriageStack))
            .triage
            .slate,
        const ['c-1', 'c-2', 'c-3', 'n-1', 'n-2'],
      );
    });

    testWidgets('pile pleine : aucun prefetch', (tester) async {
      final repo = _MockEssentielRepository();
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const []);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(6),
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielRepositoryProvider.overrideWithValue(repo),
          triageWith(slate: [for (var i = 1; i <= 6; i++) 'c-$i']),
        ],
      ));
      await tester.pump();
      await tester.pump();

      verifyNever(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          ));
    });

    testWidgets('pool sec : un seul appel, pas un par frame', (tester) async {
      final repo = _MockEssentielRepository();
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const []);

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielRepositoryProvider.overrideWithValue(repo),
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3'],
            decisions: decisionsKeeping(1, 1),
          ),
        ],
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      verify(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).called(1);
    });

    testWidgets('au plancher, le rond « − » n\'est plus actionnable',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2', 'c-3'], goal: kTriageGoalMin)
        ],
      ));
      await tester.pump();

      expectRoundDisabled(tester, 'Moins d\'articles');
    });

    testWidgets('au plafond, le rond « + » n\'est plus actionnable',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2', 'c-3'], goal: kTriageGoalMax)
        ],
      ));
      await tester.pump();

      expectRoundDisabled(tester, 'Plus d\'articles');
    });

    // ── Barre de progression des gardés (33.4) ───────────────────────────

    List<AnimatedContainer> progressSegments(WidgetTester tester) => tester
        .widgetList<AnimatedContainer>(find.descendant(
          of: find.byType(TriageProgressBar),
          matching: find.byType(AnimatedContainer),
        ))
        .toList();

    testWidgets(
        'un segment par article de la CIBLE, rempli par les gardés — et aucun '
        'second compteur', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(4),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3', 'c-4'],
            decisions: decisionsKeeping(1, 1),
          ),
        ],
      ));
      await tester.pump();

      final segments = progressSegments(tester);
      expect(segments.length, kTriageGoalDefault,
          reason: 'un segment par article de la cible, plus par article du '
              'slate — le slate n\'est plus borné');

      expect(
        [for (final s in segments) s.constraints?.maxHeight],
        List.filled(kTriageGoalDefault, kTriageProgressSegmentHeight),
        reason: 'aucun segment courant : la progression est cumulative',
      );

      final colors = FacteurPalettes.light;
      Color colorOf(int i) => (segments[i].decoration! as BoxDecoration).color!;
      // Contraste acquis/restant (reprise PO 11/08) : le rempli monte à 0.45,
      // le vide descend à 0.45 du filet.
      expect(colorOf(0), colors.sectionEssentiel.withValues(alpha: 0.45),
          reason: 'un gardé');
      expect(colorOf(1), colors.border.withValues(alpha: 0.45),
          reason: 'pas encore gardé');
      expect(colorOf(4), colors.border.withValues(alpha: 0.45));

      // La barre ne réintroduit aucun compteur : les nombres restent au
      // contrôle sous elle (et dans la sémantique).
      expect(
        find.descendant(
          of: find.byType(TriageProgressBar),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(find.textContaining('sur'), findsNothing);
    });

    testWidgets('la barre avance sur un gardé, pas sur un refus',
        (tester) async {
      // C'est le renversement de la 33.4 : refuser fait avancer dans la pile,
      // pas vers l'objectif.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(3),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2', 'c-3'])
        ],
      ));
      await tester.pump();

      final colors = FacteurPalettes.light;
      int filled() => progressSegments(tester)
          .where((s) =>
              (s.decoration! as BoxDecoration).color ==
              colors.sectionEssentiel.withValues(alpha: 0.45))
          .length;

      expect(filled(), 0);

      await tester.tap(find.bySemanticsLabel('Pas pour moi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(filled(), 0, reason: 'un refus ne rapproche pas de la cible');

      await tester.tap(find.text('Je garde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(filled(), 1);
    });

    testWidgets('la sémantique porte le chiffre que la barre n\'affiche pas',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: articlesUpTo(4),
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(
            slate: const ['c-1', 'c-2', 'c-3', 'c-4'],
            decisions: decisionsKeeping(2, 2),
          ),
        ],
      ));
      await tester.pump();

      expect(
        find.bySemanticsLabel('Articles gardés : 2 sur $kTriageGoalDefault'),
        findsOneWidget,
      );
    });

    testWidgets(
        'balises 2A — avec image : une seule (la primaire couverture), '
        'le thème n\'apparaît pas', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(
              rank: 1,
              thumbnailUrl: 'https://example.com/1.jpg',
              sourceCount: 4,
              divergenceLevel: 'high',
            ),
            // Carte du dessous neutralisée (pas de thème) pour ne pas polluer
            // les compteurs de balises.
            _article(rank: 2, theme: null),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      expect(find.byKey(const Key('triage-coverage-chip')), findsOneWidget);
      expect(find.byType(DivergenceInlineBadge), findsOneWidget);
      expect(find.text('Technologie'), findsNothing,
          reason: 'avec image, une seule balise : la primaire suffit');
    });

    testWidgets(
        'balises 2A — sans image : jusqu\'à deux (primaire puis thème), et '
        'thème + fraîcheur quand il n\'y a pas de couverture', (tester) async {
      // Cas 1 : couverture + thème.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1, sourceCount: 4, divergenceLevel: 'high'),
            _article(rank: 2, theme: null),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      expect(find.byKey(const Key('triage-coverage-chip')), findsOneWidget);
      expect(find.text('Technologie'), findsOneWidget);

      // Cas 2 : pas de couverture → thème + fraîcheur (horloge).
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1),
            _article(rank: 2, theme: null),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      expect(find.byKey(const Key('triage-coverage-chip')), findsNothing);
      expect(find.text('Technologie'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TriageSwipeCard),
          matching: find.byIcon(PhosphorIcons.clock()),
        ),
        findsOneWidget,
        reason: 'la fraîcheur complète le thème sur la carte du dessus',
      );
    });

    testWidgets(
        'un tap sur la carte du dessus appelle onTapArticle SANS décider',
        (tester) async {
      EssentielArticle? tapped;
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (a) => tapped = a,
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      await tester.tap(find.byType(TriageSwipeCard));
      await tester.pump();

      expect(tapped?.contentId, 'c-1');
      // Aucune décision : la pile n'a pas bougé.
      expectGoalControl(tester, kTriageGoalDefault);
      expect(find.byKey(const ValueKey('triage-kept-row-c-1')), findsNothing);
    });

    testWidgets(
        'lecture au retour = gardé : l\'id tapé passé dans consumed fait '
        'avancer la pile et bascule l\'article dans « TES ARTICLES »',
        (tester) async {
      final repo = _MockEssentielRepository();
      final analytics = _MockAnalytics();
      when(() => repo.postTriage(
            digestDate: any(named: 'digestDate'),
            slateSize: any(named: 'slateSize'),
            decisions: any(named: 'decisions'),
          )).thenAnswer((_) async => true);
      when(() => analytics.trackEssentielTriage(
            decision: any(named: 'decision'),
            contentId: any(named: 'contentId'),
            rank: any(named: 'rank'),
            slateSize: any(named: 'slateSize'),
            goal: any(named: 'goal'),
            decidedVia: any(named: 'decidedVia'),
            latencyMs: any(named: 'latencyMs'),
          )).thenAnswer((_) async {});
      when(() => analytics.trackEssentielTriageSession(
            slateSize: any(named: 'slateSize'),
            goal: any(named: 'goal'),
            goalReached: any(named: 'goalReached'),
            endedBy: any(named: 'endedBy'),
            autoFetches: any(named: 'autoFetches'),
            kept: any(named: 'kept'),
            later: any(named: 'later'),
            passed: any(named: 'passed'),
            durationMs: any(named: 'durationMs'),
          )).thenAnswer((_) async {});
      when(() => analytics.trackEssentielTriageStopNudge(
            action: any(named: 'action'),
            consecutivePass: any(named: 'consecutivePass'),
            keptCount: any(named: 'keptCount'),
            goal: any(named: 'goal'),
          )).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielRepositoryProvider.overrideWithValue(repo),
          analyticsServiceProvider.overrideWithValue(analytics),
          triageWith(slate: const ['c-1', 'c-2']),
        ],
      ));
      await tester.pump();

      // Ouvre depuis la pile — condition de l'auto-keep : un article lu qui
      // n'a PAS été ouvert depuis la pile ne doit jamais être auto-gardé.
      await tester.tap(find.byType(TriageSwipeCard));
      await tester.pump();

      // Retour de lecture : la session marque l'article consommé.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EssentielHiFiCard)),
      );
      container.read(consumedContentIdsProvider.notifier).state = {'c-1'};
      await tester.pump(); // rebuild → auto-keep posté après la frame
      await tester.pump(); // la décision s'applique
      await tester.pump(const Duration(milliseconds: 300)); // AnimatedSize

      expect(find.byKey(const ValueKey('triage-kept-row-c-1')), findsOneWidget);
      expect(find.text('TES ARTICLES'), findsOneWidget);
      expectGoalControl(tester, kTriageGoalDefault);
      // La pile a avancé sur la carte suivante.
      expect(
        find.descendant(
          of: find.byType(TriageSwipeCard),
          matching: find.text('Titre 2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'un article lu SANS avoir été ouvert depuis la pile n\'est jamais '
        'auto-gardé (hydratation serveur au cold-boot)', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          triageWith(slate: const ['c-1', 'c-2'])
        ],
      ));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(EssentielHiFiCard)),
      );
      container.read(consumedContentIdsProvider.notifier).state = {'c-1'};
      await tester.pump();
      await tester.pump();

      // Pas de tap préalable ⇒ pas d'auto-keep : la pile n'a pas bougé.
      expectGoalControl(tester, kTriageGoalDefault);
      expect(find.byKey(const ValueKey('triage-kept-row-c-1')), findsNothing);
    });
  });

  // ── A1 (passe PO 09/08) — jamais l'en-tête seul ────────────────────────────
  //
  // Le défaut : la carte se réduisait à son en-tête au-dessus du vide. Cause
  // trouvée à l'instrumentation — `_buildSkeletonState` laisse dans le notifier
  // une coquille `EssentielSection(articles: [])`, et
  // `_reconcilePlacementThenSync` publie un `_compose()` **non-squelette**
  // pendant le bootstrap (il n'est délibérément pas gardé par
  // `_bootstrapping`) : la coquille vide était donc rendue comme une vraie
  // carte, `articles.isEmpty` ⇒ ni pile, ni silhouette, ni tuile.
  //
  // Ce banc verrouille la **sortie** (la carte, garde-fou terminal), pas la
  // cause amont : quelle que soit la raison pour laquelle la carte est montée
  // sans contenu définitif, elle rend la silhouette.
  group('EssentielHiFiCard — jamais réduite à son en-tête (A1)', () {
    /// La carte ne doit jamais s'arrêter à `_Header` + le gap de 6 px : sa
    /// colonne porte toujours **au moins** un troisième enfant (silhouette,
    /// pile ou tuile).
    void expectBodyBelowHeader(WidgetTester tester) {
      final column = tester.widget<Column>(
        find
            .descendant(
              of: find.byType(EssentielHiFiCard),
              matching: find.byType(Column),
            )
            .first,
      );
      expect(
        column.children.length,
        greaterThan(2),
        reason: 'en-tête + gap seulement ⇒ la carte est un en-tête nu',
      );
    }

    testWidgets('héros pas encore résolu (articles vides) → silhouette',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(articles: const [], onTapArticle: (_) {}),
      ));
      await tester.pump();

      expect(find.byType(TriageStackSkeleton), findsOneWidget);
      expectBodyBelowHeader(tester);
    });

    testWidgets('articles présents mais tri pas encore hydraté → silhouette',
        (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielTriageProvider.overrideWith(
            (ref) => EssentielTriageNotifier(
              ref,
              initialState: const EssentielTriageState(dayKey: 'test'),
            ),
          ),
        ],
      ));
      await tester.pump();

      expect(find.byType(TriageStackSkeleton), findsOneWidget);
      expectBodyBelowHeader(tester);
    });

    testWidgets(
        'slate figé mais haut de pile introuvable dans le pool → silhouette, '
        'jamais un corps vide', (tester) async {
      // Le cas réel : « Plus d'articles » a persisté des `contentId` de
      // carrousel, absents du pool à l'hydratation suivante.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1)],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielTriageProvider.overrideWith(
            (ref) => EssentielTriageNotifier(
              ref,
              initialState: const EssentielTriageState(
                dayKey: 'test',
                slate: ['c-disparu'],
                hydrated: true,
              ),
            ),
          ),
        ],
      ));
      await tester.pump();

      expect(find.byType(TriageStackSkeleton), findsOneWidget);
      expectBodyBelowHeader(tester);
    });
  });

  // ── A3 (passe PO 09/08) — la pile ne tressaute pas au swipe ───────────────
  //
  // Deux mécaniques étaient candidates ; la mesure en départage une seule.
  //
  // 1. **Promotion — écartée.** L'hypothèse était que `_completeExit()` remet
  //    `_promotion` à 0 avant que `onDone()` n'ait fait avancer l'index, d'où un
  //    reclaquement 1.0 → 0.96 de la carte du dessous. Le banc ci-dessous, qui
  //    lit l'échelle **rendue** frame par frame, montre que la baisse tombe
  //    exactement sur la frame de promotion (les deux effets sont dans le même
  //    microtask, donc dans la même frame) : aucune régression visible.
  //    `_completeExit()` n'a donc **pas** été touché. Le banc reste, comme
  //    verrou.
  // 2. **`AnimatedSize` imbriqués — la cause.** La colonne et le slot de carte
  //    animaient la même hauteur. `RenderAnimatedSize` bascule en état
  //    `unstable` quand la taille de son enfant change plusieurs frames de
  //    suite : il cesse d'animer, après une frame de stalle et un saut de
  //    re-ciblage. Trace mesurée sur le build cassé (sonde de géométrie par
  //    frame, web staging), position de la barre d'actions : 607.3 → 572.2 →
  //    542.9 → 518.8 → **485.3** → 474.0 … soit des pas de 35.1, 29.3, 24.1,
  //    **33.5** (rebond), 11.3 — au lieu d'une easeOutCubic monotone
  //    décroissante.
  group('EssentielHiFiCard — pile stable au swipe (A3)', () {
    setUp(() {
      registerFallbackValue(<Map<String, dynamic>>[]);
    });

    /// L'`Opacity` **de promotion** de la carte du dessous (le wrapper le plus
    /// externe du slot arrière) — depuis la reprise PO du 10/08, la profondeur
    /// n'est plus portée que par elle (plus de `Transform.scale`).
    Finder backCardFinder() => find
        .descendant(
          of: find.byKey(const ValueKey('triage-back')),
          matching: find.byType(Opacity),
        )
        .first;

    /// Opacité **rendue** de la carte du dessous, lue sur l'arbre (ce que l'œil
    /// voit) plutôt que sur `_promotion`.
    double? backOpacity(WidgetTester tester) {
      final finder = backCardFinder();
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<Opacity>(finder).opacity;
    }

    /// Rectangle **peint** (global, transformes d'ancêtres compris) de la carte
    /// du dessous : `getRect` applique un éventuel `Transform.scale` d'ancêtre,
    /// donc un retrait latéral s'y verrait. Sert à verrouiller « à fleur du
    /// cadre ».
    Rect? backRect(WidgetTester tester) {
      final finder = backCardFinder();
      if (finder.evaluate().isEmpty) return null;
      return tester.getRect(finder);
    }

    testWidgets(
        'la carte du dessous reste à fleur du cadre (jamais décalée) et monte '
        'en opacité jusqu\'à sa promotion', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _MockEssentielRepository();
      final analytics = _MockAnalytics();
      when(() => repo.postTriage(
            digestDate: any(named: 'digestDate'),
            slateSize: any(named: 'slateSize'),
            decisions: any(named: 'decisions'),
          )).thenAnswer((_) async => true);
      when(() => analytics.trackEssentielTriage(
            decision: any(named: 'decision'),
            contentId: any(named: 'contentId'),
            rank: any(named: 'rank'),
            slateSize: any(named: 'slateSize'),
            goal: any(named: 'goal'),
            decidedVia: any(named: 'decidedVia'),
            latencyMs: any(named: 'latencyMs'),
          )).thenAnswer((_) async {});
      when(() => analytics.trackEssentielTriageSession(
            slateSize: any(named: 'slateSize'),
            goal: any(named: 'goal'),
            goalReached: any(named: 'goalReached'),
            endedBy: any(named: 'endedBy'),
            autoFetches: any(named: 'autoFetches'),
            kept: any(named: 'kept'),
            later: any(named: 'later'),
            passed: any(named: 'passed'),
            durationMs: any(named: 'durationMs'),
          )).thenAnswer((_) async {});
      when(() => analytics.trackEssentielTriageStopNudge(
            action: any(named: 'action'),
            consecutivePass: any(named: 'consecutivePass'),
            keptCount: any(named: 'keptCount'),
            goal: any(named: 'goal'),
          )).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2), _article(rank: 3)],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielRepositoryProvider.overrideWithValue(repo),
          analyticsServiceProvider.overrideWithValue(analytics),
          essentielTriageProvider.overrideWith(
            (ref) => EssentielTriageNotifier(
              ref,
              initialState: const EssentielTriageState(
                dayKey: 'test',
                slate: ['c-1', 'c-2', 'c-3'],
                hydrated: true,
              ),
            ),
          ),
        ],
      ));
      await tester.pump();

      // Geste réel jusqu'au-delà du seuil, puis relâchement : l'anim de sortie
      // court, la promotion suit. On échantillonne **chaque frame**.
      // La décision a-t-elle atterri ? La ligne du gardé `c-1` apparaît dans la
      // **même** frame que la promotion — c'est la borne exacte de la fenêtre
      // « avant promotion ». (Ne pas se fier à la disparition de « Titre 1 » :
      // il reste rendu, justement dans cette ligne de gardé.)
      bool promoted() => find
          .byKey(const ValueKey('triage-kept-row-c-1'))
          .evaluate()
          .isNotEmpty;

      // Cadre de référence = la carte du dessus au repos (elle dimensionne la
      // pile). La carte du dessous ne se translate pas : elle doit rester sur
      // ces mêmes bords tout du long — sinon elle est « décalée » d'un côté,
      // exactement le défaut corrigé (une carte réduite était en retrait).
      final frame = tester.getRect(find.byType(TriageSwipeCard));
      void expectFlush(String when) {
        final back = backRect(tester);
        expect(back, isNotNull, reason: 'carte du dessous introuvable ($when)');
        expect(back!.left, closeTo(frame.left, 0.5),
            reason: 'bord gauche décalé ($when) : $back vs $frame');
        expect(back.right, closeTo(frame.right, 0.5),
            reason: 'bord droit décalé ($when) : $back vs $frame');
      }

      expectFlush('au repos');
      final opacities = <double>[backOpacity(tester)!];
      expect(opacities.first, closeTo(kTriageBackCardOpacity, 0.001),
          reason: 'au repos la carte du dessous est estompée');

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TriageSwipeCard)),
      );
      for (var i = 0; i < 10 && !promoted(); i++) {
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expectFlush('pendant le geste');
        final o = backOpacity(tester);
        if (o != null) opacities.add(o);
      }
      await gesture.up();

      // Frames de l'anim de sortie, jusqu'à la promotion **exclue**.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (promoted()) break;
        expectFlush('pendant la sortie');
        final o = backOpacity(tester);
        if (o != null) opacities.add(o);
      }
      await tester.pumpAndSettle();

      expect(promoted(), isTrue, reason: 'le swipe doit avoir décidé');
      expect(opacities.length, greaterThan(4),
          reason: 'le geste doit produire des frames à échantillonner');
      expect(opacities.toSet().length, greaterThan(1),
          reason: 'banc vide : l\'opacité rendue ne bouge jamais');
      for (var i = 1; i < opacities.length; i++) {
        expect(
          opacities[i],
          greaterThanOrEqualTo(opacities[i - 1] - 0.0001),
          reason: 'la carte du dessous s\'estompe à la frame $i : '
              '${opacities[i - 1]} → ${opacities[i]} (suite : $opacities)',
        );
      }
      // Elle finit pleinement opaque, pas à mi-chemin.
      expect(opacities.last, closeTo(1.0, 0.001));
    });

    testWidgets(
        'la carte du dessous est rognée au MÊME arrondi que celle du dessus : '
        'plus aucun coin coloré autour du cadre', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Carte du dessus **sans image** (donc courte, titre sur peu de lignes),
      // carte du dessous **avec** image (donc plus haute) : c'est exactement la
      // configuration qui laissait voir l'image du dessous dans les deux
      // encoches laissées par les coins arrondis de la carte du dessus.
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [
            _article(rank: 1),
            _article(rank: 2, thumbnailUrl: 'https://example.com/2.jpg'),
          ],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielTriageProvider.overrideWith(
            (ref) => EssentielTriageNotifier(
              ref,
              initialState: const EssentielTriageState(
                dayKey: 'test',
                slate: ['c-1', 'c-2'],
                hydrated: true,
              ),
            ),
          ),
        ],
      ));
      await tester.pump();

      final slot = find.byKey(const ValueKey('triage-back'));
      expect(slot, findsOneWidget);

      // Le rognage est au rayon de la carte, pas au rectangle droit du `Stack`.
      final clip = tester.widget<ClipRRect>(
        find.descendant(of: slot, matching: find.byType(ClipRRect)).first,
      );
      expect(clip.borderRadius, BorderRadius.circular(FacteurRadius.large));

      // Et la zone rognée est **exactement** le gabarit de la carte du dessus :
      // rien de la carte du dessous ne peut donc peindre au-delà.
      final frame = tester.getRect(find.byType(TriageSwipeCard));
      final clipped = tester.getRect(
        find.descendant(of: slot, matching: find.byType(ClipRRect)).first,
      );
      expect(clipped.left, closeTo(frame.left, 0.5));
      expect(clipped.right, closeTo(frame.right, 0.5));
      expect(clipped.top, closeTo(frame.top, 0.5));
      expect(clipped.bottom, closeTo(frame.bottom, 0.5),
          reason: 'la carte du dessous, plus haute, doit être rognée au bas de '
              'la carte du dessus');
    });

    testWidgets(
        'un seul AnimatedSize anime la hauteur de la pile : aucun n\'est '
        'imbriqué dans un autre', (tester) async {
      await tester.pumpWidget(_wrap(
        EssentielHiFiCard(
          articles: [_article(rank: 1), _article(rank: 2)],
          onTapArticle: (_) {},
        ),
        overrides: [
          essentielTriageProvider.overrideWith(
            (ref) => EssentielTriageNotifier(
              ref,
              initialState: const EssentielTriageState(
                dayKey: 'test',
                slate: ['c-1', 'c-2'],
                hydrated: true,
              ),
            ),
          ),
        ],
      ));
      await tester.pump();

      // `RenderAnimatedSize` bascule en état `unstable` — une frame de stalle
      // puis un saut — dès que la taille de son enfant change plusieurs frames
      // d'affilée. C'est exactement ce que fait un `AnimatedSize` imbriqué dans
      // un autre. L'invariant est donc structurel : aucun `AnimatedSize` de la
      // pile n'est l'ancêtre d'un autre.
      for (final element in find.byType(AnimatedSize).evaluate()) {
        final ancestors = <Element>[];
        element.visitAncestorElements((a) {
          if (a.widget is EssentielTriageStack) return false;
          if (a.widget is AnimatedSize) ancestors.add(a);
          return true;
        });
        expect(
          ancestors,
          isEmpty,
          reason: 'AnimatedSize imbriqué : les deux animent la même hauteur, '
              'ce qui fait sauter la barre d\'actions',
        );
      }
    });
  });
}

class _MockEssentielRepository extends Mock implements EssentielRepository {}

class _MockAnalytics extends Mock implements AnalyticsService {}

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
