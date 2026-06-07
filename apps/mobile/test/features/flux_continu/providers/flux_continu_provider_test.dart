import 'dart:io';

import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/models/dual_digest_response.dart';
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
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Stub notifier that returns a fixed [UserInterestsState] synchronously,
/// so the fluxContinuProvider's `ref.read(userInterestsProvider)` resolves
/// without making the test hit the (absent) backend.
class _StubUserInterestsNotifier extends UserInterestsNotifier {
  _StubUserInterestsNotifier(this._initial);

  UserInterestsState _initial;

  @override
  Future<UserInterestsState> build() async => _initial;

  void setState(UserInterestsState next) {
    _initial = next;
    state = AsyncValue.data(next);
  }
}

UserInterestsState _interestsState({
  List<FavoriteRef> favorites = const [],
  List<CustomTopicInterest> customTopics = const [],
}) {
  return UserInterestsState(
    themes: const [],
    customTopics: customTopics,
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 5,
  );
}

String _todayIso() {
  // Mirror the provider's 07:30-local tournée-day boundary: before 07:30 the
  // active prefs key still references yesterday so the closing-dismissed flag
  // survives across midnight (the digest hasn't regenerated yet).
  final now = DateTime.now();
  final shifted = (now.hour < 7 || (now.hour == 7 && now.minute < 30))
      ? now.subtract(const Duration(days: 1))
      : now;
  return shifted.toIso8601String().substring(0, 10);
}

String _todayClosingKey() => 'flux_continu_closing_dismissed_${_todayIso()}';

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

