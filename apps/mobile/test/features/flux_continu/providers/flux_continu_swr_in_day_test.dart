// Tests du SWR in-day (cache local des articles de la Tournée) :
//
//  - commit 1 : une **revalidation** (pull-to-refresh, refetch d'un cache
//    in-day) ne republie jamais une section déjà hydratée avec `items: []` —
//    le seed passe par `_reseedShells` au lieu d'écraser par des coquilles ;
//  - commit 2 : le fan-out persiste chaque section résolue (jamais une section
//    vide), et la réouverture dans la journée peint la Tournée **complète**
//    (articles compris) avant le moindre appel réseau — y compris les sections
//    que le seed ne sait pas produire (catalogue sources non résolu).
import 'dart:async';
import 'dart:io';

import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/models/dual_digest_response.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/services/feed_cache_service.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/flux_continu/services/flux_continu_cache_service.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'feed_repository_mock.dart';
import 'flux_continu_settle.dart';

const String _kUserId = 'user-swr';

class _MockDigestRepository extends Mock implements DigestRepository {}

typedef _MockFluxContinuRepository = MockFluxContinuRepository;

/// Faux repo feed servant un **payload brut** (ce que le SWR persiste) plutôt
/// qu'un `FeedResponse` déjà construit : c'est le chemin de production.
class _RawFeedRepository implements FeedRepository {
  _RawFeedRepository({this.onFetch});

  static const int itemsPerSection = 3;
  final void Function(String key)? onFetch;

  /// Sections servies **vides** (une panne réseau ne doit jamais être
  /// persistée comme un contenu légitime).
  final Set<String> emptyKeys = <String>{};

  static Map<String, dynamic> rawFeed(String prefix, int count) => {
        'items': [
          for (var i = 0; i < count; i++)
            {
              'id': '$prefix-$i',
              'title': 'Article $prefix $i',
              'url': 'https://x.test/$prefix/$i',
              'content_type': 'article',
              'published_at': '2026-01-01T08:00:00.000Z',
              'status': 'unseen',
              'source': {'id': 'src-$prefix', 'name': 'Source $prefix'},
            },
        ],
        'pagination': {'has_next': false, 'total': count},
      };

  @override
  Future<FeedRawResult> getFeedWithRaw({
    int page = 1,
    int limit = 20,
    String? contentType,
    bool savedOnly = false,
    String? mode,
    String? theme,
    String? topic,
    bool hasNote = false,
    String? sourceId,
    String? entity,
    String? keyword,
    bool includeUnfollowed = false,
    bool serein = false,
    bool personalized = false,
    bool followedOnly = false,
    bool forceFresh = false,
  }) async {
    final key = theme ?? topic ?? sourceId ?? 'default';
    onFetch?.call(key);
    final count = emptyKeys.contains(key) ? 0 : itemsPerSection;
    final raw = rawFeed(key, count);
    return (
      feed: FeedRepository.parseFeedData(data: raw, page: page, limit: limit),
      raw: raw,
    );
  }

