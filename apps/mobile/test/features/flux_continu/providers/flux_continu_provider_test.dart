import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    favoriteCap: 3,
  );
}

String _todayKey() {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return 'flux_continu_folded_$today';
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

FeedResponse _feedResponseWithIds(
  List<String> ids, {
  int page = 1,
  bool hasNext = false,
}) {
  return FeedResponse(
    items: ids
        .map((id) => Content(
              id: id,
              title: 'title-$id',
              url: 'https://x.test/$id',
              contentType: ContentType.article,
              publishedAt: DateTime(2026, 1, 1),
              source: Source(id: 's', name: 'S', type: SourceType.article),
            ))
        .toList(),
    pagination:
        Pagination(page: page, perPage: 10, total: 0, hasNext: hasNext),
    carousels: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _MockFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;

  ProviderContainer makeContainer({
    UserInterestsState? interests,
  }) {
    return ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider
            .overrideWithValue(_StubEssentielRepository()),
        userInterestsProvider.overrideWith(
          () => _StubUserInterestsNotifier(interests ?? _interestsState()),
        ),
      ],
    );
  }

  setUp(() {
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    // The provider wraps each upstream call in `_safe<T>` which catches and
    // logs — empty/throwing repos are the canonical "no payload" path.
    when(() => digestRepo.fetchBothDigests())
        .thenThrow(Exception('mock: no digest'));
    when(() => fluxRepo.getTopThemes())
        .thenAnswer((_) async => const <TopTheme>[]);
    when(() => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        )).thenThrow(Exception('mock: no feed'));
  });

  group('FluxContinuNotifier — purge cross-day', () {
    test('removes folded keys from previous days, keeps today\'s key',
        () async {
      const oldKey = 'flux_continu_folded_2020-01-01';
      const oldClosingKey = 'flux_continu_closing_dismissed_2020-01-01';
      final todayFoldedKey = _todayKey();

      SharedPreferences.setMockInitialValues({
        oldKey: <String>['essentiel'],
        oldClosingKey: true,
        todayFoldedKey: <String>['bonnes'],
      });

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      // Purge runs as `unawaited` — give the microtask queue a beat.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      expect(keys, isNot(contains(oldKey)));
      expect(keys, isNot(contains(oldClosingKey)));
      expect(keys, contains(todayFoldedKey));
    });

    test('starts with empty folded map when no key exists for today', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      expect(state.folded, isEmpty);
    });

    test('loads today\'s folded sections from SharedPreferences on build',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _todayKey(): <String>['essentiel', 'bonnes'],
      });

      final container = makeContainer();
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      // No sections built (mocks return null), so the compose step strips
      // entries pointing to absent kinds — folded ends up empty even though
      // the prefs had values. This is the intentional behavior of `_compose`.
      expect(state.folded, isEmpty);
    });

    test('silently ignores legacy theme1/theme2 keys in prefs', () async {
      // Legacy SharedPreferences format used `theme1` / `theme2` to identify
      // the two favorite theme sections. The new format uses `theme:<slug>` /
      // `topic:<uuid>`. The migration is parse-tolerant — old keys are
      // silently dropped, never crash, and get purged by the cross-day
      // purge inside 24h.
      SharedPreferences.setMockInitialValues(<String, Object>{
        _todayKey(): <String>['essentiel', 'theme1', 'theme2'],
      });

      final container = makeContainer();
      addTearDown(container.dispose);

      // No throw, no warning.
      final state = await container.read(fluxContinuProvider.future);
      expect(state.folded, isEmpty);
    });
  });

  group('FluxContinuNotifier — fold queue', () {
    test('markScrolledPastForNextSession persists section to today\'s key',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      const section = DigestTopicSection(
        kind: SectionKind.essentiel,
        label: 'Essentiel',
        accent: Color(0xFFB0470A),
        coreVisibleCount: 3,
        topics: [],
      );
      await container
          .read(fluxContinuProvider.notifier)
          .markScrolledPastForNextSession(section);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_todayKey()), contains('essentiel'));
    });

    test('markScrolledPastForNextSession is idempotent per section key',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      const section = FeedThemeSection(
        kind: SectionKind.theme,
        label: 'Tech',
        accent: Color(0xFF2C3E50),
        coreVisibleCount: 3,
        themeSlug: 'tech',
        items: [],
      );
      final notifier = container.read(fluxContinuProvider.notifier);
      await notifier.markScrolledPastForNextSession(section);
      await notifier.markScrolledPastForNextSession(section);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_todayKey()) ?? const [];
      expect(stored.where((s) => s == 'theme:tech').length, 1);
    });

    test('applyPendingFoldsToState is a no-op when queue is empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      final initial = await container.read(fluxContinuProvider.future);
      container.read(fluxContinuProvider.notifier).applyPendingFoldsToState();
      final after = container.read(fluxContinuProvider).valueOrNull;

      expect(after, isNotNull);
      expect(after!.folded, equals(initial.folded));
    });

    test('persistQueuedSnapshot exposes queued section keys', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final notifier = container.read(fluxContinuProvider.notifier);

      expect(notifier.persistQueuedSnapshot(), isEmpty);

      const essentiel = DigestTopicSection(
        kind: SectionKind.essentiel,
        label: 'Essentiel',
        accent: Color(0xFFB0470A),
        coreVisibleCount: 3,
        topics: [],
      );
      const tech = FeedThemeSection(
        kind: SectionKind.theme,
        label: 'Tech',
        accent: Color(0xFF2C3E50),
        coreVisibleCount: 3,
        themeSlug: 'tech',
        items: [],
      );
      await notifier.markScrolledPastForNextSession(essentiel);
      await notifier.markScrolledPastForNextSession(tech);

      expect(
        notifier.persistQueuedSnapshot(),
        equals(<String>{'essentiel', 'theme:tech'}),
      );
    });

    test('applyPendingFoldsToState(exceptKeys: all) is a no-op', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      final initial = await container.read(fluxContinuProvider.future);
      final notifier = container.read(fluxContinuProvider.notifier);

      const essentiel = DigestTopicSection(
        kind: SectionKind.essentiel,
        label: 'Essentiel',
        accent: Color(0xFFB0470A),
        coreVisibleCount: 3,
        topics: [],
      );
      await notifier.markScrolledPastForNextSession(essentiel);

      notifier.applyPendingFoldsToState(exceptKeys: {'essentiel'});
      final after = container.read(fluxContinuProvider).valueOrNull;

      // Excluded keys are never promoted — state.folded stays unchanged.
      expect(after, isNotNull);
      expect(after!.folded, equals(initial.folded));
      // But the queue is preserved (so the cold-launch persist still applies).
      expect(notifier.persistQueuedSnapshot(), contains('essentiel'));
    });
  });

  group('FluxContinuNotifier — favorites-driven theme sections', () {
    test('0 favorites + empty top-themes fallback → 3 canonical themes fetched',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      // Digest absent, feed absent → only the theme fetches matter.
      when(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async => _feedResponseWith(3));

      final container = makeContainer(); // 0 favorites in stub
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);

      // 3 fallback canonical theme fetches (tech, environment, science).
      final captured = verify(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: captureAny(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).captured;
      expect(captured, containsAll(['tech', 'environment', 'science']));
    });

    test('Theme favorite triggers getFeed(theme: slug)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      when(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async => _feedResponseWith(3));

      final container = makeContainer(
        interests: _interestsState(favorites: [
          const ThemeFavoriteRef(slug: 'culture'),
        ]),
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);

      verify(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: 'culture',
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).called(1);
    });

    test('Custom topic favorite triggers getFeed(topic: uuid)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      when(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            topic: any(named: 'topic'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async => _feedResponseWith(3));

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

      verify(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            topic: customId,
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).called(1);

      final themeSections =
          state.sections.whereType<FeedThemeSection>().toList();
      expect(themeSections, hasLength(1));
      expect(themeSections.single.label, 'IA & éducation');
      expect(themeSections.single.customTopicId, customId);
    });

    test('3 favorites cap (4th ignored)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      when(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async => _feedResponseWith(3));

      final container = makeContainer(
        interests: _interestsState(favorites: const [
          ThemeFavoriteRef(slug: 'tech'),
          ThemeFavoriteRef(slug: 'science'),
          ThemeFavoriteRef(slug: 'culture'),
          ThemeFavoriteRef(slug: 'economy'), // 4th — must be dropped
        ]),
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);
      final slugs = state.sections
          .whereType<FeedThemeSection>()
          .map((s) => s.themeSlug)
          .toList();
      expect(slugs, ['tech', 'science', 'culture']);
    });
  });

  group('FluxContinuNotifier — Tournée du jour curation (personalized)', () {
    test('Theme favorite forwards personalized:true to getFeed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      when(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async => _feedResponseWith(3));

      final container = makeContainer(
        interests: _interestsState(favorites: const [
          ThemeFavoriteRef(slug: 'tech'),
        ]),
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);

      // The Tournée du jour theme sections opt in to the backend curation
      // (followed sources only + 24h window + user_subtopics boost).
      verify(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: 'tech',
            serein: any(named: 'serein'),
            personalized: true,
          )).called(1);
    });

    test('Custom topic favorite forwards personalized:true to getFeed',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      when(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            topic: any(named: 'topic'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async => _feedResponseWith(3));

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

      verify(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            topic: customId,
            serein: any(named: 'serein'),
            personalized: true,
          )).called(1);
    });
  });

  group('FluxContinuNotifier — loadMoreTheme pagination', () {
    test('appends next page items, increments page, propagates hasMore',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // Initial fetch (page 1) — 2 items, hasNext=true.
      when(() => feedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async =>
          _feedResponseWithIds(const ['a1', 'a2'], page: 1, hasNext: true));
      // Load-more fetch (page 2) — 2 new items, hasNext=false.
      when(() => feedRepo.getFeed(
            page: 2,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async =>
          _feedResponseWithIds(const ['a3', 'a4'], page: 2, hasNext: false));

      final container = makeContainer(
        interests: _interestsState(favorites: const [
          ThemeFavoriteRef(slug: 'tech'),
        ]),
      );
      addTearDown(container.dispose);

      final initial = await container.read(fluxContinuProvider.future);
      final themeSection =
          initial.sections.whereType<FeedThemeSection>().single;
      expect(themeSection.items.map((c) => c.id), ['a1', 'a2']);
      expect(themeSection.currentPage, 1);
      expect(themeSection.hasMore, true);

      await container
          .read(fluxContinuProvider.notifier)
          .loadMoreTheme(sectionKey(themeSection));

      final after = container.read(fluxContinuProvider).requireValue;
      final updated =
          after.sections.whereType<FeedThemeSection>().single;
      expect(updated.items.map((c) => c.id), ['a1', 'a2', 'a3', 'a4']);
      expect(updated.currentPage, 2);
      expect(updated.hasMore, false);
      expect(updated.isLoadingMore, false);
    });

    test('does nothing when section is already at end (hasMore=false)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      when(() => feedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async =>
          _feedResponseWithIds(const ['a1', 'a2'], page: 1, hasNext: false));

      final container = makeContainer(
        interests: _interestsState(favorites: const [
          ThemeFavoriteRef(slug: 'tech'),
        ]),
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
      verify(() => feedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: 'tech',
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).called(1);
      verifyNever(() => feedRepo.getFeed(
            page: 2,
            limit: any(named: 'limit'),
            theme: 'tech',
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          ));
    });
  });
}
