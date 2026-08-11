// PR-4 — ordre des blocs de la Tournée par le score top-3 : gel à la journée
// (anti-saut pendant le fan-out), rejeu de l'ordre persisté, portée du
// classement (plus large que les seuls favoris) et arbitrage face à l'ordre
// manuel. Le helper pur est couvert à part
// (`test/features/flux_continu/utils/section_score_order_test.dart`) ; ici on
// teste le **câblage** dans le notifier.
import 'dart:convert';
import 'dart:io';

import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flux_continu_settle.dart';

class _MockDigestRepository extends Mock implements DigestRepository {}

class _MockFeedRepository extends Mock implements FeedRepository {}

class _MockFluxContinuRepository extends Mock
    implements FluxContinuRepository {}

class _StubEssentielRepository implements EssentielRepository {
  // Story 33.3 — « Plus d'articles ? » ne concerne pas ces tests ; le stub
  // renvoie « rien d'inédit » pour rester conforme à l'interface.
  @override
  Future<List<Map<String, dynamic>>?> fetchMore({
    required List<String> excludeIds,
    int limit = 2,
  }) async =>
      const [];

  @override
  Future<EssentielFetchResult?> fetch({bool? serein, DateTime? date}) async =>
      (articles: const <EssentielArticle>[], newSinceMorning: 0, carousel: null);

  @override
  Future<bool> postTriage({
    required String digestDate,
    required int slateSize,
    required List<Map<String, dynamic>> decisions,
  }) async =>
      true;
}

class _StubUserInterestsNotifier extends UserInterestsNotifier {
  _StubUserInterestsNotifier(this._initial);
  final UserInterestsState _initial;
  @override
  Future<UserInterestsState> build() async => _initial;
}

class _StubUserSourcesStateNotifier extends UserSourcesStateNotifier {
  _StubUserSourcesStateNotifier(this._initial);
  final UserSourcesState _initial;
  @override
  Future<UserSourcesState> build() async => _initial;
}

class _StubUserSourcesNotifier extends UserSourcesNotifier {
  _StubUserSourcesNotifier(this._initial);
  final List<Source> _initial;
  @override
  Future<List<Source>> build() async => _initial;
}