  @override
  Future<FeedResponse> getFeed({
    int page = 1,
    int limit = 20,
    String? contentType,
    bool savedOnly = false,
    String? mode,
    String? theme,
    String? topic,
    bool hasNote = false,
    String? sourceId,
    String? entity,
    String? keyword,
    bool includeUnfollowed = false,
    bool serein = false,
    bool personalized = false,
    bool followedOnly = false,
    bool forceFresh = false,
  }) async =>
      (await getFeedWithRaw(
        page: page,
        limit: limit,
        theme: theme,
        topic: topic,
        sourceId: sourceId,
        serein: serein,
        personalized: personalized,
      ))
          .feed;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _StubEssentielRepository implements EssentielRepository {
  _StubEssentielRepository({this.gate});

  /// Quand fournie, `fetch()` ne se résout que sur cette future : sert à
  /// observer l'état **avant** le moindre retour réseau.
  final Future<EssentielFetchResult?> Function()? gate;

  @override
  Future<EssentielFetchResult?> fetch({bool? serein, DateTime? date}) {
    if (gate != null) return gate!();
    return Future.value((
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
    ));
  }

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

class _AuthNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  _AuthNotifier()
      : super(const app_auth.AuthState(
          user: supabase.User(
            id: _kUserId,
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-01-01',
          ),
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

DigestResponse _digest(String id) => DigestResponse(
      digestId: id,
      userId: _kUserId,
      targetDate: DateTime(2026, 1, 1),
      generatedAt: DateTime(2026, 1, 1),
      topics: const [],
    );

DualDigestResponse _dual() => DualDigestResponse(
      normal: _digest('d-normal'),
      serein: _digest('d-serein'),
      sereinEnabled: false,
    );

/// `sectionKey` → nombre d'items, pour les seules sections thème/source/veille.
Map<String, int> _themeItemCounts(FluxContinuState state) => {
      for (final s in state.sections)
        if (s is FeedThemeSection) sectionKey(s): s.items.length,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _RawFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;

  Future<Box<String>> openBox(String name) async => Hive.isBoxOpen(name)
      ? Hive.box<String>(name)
      : await Hive.openBox<String>(name);

  ProviderContainer makeContainer({
    UserInterestsState? interests,
    EssentielRepository? essentielRepo,
  }) {
    return ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider
            .overrideWithValue(essentielRepo ?? _StubEssentielRepository()),
        grilleRepositoryProvider.overrideWithValue(_NoGrilleRepository()),
        userInterestsProvider.overrideWith(
          () => _StubUserInterestsNotifier(interests ?? _interestsState()),
        ),
        sereinToggleProvider
            .overrideWith((ref) => SereinToggleNotifier(ref, null)),
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
        app_auth.authStateProvider.overrideWith((ref) => _AuthNotifier()),
      ],
    );
  }

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('flux_swr_hive').path);
  });

  setUp(() async {
    await (await openBox(FluxContinuCacheService.boxName)).clear();
    await (await openBox(FeedCacheService.boxName)).clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    digestRepo = _MockDigestRepository();
    feedRepo = _RawFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    when(() => digestRepo.fetchBothDigests()).thenAnswer((_) async => _dual());
    when(() => fluxRepo.getTopThemes())
        .thenAnswer((_) async => const <TopTheme>[]);
  });

  tearDown(() async {
    await pumpEventQueue(times: 5);
    await (await openBox(FluxContinuCacheService.boxName)).clear();
    await (await openBox(FeedCacheService.boxName)).clear();
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
          for (final s in value.sections.whereType<FeedThemeSection>()) {
            final key = sectionKey(s);
            if ((hydrated[key] ?? 0) > 0 && s.items.isEmpty) {
              regressions.add(key);
            }
          }
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
      final container = makeContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'theme0'),
            ThemeFavoriteRef(slug: 'theme1'),
          ],
        ),
      );
      addTearDown(container.dispose);

      await settle(container);
      expect(
        _themeItemCounts(container.read(fluxContinuProvider).value!).keys,
        containsAll(<String>['theme:theme0', 'theme:theme1']),
      );

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

  test(
    'le fan-out persiste chaque section résolue, jamais une section vide',
    () async {
      feedRepo.emptyKeys.add('theme1');
      final container = makeContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'theme0'),
            ThemeFavoriteRef(slug: 'theme1'),
          ],
        ),
      );
      addTearDown(container.dispose);

      await settle(container);

      final cache = FeedCacheService(await openBox(FeedCacheService.boxName));
      final persisted = cache.readTourneeSections(
        _kUserId,
        variant: FeedCacheVariant.normal,
        dayKey: TourneeProgressService.dayKey(DateTime.now()),
      );
      expect(persisted.keys, contains('theme:theme0'));
      expect(persisted.keys, isNot(contains('theme:theme1')),
          reason: 'une section vide (panne réseau avalée) n\'est jamais '
              'mémorisée comme un contenu légitime');
    },
  );

  test(
    'réouverture in-day : la Tournée est peinte avec ses articles AVANT tout '
    'appel réseau, sections source comprises',
    () async {
      const favorites = [
        ThemeFavoriteRef(slug: 'theme0'),
        ThemeFavoriteRef(slug: 'theme1'),
      ];

      // 1er boot : remplit le cache sections + le snapshot Flux.
      final first = makeContainer(interests: _interestsState(
        favorites: favorites,
      ));
      await settle(first);
      final firstCounts =
          _themeItemCounts(first.read(fluxContinuProvider).value!);
      expect(firstCounts.length, 2);
      first.dispose();
      await pumpEventQueue(times: 5);

      // 2e boot, le même jour. Les intérêts ne sont **pas** résolus (comme au
      // vrai boot : `_peekValue` n'initialise rien) et rien ne répond côté
      // réseau — seul le cache peut peindre la Tournée.
      final never = Completer<EssentielFetchResult?>();
      addTearDown(() => never.complete(null));
      final fetches = <String>[];
      feedRepo = _RawFeedRepository(onFetch: fetches.add);
      when(() => digestRepo.fetchBothDigests())
          .thenAnswer((_) => Completer<DualDigestResponse>().future);

      final second = makeContainer(
        essentielRepo: _StubEssentielRepository(gate: () => never.future),
      );
      addTearDown(second.dispose);

      FluxContinuState? painted;
      final sub = second.listen<AsyncValue<FluxContinuState>>(
        fluxContinuProvider,
        (_, next) => painted ??= next.value,
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await pumpEventQueue(times: 20);

      expect(painted, isNotNull,
          reason: 'le chemin cache in-day peint avant le gate JWT');
      expect(painted!.isSkeleton, isFalse);
      final counts = _themeItemCounts(painted!);
      expect(counts.keys, containsAll(firstCounts.keys),
          reason: 'les sections reviennent alors que le seed ne peut pas les '
              'produire (intérêts non résolus)');
      expect(counts.values, everyElement(greaterThan(0)),
          reason: 'avec leurs articles, pas des coquilles');
      expect(fetches, isEmpty,
          reason: 'aucun appel /api/feed n\'a encore répondu');
    },
  );

  test(
    'un cache daté d\'hier n\'est jamais peint (et se purge)',
    () async {
      final box = await openBox(FeedCacheService.boxName);
      final cache = FeedCacheService(box);
      await cache.saveTourneeSection(
        _kUserId,
        'theme:vieux',
        variant: FeedCacheVariant.normal,
        dayKey: '2020-01-01',
        header: const {
          'kind': 'theme',
          'label': 'Vieux',
          'accent': 0xFF000000,
          'core_visible_count': 3,
          'theme_slug': 'vieux',
        },
        rawData: _RawFeedRepository.rawFeed('vieux', 3),
      );

      expect(
        cache.readTourneeSections(
          _kUserId,
          variant: FeedCacheVariant.normal,
          dayKey: TourneeProgressService.dayKey(DateTime.now()),
        ),
        isEmpty,
      );

      await cache.purgeStaleTourneeSections(_kUserId, dayKey: TourneeProgressService.dayKey(DateTime.now()));
      expect(
        box.keys.where((k) => k.toString().startsWith(FeedCacheService.tourneePrefix)),
        isEmpty,
      );
    },
  );

  test(
    'un article balayé reste absent après réouverture in-day',
    () async {
      const favorites = [ThemeFavoriteRef(slug: 'theme0')];
      final first = makeContainer(
        interests: _interestsState(favorites: favorites),
      );
      await settle(first);

      final dismissed = first
          .read(fluxContinuProvider)
          .value!
          .sections
          .whereType<FeedThemeSection>()
          .firstWhere((s) => sectionKey(s) == 'theme:theme0')
          .items
          .first
          .id;
      first.read(fluxContinuProvider.notifier).confirmDismiss(dismissed);
      await pumpEventQueue(times: 5);
      first.dispose();

      final second = makeContainer(
        interests: _interestsState(favorites: favorites),
      );
      addTearDown(second.dispose);
      final state = await settle(second);

      final ids = state.sections
          .whereType<FeedThemeSection>()
          .expand((s) => s.items)
          .map((c) => c.id);
      expect(ids, isNot(contains(dismissed)),
          reason: 'le balayage du jour est persisté, le SWR ne le ressuscite '
              'pas');
      expect(state.dismissedIds, contains(dismissed));
    },
  );

  test('patchTourneeContentStatus ne décode que les entrées porteuses',
      () async {
    final box = await openBox(FeedCacheService.boxName);
    final cache = FeedCacheService(box);
    for (final key in ['theme:a', 'theme:b']) {
      await cache.saveTourneeSection(
        _kUserId,
        key,
        variant: FeedCacheVariant.normal,
        dayKey: TourneeProgressService.dayKey(DateTime.now()),
        header: {
          'kind': 'theme',
          'label': key,
          'accent': 0xFF000000,
          'core_visible_count': 3,
          'theme_slug': key,
        },
        rawData: _RawFeedRepository.rawFeed(key, 2),
      );
    }

    final patched = await cache.patchTourneeContentStatus(
      _kUserId,
      'theme:a-0',
      ContentStatus.consumed,
    );
    expect(patched, 1, reason: 'seule l\'entrée qui porte l\'id est réécrite');

    final entries = cache.readTourneeSections(
      _kUserId,
      variant: FeedCacheVariant.normal,
      dayKey: TourneeProgressService.dayKey(DateTime.now()),
    );
    final items = (entries['theme:a']!.data as Map)['items'] as List;
    expect((items.first as Map)['status'], 'consumed');
  });
}