FeedResponse _feedResponseWithIds(
  List<String> ids, {
  int page = 1,
  bool hasNext = false,
}) {
  return FeedResponse(
    items: ids
        .map(
          (id) => Content(
            id: id,
            title: 'title-$id',
            url: 'https://x.test/$id',
            contentType: ContentType.article,
            publishedAt: DateTime(2026, 1, 1),
            source: Source(id: 's', name: 'S', type: SourceType.article),
          ),
        )
        .toList(),
    pagination: Pagination(page: page, perPage: 10, total: 0, hasNext: hasNext),
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

  ProviderContainer makeContainer({
    UserInterestsState? interests,
    _StubUserInterestsNotifier? interestsNotifier,
  }) {
    final userInterestsNotifier = interestsNotifier ??
        _StubUserInterestsNotifier(interests ?? _interestsState());
    return ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider.overrideWithValue(
          _StubEssentielRepository(),
        ),
        grilleRepositoryProvider.overrideWithValue(_NoGrilleRepository()),
        userInterestsProvider.overrideWith(() => userInterestsNotifier),
        sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref)),
      ],
    );
  }

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('flux_provider_hive').path);
  });

  setUp(() async {
    await clearFluxCache();
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    // The provider wraps each upstream call in `_safe<T>` which catches and
    // logs — empty/throwing repos are the canonical "no payload" path.
    when(
      () => digestRepo.fetchBothDigests(),
    ).thenThrow(Exception('mock: no digest'));
    when(
      () => fluxRepo.getTopThemes(),
    ).thenAnswer((_) async => const <TopTheme>[]);
    when(
      () => feedRepo.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        theme: any(named: 'theme'),
        topic: any(named: 'topic'),
        serein: any(named: 'serein'),
        personalized: any(named: 'personalized'),
      ),
    ).thenThrow(Exception('mock: no feed'));
  });

  tearDown(() async {
    await pumpEventQueue(times: 5);
    await clearFluxCache();
  });

  group('FluxContinuNotifier — purge cross-day', () {
    test('removes closing-dismissed keys from previous days, keeps today\'s',
        () async {
      const oldClosingKey = 'flux_continu_closing_dismissed_2020-01-01';
      final todayClosingKey = _todayClosingKey();

      SharedPreferences.setMockInitialValues(<String, Object>{
        oldClosingKey: true,
        todayClosingKey: true,
      });

        final container = makeContainer();
        addTearDown(container.dispose);

        await container.read(fluxContinuProvider.future);
        // Purge runs as `unawaited` — give the microtask queue a beat.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      expect(keys, isNot(contains(oldClosingKey)));
      expect(keys, contains(todayClosingKey));
    });

    test('sweeps leftover legacy folded blobs (mechanic removed 2026-06)',
        () async {
      // The fold mechanic and its `flux_continu_folded_*` SharedPreferences
      // blobs were removed. The cross-day purge now sweeps any such leftover —
      // today's included — so they never linger.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flux_continu_folded_2020-01-01': <String>['essentiel'],
        'flux_continu_folded_${_todayIso()}': <String>['bonnes'],
      });

        final container = makeContainer();
        addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('flux_continu_folded_')),
        isEmpty,
      );
    });

    test('starts with empty state when no prefs exist for today', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      expect(state.closingDismissed, isFalse);
      expect(state.moreOpen, isEmpty);
    });
  });

  group('FluxContinuNotifier — favorites-driven theme sections', () {
    test(
      '0 favorites + empty top-themes fallback → 3 canonical themes fetched',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        // Digest absent, feed absent → only the theme fetches matter.
        when(
          () => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          ),
        ).thenAnswer((_) async => _feedResponseWith(3));

        final container = makeContainer(); // 0 favorites in stub
        addTearDown(container.dispose);

        await container.read(fluxContinuProvider.future);

        // 3 fallback canonical theme fetches (tech, environment, science).
        final captured = verify(
          () => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: captureAny(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          ),
        ).captured;
        expect(captured, containsAll(['tech', 'environment', 'science']));
      },
    );

    test('Theme favorite triggers getFeed(theme: slug)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
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
        interests: _interestsState(
          favorites: [const ThemeFavoriteRef(slug: 'culture')],
        ),
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);

      verify(
        () => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: 'culture',
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        ),
      ).called(1);
    });

    test('Custom topic favorite is excluded from Tournée', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      const customId = 'aaaa-bbbb-cccc';
      final container = makeContainer(
        interests: _interestsState(
          favorites: [const CustomTopicFavoriteRef(id: customId)],
          customTopics: [
            const CustomTopicInterest(
              id: customId,
              topicName: 'IA & éducation',
              slugParent: 'tech',
              state: InterestState.favorite,
              priorityMultiplier: 2.0,
            ),
          ],
        ),
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      verifyNever(
        () => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          topic: customId,
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        ),
      );

      final themeSections =
          state.sections.whereType<FeedThemeSection>().toList();
      expect(themeSections.where((s) => s.customTopicId != null), isEmpty);
    });

    test('Custom topic favorite added live is ignored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      when(
        () => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        ),
      ).thenAnswer((_) async => _feedResponseWith(3));

      const customId = 'aaaa-bbbb-cccc';
      final interestsNotifier = _StubUserInterestsNotifier(
        _interestsState(
          favorites: const [ThemeFavoriteRef(slug: 'tech')],
        ),
      );
      final container = makeContainer(interestsNotifier: interestsNotifier);
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      clearInteractions(feedRepo);

      interestsNotifier.setState(
        _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            CustomTopicFavoriteRef(id: customId),
          ],
          customTopics: const [
            CustomTopicInterest(
              id: customId,
              topicName: 'IA & éducation',
              slugParent: 'tech',
              state: InterestState.favorite,
              priorityMultiplier: 2.0,
            ),
          ],
        ),
      );
      await pumpEventQueue(times: 5);

      verifyNever(
        () => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          topic: customId,
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        ),
      );
      verifyNever(
        () => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: 'tech',
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        ),
      );
    });

    test('5 favorites cap (6th ignored)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
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
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
            ThemeFavoriteRef(slug: 'politics'),
            ThemeFavoriteRef(slug: 'sport'), // 6th — must be dropped
          ],
        ),
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);
      final slugs = state.sections
          .whereType<FeedThemeSection>()
          .map((s) => s.themeSlug)
          .toList();
      expect(slugs, ['tech', 'science', 'culture', 'economy', 'politics']);
    });
  });

  group('FluxContinuNotifier — Tournée du jour curation (personalized)', () {
    test('Theme favorite forwards personalized:true to getFeed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
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
        interests: _interestsState(
          favorites: const [ThemeFavoriteRef(slug: 'tech')],
        ),
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);

      // The Tournée du jour theme sections opt in to the backend curation
      // (followed sources only + 24h window + user_subtopics boost).
      verify(
        () => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: 'tech',
          serein: any(named: 'serein'),
          personalized: true,
        ),
      ).called(1);
    });

    test(
      'Custom topic favorite does not hit personalized topic feed',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        const customId = 'aaaa-bbbb-cccc';
        final container = makeContainer(
          interests: _interestsState(
            favorites: const [CustomTopicFavoriteRef(id: customId)],
            customTopics: const [
              CustomTopicInterest(
                id: customId,
                topicName: 'IA & éducation',
                slugParent: 'tech',
                state: InterestState.favorite,
                priorityMultiplier: 2.0,
              ),
            ],
          ),
        );
        addTearDown(container.dispose);

        await container.read(fluxContinuProvider.future);

        verifyNever(
          () => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            topic: customId,
            serein: any(named: 'serein'),
            personalized: true,
          ),
        );
      },
    );
  });

  group('FluxContinuNotifier — loadMoreTheme pagination', () {
    test(
      'appends next page items, increments page, propagates hasMore',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        // Initial fetch (page 1) — 10 items (= page limit), hasNext=true.
        // The page must be FULL to keep hasMore=true after the safety-net
        // guard "items.length < limit ⇒ hasMore=false" (cf.
        // `_kThemeSectionPageLimit` in flux_continu_provider.dart).
        final pageOneIds = List.generate(10, (i) => 'a${i + 1}');
        final pageTwoIds = List.generate(3, (i) => 'b${i + 1}');
        when(
          () => feedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          ),
        ).thenAnswer(
          (_) async => _feedResponseWithIds(pageOneIds, page: 1, hasNext: true),
        );
        // Load-more fetch (page 2) — 3 new items, hasNext=false (last page).
        when(
          () => feedRepo.getFeed(
            page: 2,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          ),
        ).thenAnswer(
          (_) async =>
              _feedResponseWithIds(pageTwoIds, page: 2, hasNext: false),
        );

        final container = makeContainer(
          interests: _interestsState(
            favorites: const [ThemeFavoriteRef(slug: 'tech')],
          ),
        );
        addTearDown(container.dispose);

        final initial = await container.read(fluxContinuProvider.future);
        final themeSection =
            initial.sections.whereType<FeedThemeSection>().single;
        expect(themeSection.items.map((c) => c.id), pageOneIds);
        expect(themeSection.currentPage, 1);
        expect(themeSection.hasMore, true);

        await container
            .read(fluxContinuProvider.notifier)
            .loadMoreTheme(sectionKey(themeSection));

        final after = container.read(fluxContinuProvider).requireValue;
        final updated = after.sections.whereType<FeedThemeSection>().single;
        expect(updated.items.map((c) => c.id), [...pageOneIds, ...pageTwoIds]);
        expect(updated.currentPage, 2);
        expect(updated.hasMore, false);
        expect(updated.isLoadingMore, false);
      },
    );

    test(
        'partial page-1 response (< limit) forces hasMore=false even if '
        'backend reports hasNext=true', () async {
      // Garde-fou : si la page initiale renvoie moins d'items que la limite
      // demandée, aucune page suivante ne peut exister, peu importe ce que
      // dit pagination.hasNext. Évite le cas où total_candidates est
      // surestimé côté backend (compté avant compression applicative) et
      // empêche ScrollExhausted de devenir true sur la page dédiée
      // ThemeSectionScreen → bloque l'affichage de la closing card et du
      // bloc "Section suivante".
      SharedPreferences.setMockInitialValues(<String, Object>{});
      when(
        () => feedRepo.getFeed(
          page: 1,
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        ),
      ).thenAnswer(
        (_) async => _feedResponseWithIds(
          const ['a1', 'a2', 'a3'],
          page: 1,
          hasNext: true,
        ),
      );

      final container = makeContainer(
        interests: _interestsState(
          favorites: const [ThemeFavoriteRef(slug: 'tech')],
        ),
      );
      addTearDown(container.dispose);

      final initial = await container.read(fluxContinuProvider.future);
      final themeSection =
          initial.sections.whereType<FeedThemeSection>().single;
      expect(themeSection.items.length, 3);
      expect(
        themeSection.hasMore,
        false,
        reason: 'partial page must short-circuit pagination',
      );
    });

    test(
      'does nothing when section is already at end (hasMore=false)',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        when(
          () => feedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          ),
        ).thenAnswer(
          (_) async =>
              _feedResponseWithIds(const ['a1', 'a2'], page: 1, hasNext: false),
        );

        final container = makeContainer(
          interests: _interestsState(
            favorites: const [ThemeFavoriteRef(slug: 'tech')],
          ),
        );
        addTearDown(container.dispose);

        final initial = await container.read(fluxContinuProvider.future);
        final themeSection =
            initial.sections.whereType<FeedThemeSection>().single;
        expect(themeSection.hasMore, false);

        // Call loadMoreTheme — backend must NOT be hit a second time.
        await container
            .read(fluxContinuProvider.notifier)
            .loadMoreTheme(sectionKey(themeSection));

        // Theme=tech fetch happens exactly once (initial). The page=1
        // continuation fetch in `_fetchAll` is not theme-scoped and matched
        // separately by the default mock; we only assert on theme fetches.
        verify(
          () => feedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: 'tech',
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          ),
        ).called(1);
        verifyNever(
          () => feedRepo.getFeed(
            page: 2,
            limit: any(named: 'limit'),
            theme: 'tech',
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          ),
        );
      },
    );
  });

  group('FluxContinuNotifier — Story 9.2 hotfix (Actus du jour)', () {
    /// Stub Essentiel repo returning a single EssentielArticle so the v3
    /// hi-fi section is built. Distinct from `_StubEssentielRepository`
    /// (which returns an empty list) to drive the coexistence assertion.
    final hiFiArticle = EssentielArticle(
      contentId: 'hifi-1',
      title: 'Hi-fi article',
      url: 'https://x.test/hifi-1',
      publishedAt: DateTime(2026, 1, 1),
      sourceName: 'Source',
      sourceLetter: 'S',
      sectionLabel: 'Tech',
      rank: 1,
    );

    test(
      'EssentielSection (hi-fi) and "Actus du jour" coexist in sections',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        // Digest "normal" with two non-empty topics → builds the legacy
        // "Actus du jour" DigestTopicSection.
        final digest = DigestResponse(
          digestId: 'd1',
          userId: 'u1',
          targetDate: DateTime(2026, 5, 23),
          generatedAt: DateTime(2026, 5, 23),
          topics: [
            const DigestTopic(
              topicId: 't1',
              label: 'Topic A',
              articles: [DigestItem(contentId: 'a1', title: 'A')],
            ),
            const DigestTopic(
              topicId: 't2',
              label: 'Topic B',
              articles: [DigestItem(contentId: 'b1', title: 'B')],
            ),
          ],
        );
        when(() => digestRepo.fetchBothDigests()).thenAnswer(
          (_) async => DualDigestResponse(normal: digest, sereinEnabled: false),
        );

        final container = ProviderContainer(
          overrides: [
            digestRepositoryProvider.overrideWithValue(digestRepo),
            feedRepositoryProvider.overrideWithValue(feedRepo),
            fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
            essentielRepositoryProvider.overrideWithValue(
              _OneArticleEssentielRepository(hiFiArticle),
            ),
            grilleRepositoryProvider.overrideWithValue(_NoGrilleRepository()),
            userInterestsProvider.overrideWith(
              () => _StubUserInterestsNotifier(_interestsState()),
            ),
            sereinToggleProvider.overrideWith(
              (ref) => SereinToggleNotifier(ref),
            ),
          ],
        );
        addTearDown(container.dispose);

        final state = await container.read(fluxContinuProvider.future);

        // Both must be present, with distinct sectionKeys.
        final essentielV3 =
            state.sections.whereType<EssentielSection>().toList();
        final actusDuJour = state.sections
            .whereType<DigestTopicSection>()
            .where((s) => s.kind == SectionKind.essentiel)
            .toList();
        expect(essentielV3, hasLength(1));
        expect(actusDuJour, hasLength(1));
        expect(actusDuJour.single.label, 'Actus du jour');
        // Distinct keys — no collision in the folded/moreOpen maps.
        expect(sectionKey(essentielV3.single), 'essentiel_v3');
        expect(sectionKey(actusDuJour.single), 'essentiel');
        // The dedup pass drops the lead article of "Actus du jour" if it ever
        // overlaps with the hi-fi card — the legacy section must still
        // survive composition though (it carries other topics).
        expect(
          state.sections.indexOf(essentielV3.single),
          lessThan(state.sections.indexOf(actusDuJour.single)),
          reason: 'Hi-fi card renders above the legacy "Actus du jour"',
        );
      },
    );
  });

  group('FluxContinuNotifier — dedup inter-sections', () {
    /// Builds a container whose Essentiel hi-fi card surfaces a single article
    /// with [hiFiContentId], coexisting with the digest [topics] that feed the
    /// legacy "Actus du jour" section.
    ProviderContainer makeDedupContainer({
      required String hiFiContentId,
      required List<DigestTopic> topics,
    }) {
      final hiFi = EssentielArticle(
        contentId: hiFiContentId,
        title: 'Hi-fi $hiFiContentId',
        url: 'https://x.test/$hiFiContentId',
        publishedAt: DateTime(2026, 1, 1),
        sourceName: 'Source',
        sourceLetter: 'S',
        sectionLabel: 'Tech',
        rank: 1,
      );
      final digest = DigestResponse(
        digestId: 'd1',
        userId: 'u1',
        targetDate: DateTime(2026, 5, 23),
        generatedAt: DateTime(2026, 5, 23),
        topics: topics,
      );
      when(() => digestRepo.fetchBothDigests()).thenAnswer(
        (_) async => DualDigestResponse(normal: digest, sereinEnabled: false),
      );
      return ProviderContainer(
        overrides: [
          digestRepositoryProvider.overrideWithValue(digestRepo),
          feedRepositoryProvider.overrideWithValue(feedRepo),
          fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
          essentielRepositoryProvider.overrideWithValue(
            _OneArticleEssentielRepository(hiFi),
          ),
          grilleRepositoryProvider.overrideWithValue(_NoGrilleRepository()),
          userInterestsProvider.overrideWith(
            () => _StubUserInterestsNotifier(_interestsState()),
          ),
          // The real serein toggle watches authStateProvider → Supabase.instance
          // (uninitialized in unit tests). Override with a notifier that skips
          // the auth watch so the provider build doesn't blow up.
          sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref)),
        ],
      );
    }

    test(
        'a topic whose lead is already in Essentiel is dropped from Actus '
        'du jour (Option A), the rest survives', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // Topic A's lead shares the hi-fi card's contentId → it must be dropped.
      // Topic B is untouched → "Actus du jour" survives with one topic.
      final container = makeDedupContainer(
        hiFiContentId: 'shared-1',
        topics: const [
          DigestTopic(
            topicId: 't1',
            label: 'Topic A',
            articles: [DigestItem(contentId: 'shared-1', title: 'A')],
          ),
          DigestTopic(
            topicId: 't2',
            label: 'Topic B',
            articles: [DigestItem(contentId: 'b1', title: 'B')],
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      // Essentiel keeps the shared article.
      final essentiel = state.sections.whereType<EssentielSection>().single;
      expect(essentiel.articles.map((a) => a.contentId), contains('shared-1'));

      // Actus du jour survives but no longer carries the duplicated topic.
      final actus = state.sections
          .whereType<DigestTopicSection>()
          .where((s) => s.kind == SectionKind.essentiel)
          .single;
      final actusLeadIds =
          actus.topics.map((t) => pickTopicLead(t).contentId).toList();
      expect(actusLeadIds, isNot(contains('shared-1')));
      expect(actusLeadIds, contains('b1'));
    });

    test('Actus du jour disappears entirely when fully deduped', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // The only topic's lead is the hi-fi article → Actus becomes empty and
      // must be removed (no orphan banner).
      final container = makeDedupContainer(
        hiFiContentId: 'shared-1',
        topics: const [
          DigestTopic(
            topicId: 't1',
            label: 'Topic A',
            articles: [DigestItem(contentId: 'shared-1', title: 'A')],
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      expect(state.sections.whereType<EssentielSection>(), hasLength(1));
      expect(
        state.sections.whereType<DigestTopicSection>().where(
              (s) => s.kind == SectionKind.essentiel,
            ),
        isEmpty,
        reason: 'A fully-deduped "Actus du jour" must be dropped, not orphaned',
      );
    });
  });

  group('FluxContinuNotifier — fit dynamique « cartes ≤ écran »', () {
    EssentielArticle essArticle(String id) => EssentielArticle(
          contentId: id,
          title: 'Essentiel $id',
          url: 'https://x.test/$id',
          publishedAt: DateTime(2026, 1, 1),
          sourceName: 'Source',
          sourceLetter: 'S',
          sectionLabel: 'Tech',
          rank: 1,
        );

    /// Container with a hero of [essentielIds] and a single 'tech' theme
    /// favorite whose feed carries [themeFeedIds]. [usableHeight] threads the
    /// fit budget (null = pas encore mesuré ⇒ défauts).
    ProviderContainer makeFitContainer({
      required List<String> essentielIds,
      required List<String> themeFeedIds,
      double? usableHeight,
    }) {
      when(
        () => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        ),
      ).thenAnswer(
        (_) async => _feedResponseWithIds(themeFeedIds, hasNext: false),
      );
      return ProviderContainer(
        overrides: [
          digestRepositoryProvider.overrideWithValue(digestRepo),
          feedRepositoryProvider.overrideWithValue(feedRepo),
          fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
          essentielRepositoryProvider.overrideWithValue(
            _FixedEssentielRepository(essentielIds.map(essArticle).toList()),
          ),
          grilleRepositoryProvider.overrideWithValue(_NoGrilleRepository()),
          userInterestsProvider.overrideWith(
            () => _StubUserInterestsNotifier(
              _interestsState(favorites: const [ThemeFavoriteRef(slug: 'tech')]),
            ),
          ),
          sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref)),
          if (usableHeight != null)
            usableViewportHeightProvider.overrideWith((ref) => usableHeight),
        ],
      );
    }

    test(
      'small usable height trims the hero AND releases ejected ids downstream',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        // 4 hero articles ; the 'tech' feed carries the two that would be
        // ejected (e3, e4) plus its own items.
        final container = makeFitContainer(
          essentielIds: const ['e1', 'e2', 'e3', 'e4'],
          themeFeedIds: const ['e3', 'e4', 'x1', 'x2'],
          usableHeight: 500,
        );
        addTearDown(container.dispose);

        final state = await container.read(fluxContinuProvider.future);

        // (a) hero trimmed to the lead + one medium (fitHeroCount(500) == 2).
        final hero = state.sections.whereType<EssentielSection>().single;
        expect(hero.articles.map((a) => a.contentId), ['e1', 'e2']);

        // (b) the ejected ids reappear in the next section (« sortent du pool »).
        final theme = state.sections.whereType<FeedThemeSection>().single;
        expect(theme.items.map((c) => c.id), containsAll(['e3', 'e4']));

        // (c) downstream cap ≤ default (3) and ≥ 1 — fitVisibleCount(500) == 2.
        expect(theme.coreVisibleCount, 2);

        // (d) the "+N" footer count derives correctly (totalCount − cap).
        expect(theme.totalCount - theme.coreVisibleCount, 2);
      },
    );

    test(
      'no measure yet (null height) keeps defaults — hero & dedup untouched',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final container = makeFitContainer(
          essentielIds: const ['e1', 'e2', 'e3', 'e4'],
          themeFeedIds: const ['e3', 'e4', 'x1', 'x2'],
          // usableHeight null ⇒ provider default (no fit applied).
        );
        addTearDown(container.dispose);

        final state = await container.read(fluxContinuProvider.future);

        final hero = state.sections.whereType<EssentielSection>().single;
        expect(hero.articles.map((a) => a.contentId), ['e1', 'e2', 'e3', 'e4']);
        // Hero kept all 4 ⇒ dedup strips e3/e4 from the theme section.
        final theme = state.sections.whereType<FeedThemeSection>().single;
        expect(theme.items.map((c) => c.id), ['x1', 'x2']);
        expect(theme.coreVisibleCount, 3);
      },
    );

    test('the dynamic cap survives a dismiss (copyWith preserves it)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = makeFitContainer(
        essentielIds: const ['e1', 'e2'],
        themeFeedIds: const ['x1', 'x2', 'x3', 'x4'],
        usableHeight: 500,
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);
      final theme = state.sections.whereType<FeedThemeSection>().single;
      expect(theme.coreVisibleCount, 2);

      // Dismissing an item routes through _filterSections → copyWith, which must
      // NOT reset the capped coreVisibleCount back to the default 3.
      container.read(fluxContinuProvider.notifier).confirmDismiss('x4');
      await pumpEventQueue(times: 2);

      final after = container.read(fluxContinuProvider).requireValue;
      final themeAfter = after.sections.whereType<FeedThemeSection>().single;
      expect(themeAfter.coreVisibleCount, 2);
      expect(themeAfter.items.map((c) => c.id), isNot(contains('x4')));
    });
  });

  group('FeedThemeSection.copyWith', () {
    test('preserves coreVisibleCount and the source/theme/pagination fields',
        () {
      const section = FeedThemeSection(
        kind: SectionKind.theme,
        label: 'Tech',
        accent: Color(0xFF000000),
        coreVisibleCount: 3,
        themeSlug: 'tech',
        items: <Content>[],
        currentPage: 2,
        hasMore: true,
      );

      // Untouched copy keeps the dynamic count.
      expect(section.copyWith(hasMore: false).coreVisibleCount, 3);

      // Explicit override sets the capped count while keeping other fields.
      final capped = section.copyWith(coreVisibleCount: 1);
      expect(capped.coreVisibleCount, 1);
      expect(capped.themeSlug, 'tech');
      expect(capped.currentPage, 2);
    });
  });
}

/// Stub EssentielRepository returning exactly one [EssentielArticle] so the
/// hi-fi section is built during the coexistence test.
class _OneArticleEssentielRepository implements EssentielRepository {
  _OneArticleEssentielRepository(this._article);
  final EssentielArticle _article;

  @override
  Future<List<EssentielArticle>?> fetch() async => [_article];
}

/// Stub EssentielRepository returning a fixed list — drives the hero-fit tests.
class _FixedEssentielRepository implements EssentielRepository {
  _FixedEssentielRepository(this._articles);
  final List<EssentielArticle> _articles;

  @override
  Future<List<EssentielArticle>?> fetch() async => _articles;
}