/// [score] non nul ⇒ chaque article porte un `recommendationReason` : c'est le
/// seul input du classement des blocs.
FeedResponse _feed(List<String> ids, {double? score}) {
  return FeedResponse(
    items: [
      for (final id in ids)
        Content(
          id: id,
          title: 'title-$id',
          url: 'https://x.test/$id',
          contentType: ContentType.article,
          publishedAt: DateTime(2026, 1, 1),
          source: Source(id: 's', name: 'S', type: SourceType.article),
          recommendationReason: score == null
              ? null
              : RecommendationReason(label: 'Recommandé', scoreTotal: score),
        ),
    ],
    pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
    carousels: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _MockFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('flux_score_order_hive').path);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    when(() => digestRepo.fetchBothDigests())
        .thenThrow(Exception('mock: no digest'));
    when(() => fluxRepo.getTopThemes())
        .thenAnswer((_) async => const <TopTheme>[]);
  });

  /// [counts] fixe le nombre d'articles par thème ; [scores] leur `score_total`
  /// (thème absent ⇒ articles non scorés ⇒ section hors du classement).
  void stubThemes(
    Map<String, int> counts, {
    Map<String, double> scores = const {},
  }) {
    when(() => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          sourceId: any(named: 'sourceId'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        )).thenAnswer((invocation) async {
      final theme = invocation.namedArguments[#theme] as String?;
      if (theme == null) return _feed(const []);
      final n = counts[theme] ?? 0;
      return _feed(
        [for (var i = 0; i < n; i++) '$theme$i'],
        score: scores[theme],
      );
    });
  }

  Future<ProviderContainer> buildContainer({
    required List<String> themeSlugs,
    List<TopTheme> topThemes = const [],
  }) async {
    when(() => fluxRepo.getTopThemes()).thenAnswer((_) async => topThemes);
    final container = ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider
            .overrideWithValue(_StubEssentielRepository()),
        userInterestsProvider.overrideWith(
          () => _StubUserInterestsNotifier(
            UserInterestsState(
              themes: const [],
              customTopics: const [],
              favorites: [
                for (final slug in themeSlugs) ThemeFavoriteRef(slug: slug),
              ],
              favoriteCount: themeSlugs.length,
              favoriteCap: 7,
            ),
          ),
        ),
        userSourcesStateProvider.overrideWith(
          () => _StubUserSourcesStateNotifier(
            const UserSourcesState(
              sources: [],
              favorites: [],
              favoriteCount: 0,
              favoriteCap: 7,
            ),
          ),
        ),
        userSourcesProvider
            .overrideWith(() => _StubUserSourcesNotifier(const [])),
        sereinToggleProvider
            .overrideWith((ref) => SereinToggleNotifier(ref, null)),
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
      ],
    );
    await container.read(userSourcesStateProvider.future);
    await container.read(userSourcesProvider.future);
    await container.read(userInterestsProvider.future);
    return container;
  }

  List<String> themeOrder(FluxContinuState state) => state.sections
      .whereType<FeedThemeSection>()
      .map((s) => s.themeSlug ?? '')
      .toList();

  /// Ordres successifs observés, doublons consécutifs écrasés — donc un élément
  /// par **changement d'ordre** effectivement visible par l'utilisateur.
  List<List<String>> orderChanges(List<List<String>> observed) {
    final out = <List<String>>[];
    for (final o in observed) {
      if (out.isEmpty || out.last.join('|') != o.join('|')) out.add(o);
    }
    return out;
  }

  /// Enregistre l'ordre des sections thème à **chaque** émission non squelette.
  List<List<String>> watchOrders(ProviderContainer container) {
    final observed = <List<String>>[];
    container.listen<AsyncValue<FluxContinuState>>(
      fluxContinuProvider,
      (_, next) {
        final s = next.valueOrNull;
        if (s == null || s.isSkeleton) return;
        observed.add(themeOrder(s));
      },
      fireImmediately: true,
    );
    return observed;
  }

  String scoreOrderBlob(String day, List<String> keys) =>
      jsonEncode({'day': day, 'keys': keys});

  group('gel de l\'ordre à la journée', () {
    test(
        'aucun saut pendant le fan-out : un seul changement d\'ordre, à la '
        'complétion', () async {
      // 'a' est le bloc le plus pauvre (1 article) mais arrive en tête des
      // favoris : il doit y rester tant que le fan-out n'est pas terminé.
      stubThemes(
        {'a': 1, 'b': 3, 'c': 3},
        scores: const {'a': 100, 'b': 100, 'c': 100},
      );
      final container = await buildContainer(themeSlugs: ['a', 'b', 'c']);
      addTearDown(container.dispose);
      final observed = watchOrders(container);

      final state = await settle(container);

      final changes = orderChanges(observed);
      expect(changes, hasLength(2),
          reason: 'un seul réordonnancement, à la complétion du fan-out');
      expect(changes.first, ['a', 'b', 'c'],
          reason: 'ordre par défaut pendant tout le remplissage');
      expect(changes.last, ['b', 'c', 'a']);
      expect(themeOrder(state), ['b', 'c', 'a']);
    });

    test('l\'ordre gelé du jour est persisté sous tournee_score_order_v1',
        () async {
      stubThemes({'a': 1, 'b': 3}, scores: const {'a': 100, 'b': 100});
      final container = await buildContainer(themeSlugs: ['a', 'b']);
      addTearDown(container.dispose);

      await settle(container);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kTourneeScoreOrderKey);
      expect(raw, isNotNull);
      final blob = jsonDecode(raw!) as Map<String, dynamic>;
      expect(blob['day'], TourneeProgressService.dayKey(DateTime.now()));
      expect(blob['keys'], ['theme:b', 'theme:a']);
    });

    test(
        'ordre persisté du jour : rejoué dès la 1ʳᵉ émission (ré-ouverture sans '
        'aucun saut)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kTourneeScoreOrderKey: scoreOrderBlob(
          TourneeProgressService.dayKey(DateTime.now()),
          ['theme:c', 'theme:a', 'theme:b'],
        ),
      });
      // Scores volontairement contradictoires avec l'ordre persisté ('c' est le
      // plus pauvre) : c'est bien l'ordre **gelé** qui pilote, pas un recalcul.
      stubThemes(
        {'a': 3, 'b': 3, 'c': 1},
        scores: const {'a': 100, 'b': 100, 'c': 100},
      );
      final container = await buildContainer(themeSlugs: ['a', 'b', 'c']);
      addTearDown(container.dispose);
      final observed = watchOrders(container);

      final state = await settle(container);

      expect(orderChanges(observed), hasLength(1),
          reason: 'ordre stable de bout en bout');
      expect(themeOrder(state), ['c', 'a', 'b']);
    });

    test('ordre persisté daté d\'hier : ignoré, un ordre frais est recalculé',
        () async {
      final yesterday = TourneeProgressService.dayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        kTourneeScoreOrderKey:
            scoreOrderBlob(yesterday, ['theme:c', 'theme:a', 'theme:b']),
      });
      stubThemes(
        {'a': 3, 'b': 3, 'c': 1},
        scores: const {'a': 100, 'b': 100, 'c': 100},
      );
      final container = await buildContainer(themeSlugs: ['a', 'b', 'c']);
      addTearDown(container.dispose);
      final observed = watchOrders(container);

      final state = await settle(container);

      expect(orderChanges(observed).first, ['a', 'b', 'c'],
          reason: 'l\'ordre d\'hier n\'est jamais appliqué');
      expect(themeOrder(state), ['a', 'b', 'c'],
          reason: 'ordre frais : \'c\' (1 article) coule en fin');
      final prefs = await SharedPreferences.getInstance();
      final blob = jsonDecode(prefs.getString(kTourneeScoreOrderKey)!) as Map;
      expect(blob['day'], TourneeProgressService.dayKey(DateTime.now()));
    });
  });

  group('portée et arbitrage du classement', () {
    test('un bloc sans aucun article scoré garde sa place (sentinelle)',
        () async {
      // 'b' n'a pas de score : il n'entre pas dans le classement et conserve sa
      // position absolue, même entre deux blocs qui, eux, sont triés.
      stubThemes(
        {'a': 1, 'b': 3, 'c': 3},
        scores: const {'a': 100, 'c': 100},
      );
      final container = await buildContainer(themeSlugs: ['a', 'b', 'c']);
      addTearDown(container.dispose);

      final state = await settle(container);

      // 'c' (300) passe devant 'a' (100) ; 'b' ne bouge pas de la position 1.
      expect(themeOrder(state), ['c', 'b', 'a']);
    });

    test(
        'le classement dépasse les favoris : une suggérée bien scorée remonte '
        'au-dessus d\'un favori pauvre', () async {
      stubThemes(
        {'tech': 1, 'cinema': 3},
        scores: const {'tech': 50, 'cinema': 100},
      );
      final container = await buildContainer(
        themeSlugs: ['tech'],
        topThemes: const [
          TopTheme(
            interestSlug: 'cinema',
            weight: 1,
            articleCount: 3,
            origin: 'suggested',
            dailyRank: 1,
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await settle(container);

      // Par défaut les suggérées sont composées APRÈS les favoris ; le score
      // (300 vs 50) inverse l'ordre.
      expect(themeOrder(state), ['cinema', 'tech']);
    });

    test('à score égal, l\'ordre manuel départage (compte personnalisé)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_customized_v1': true,
        'tournee_order_v1': ['theme:c', 'theme:b', 'theme:a'],
      });
      stubThemes(
        {'a': 3, 'b': 3, 'c': 3},
        scores: const {'a': 100, 'b': 100, 'c': 100},
      );
      final container = await buildContainer(themeSlugs: ['a', 'b', 'c']);
      addTearDown(container.dispose);

      final state = await settle(container);

      expect(themeOrder(state), ['c', 'b', 'a']);
    });

    test('mais le score l\'emporte sur l\'ordre manuel quand il départage',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_customized_v1': true,
        'tournee_order_v1': ['theme:c', 'theme:b', 'theme:a'],
      });
      // 'c' est manuellement en tête mais n'a qu'un article : il coule.
      stubThemes(
        {'a': 3, 'b': 3, 'c': 1},
        scores: const {'a': 100, 'b': 100, 'c': 100},
      );
      final container = await buildContainer(themeSlugs: ['a', 'b', 'c']);
      addTearDown(container.dispose);

      final state = await settle(container);

      expect(themeOrder(state), ['b', 'a', 'c']);
    });
  });

  group('blockScores exposés à la mesure (PR-1)', () {
    test('state.blockScores porte la somme des 3 meilleurs scores par section',
        () async {
      stubThemes({'a': 1, 'b': 5}, scores: const {'a': 100, 'b': 100});
      final container = await buildContainer(themeSlugs: ['a', 'b']);
      addTearDown(container.dispose);

      final state = await settle(container);

      expect(state.blockScores['theme:a'], 100);
      // 5 articles à 100, plafonné aux 3 meilleurs.
      expect(state.blockScores['theme:b'], 300);
    });

    test('une section sans article scoré est absente de blockScores', () async {
      stubThemes({'a': 2});
      final container = await buildContainer(themeSlugs: ['a']);
      addTearDown(container.dispose);

      final state = await settle(container);

      expect(state.blockScores, isEmpty);
    });
  });
}
