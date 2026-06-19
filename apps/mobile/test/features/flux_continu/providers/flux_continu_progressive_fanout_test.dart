// Tests for the Phase 2 progressive + bounded fan-out (app-load slowdown fix).
//
// At cold-open the provider fans out one `personalized=true` call per Tournée
// section. The old code did a single blocking `Future.wait` over all ~10 calls;
// the backend (single uvicorn worker, CPU-bound scoring) serialised them and
// the first render blocked on the slowest. The new code:
//   - keeps at most [_kPhase2FanoutConcurrency] (3) requests in flight,
//   - emits state progressively as each section resolves,
//   - still fetches every section (no coverage loss).
import 'dart:async';
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
  Future<List<EssentielArticle>?> fetch() async => const [];
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

FeedResponse _feedResponseWith(int items) {
  return FeedResponse(
    items: List.generate(
      items,
      (i) => Content(
        id: 'c$i',
        title: 't$i',
        url: 'https://x.test/$i',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 1, 1),
        source: Source(id: 's', name: 'S', type: SourceType.article),
      ),
    ),
    pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
    carousels: const [],
  );
}

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

  ProviderContainer makeContainer(UserInterestsState interests) {
    return ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider.overrideWithValue(
          _StubEssentielRepository(),
        ),
        grilleRepositoryProvider.overrideWithValue(_NoGrilleRepository()),
        userInterestsProvider.overrideWith(
          () => _StubUserInterestsNotifier(interests),
        ),
        sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref)),
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
      ],
    );
  }

  setUpAll(() {
    Hive.init(
      Directory.systemTemp.createTempSync('flux_progressive_hive').path,
    );
  });

  setUp(() async {
    await clearFluxCache();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    when(
      () => digestRepo.fetchBothDigests(),
    ).thenThrow(Exception('mock: no digest'));
    when(
      () => fluxRepo.getTopThemes(),
    ).thenAnswer((_) async => const <TopTheme>[]);
  });

  tearDown(() async {
    await pumpEventQueue(times: 5);
    await clearFluxCache();
  });

  List<FavoriteRef> themeFavorites(int n) =>
      [for (var i = 0; i < n; i++) ThemeFavoriteRef(slug: 'theme$i')];

  test('every favorite section is still fetched (no coverage loss)', () async {
    when(
      () => feedRepo.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        theme: any(named: 'theme'),
        serein: any(named: 'serein'),
        personalized: any(named: 'personalized'),
      ),
    ).thenAnswer((_) async => _feedResponseWith(3));

    final container = makeContainer(
      _interestsState(favorites: themeFavorites(6)),
    );
    addTearDown(container.dispose);

    final state = await settle(container);

    // All 6 theme sections present.
    final themeSlugs = state.sections
        .whereType<FeedThemeSection>()
        .map((s) => s.themeSlug)
        .whereType<String>()
        .toSet();
    expect(themeSlugs, {
      'theme0',
      'theme1',
      'theme2',
      'theme3',
      'theme4',
      'theme5',
    });
    // Exactly one fetch per section (page 1, personalized).
    verify(
      () => feedRepo.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        theme: any(named: 'theme'),
        serein: any(named: 'serein'),
        personalized: any(named: 'personalized'),
      ),
    ).called(6);
  });

  test('fan-out concurrency is bounded (≤ 3 in flight at once)', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    final gates = <Completer<void>>[];

    when(
      () => feedRepo.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        theme: any(named: 'theme'),
        serein: any(named: 'serein'),
        personalized: any(named: 'personalized'),
      ),
    ).thenAnswer((_) async {
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      inFlight--;
      return _feedResponseWith(3);
    });

    final container = makeContainer(
      _interestsState(favorites: themeFavorites(6)),
    );
    addTearDown(container.dispose);

    container.read(fluxContinuProvider);

    // Drain the bootstrap so Phase 2 dispatches, then release sections one at
    // a time, re-checking the pool each step. If the bound were broken, all 6
    // would be dispatched at once and maxInFlight would hit 6.
    for (var step = 0; step < 30; step++) {
      await pumpEventQueue(times: 3);
      if (gates.isEmpty) continue;
      gates.removeAt(0).complete();
    }
    // Flush any stragglers.
    while (gates.isNotEmpty) {
      gates.removeAt(0).complete();
      await pumpEventQueue(times: 3);
    }

    expect(
      maxInFlight,
      lessThanOrEqualTo(3),
      reason: 'fan-out must respect _kPhase2FanoutConcurrency (3)',
    );
    // And it actually parallelised up to the bound (not accidentally serial).
    expect(maxInFlight, greaterThan(1));
  });

  test('state fills progressively (sections appear incrementally)', () async {
    final gates = <Completer<void>>[];
    var callIdx = 0;

    when(
      () => feedRepo.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        theme: any(named: 'theme'),
        serein: any(named: 'serein'),
        personalized: any(named: 'personalized'),
      ),
    ).thenAnswer((_) async {
      // Distinct ids per call so cross-section dedup never empties a section —
      // we want the raw "how many sections are present" signal.
      final idx = callIdx++;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      return FeedResponse(
        items: List.generate(
          3,
          (i) => Content(
            id: 'call${idx}_item$i',
            title: 't',
            url: 'https://x.test/$idx/$i',
            contentType: ContentType.article,
            publishedAt: DateTime(2026, 1, 1),
            source: Source(id: 's', name: 'S', type: SourceType.article),
          ),
        ),
        pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
        carousels: const [],
      );
    });

    final container = makeContainer(
      _interestsState(favorites: themeFavorites(4)),
    );
    addTearDown(container.dispose);

    container.read(fluxContinuProvider);

    // Poll the live value (Riverpod coalesces listener notifications, so we
    // sample like `settle` does) while releasing sections one at a time.
    final counts = <int>[];
    void record() {
      final v = container.read(fluxContinuProvider).valueOrNull;
      if (v != null && !v.isSkeleton) {
        counts.add(v.sections.whereType<FeedThemeSection>().length);
      }
    }

    for (var step = 0; step < 40; step++) {
      await pumpEventQueue(times: 3);
      record();
      if (gates.isNotEmpty) gates.removeAt(0).complete();
    }
    while (gates.isNotEmpty) {
      gates.removeAt(0).complete();
      await pumpEventQueue(times: 3);
      record();
    }
    await pumpEventQueue(times: 5);
    record();

    // At least one intermediate sample had 1..3 sections (progressive fill),
    // not a single jump straight from 0 to 4.
    expect(
      counts.any((c) => c > 0 && c < 4),
      isTrue,
      reason: 'expected an intermediate state before all 4 sections arrived',
    );
    expect(counts.last, 4);
  });
}
