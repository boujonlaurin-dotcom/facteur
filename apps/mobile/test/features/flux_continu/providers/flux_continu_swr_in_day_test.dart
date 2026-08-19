// Tests du SWR in-day (cache local des articles de la Tournée) :
//
//  - commit 1 : une **revalidation** (pull-to-refresh, refetch d'un cache
//    in-day) ne republie jamais une section déjà hydratée avec `items: []` —
//    le seed passe par `_reseedShells` au lieu d'écraser par des coquilles.
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
import 'package:facteur/features/flux_continu/services/flux_continu_cache_service.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
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
  @override
  Future<EssentielFetchResult?> fetch({bool? serein, DateTime? date}) async => (
        articles: [
          for (var i = 0; i < 5; i++)
            EssentielArticle(
              contentId: 'ess-$i',
              title: 'Essentiel $i',
              url: 'https://x.test/ess/$i',
              publishedAt: DateTime(2026, 1, 1),
              sourceName: 'S',
              sourceLetter: 'S',
              sectionLabel: 'Essentiel',
              rank: i + 1,
            ),
        ],
        newSinceMorning: 0,
        carousel: null,
      );

  @override
  Future<List<Map<String, dynamic>>?> fetchMore({
    required List<String> excludeIds,
    int limit = 2,
  }) async =>
      const [];

  @override
  Future<bool> postTriage({
    required String digestDate,
    required int slateSize,
    required List<Map<String, dynamic>> decisions,
  }) async =>
      true;
}

class _NoGrilleRepository implements GrilleRepository {
  @override
  Future<GrilleTodayResponse> getToday() async =>
      throw Exception('mock: no grille');

  @override
  Future<GrilleLeaderboardResponse> getLeaderboard() =>
      throw UnimplementedError();

  @override
  Future<GrilleRevealResponse> revealWord() => throw UnimplementedError();

  @override
  Future<GrilleGuessResponse> submitGuess(String mot) =>
      throw UnimplementedError();
}

class _StubUserInterestsNotifier extends UserInterestsNotifier {
  _StubUserInterestsNotifier(this._initial);

  final UserInterestsState _initial;

  @override
  Future<UserInterestsState> build() async => _initial;
}

UserInterestsState _interestsState({List<FavoriteRef> favorites = const []}) {
  return UserInterestsState(
    themes: const [],
    customTopics: const [],
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 7,
  );
}

FeedResponse _feedResponseWith(int items, {String prefix = 'c'}) {
  return FeedResponse(
    items: List.generate(
      items,
      (i) => Content(
        id: '$prefix-$i',
        title: 't$i',
        url: 'https://x.test/$prefix/$i',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 1, 1),
        source: Source(id: 's', name: 'S', type: SourceType.article),
      ),
    ),
    pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
    carousels: const [],
  );
}

/// `sectionKey` → nombre d'items, pour les seules sections thème/source/veille.
Map<String, int> _themeItemCounts(FluxContinuState state) => {
      for (final s in state.sections)
        if (s is FeedThemeSection) sectionKey(s): s.items.length,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _MockFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;

  Future<void> clearFluxCache() async {
    final cacheBox = Hive.isBoxOpen(FluxContinuCacheService.boxName)
        ? Hive.box<String>(FluxContinuCacheService.boxName)
        : await Hive.openBox<String>(FluxContinuCacheService.boxName);
    await cacheBox.clear();
  }

  ProviderContainer makeContainer({UserInterestsState? interests}) {
    return ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider.overrideWithValue(_StubEssentielRepository()),
        grilleRepositoryProvider.overrideWithValue(_NoGrilleRepository()),
        userInterestsProvider.overrideWith(
          () => _StubUserInterestsNotifier(interests ?? _interestsState()),
        ),
        sereinToggleProvider
            .overrideWith((ref) => SereinToggleNotifier(ref, null)),
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
      ],
    );
  }

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('flux_swr_hive').path);
  });

  setUp(() async {
    await clearFluxCache();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    when(() => digestRepo.fetchBothDigests())
        .thenThrow(Exception('mock: no digest'));
    when(() => fluxRepo.getTopThemes())
        .thenAnswer((_) async => const <TopTheme>[]);
    when(
      () => feedRepo.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        theme: any(named: 'theme'),
        topic: any(named: 'topic'),
        sourceId: any(named: 'sourceId'),
        serein: any(named: 'serein'),
        personalized: any(named: 'personalized'),
      ),
    ).thenAnswer((invocation) async {
      final theme = invocation.namedArguments[#theme] as String?;
      return _feedResponseWith(3, prefix: theme ?? 'x');
    });
  });

  tearDown(() async {
    await pumpEventQueue(times: 5);
    await clearFluxCache();
  });

  test(
    'une revalidation ne republie jamais une section déjà hydratée avec '
    'items vides (pas de flash contenu → vide → contenu)',
    () async {
      final container = makeContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'theme0'),
            ThemeFavoriteRef(slug: 'theme1'),
            ThemeFavoriteRef(slug: 'theme2'),
          ],
        ),
      );
      addTearDown(container.dispose);

      await settle(container);

      // Le cold boot a hydraté les 3 sections.
      final hydrated =
          _themeItemCounts(container.read(fluxContinuProvider).value!);
      expect(hydrated.length, 3);
      expect(hydrated.values, everyElement(greaterThan(0)),
          reason: 'pré-condition : les 3 sections portent des articles');

      // Revalidation : on enregistre CHAQUE état publié pendant le refetch.
      final regressions = <String>[];
      final sub = container.listen<AsyncValue<FluxContinuState>>(
        fluxContinuProvider,
        (_, next) {
          final value = next.value;
          if (value == null || value.isSkeleton) return;
          value.sections.whereType<FeedThemeSection>().forEach((s) {
            final key = sectionKey(s);
            if ((hydrated[key] ?? 0) > 0 && s.items.isEmpty) {
              regressions.add(key);
            }
          });
        },
      );
      addTearDown(sub.close);

      await container.read(fluxContinuProvider.notifier).refresh();
      await settle(container);

      expect(regressions, isEmpty,
          reason: 'une section hydratée ne doit jamais repasser par un état '
              'vide pendant la revalidation');
      expect(_themeItemCounts(container.read(fluxContinuProvider).value!),
          hydrated);
    },
  );

  test(
    'un favori retiré entre deux passes disparaît quand même du seed '
    '(le reseed n\'est pas un cache infini)',
    () async {
      final interests = _interestsState(
        favorites: const [
          ThemeFavoriteRef(slug: 'theme0'),
          ThemeFavoriteRef(slug: 'theme1'),
        ],
      );
      final container = makeContainer(interests: interests);
      addTearDown(container.dispose);

      await settle(container);
      expect(
        _themeItemCounts(container.read(fluxContinuProvider).value!).keys,
        containsAll(<String>['theme:theme0', 'theme:theme1']),
      );

      // theme1 sort des favoris : la revalidation ne doit pas le conserver.
      container.read(userInterestsProvider.notifier).state = AsyncData(
        _interestsState(favorites: const [ThemeFavoriteRef(slug: 'theme0')]),
      );
      await container.read(fluxContinuProvider.notifier).refresh();
      await settle(container);

      final keys =
          _themeItemCounts(container.read(fluxContinuProvider).value!).keys;
      expect(keys, contains('theme:theme0'));
      expect(keys, isNot(contains('theme:theme1')));
    },
  );
}
