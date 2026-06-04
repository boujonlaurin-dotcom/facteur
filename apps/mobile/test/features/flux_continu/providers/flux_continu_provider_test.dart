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
    favoriteCap: 5,
  );
}

String _todayKey() {
  // Mirror the provider's 07:30-local tournée-day boundary: before 07:30 the
  // active prefs key still references yesterday so the fold survives across
  // midnight (the digest hasn't regenerated yet).
  final now = DateTime.now();
  final shifted =
      (now.hour < 7 || (now.hour == 7 && now.minute < 30))
          ? now.subtract(const Duration(days: 1))
          : now;
  final day = shifted.toIso8601String().substring(0, 10);
  return 'flux_continu_folded_$day';
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

    test('unfoldLocally purges _persistQueued and prefs so cold launch '
        'does not re-fold the section', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final notifier = container.read(fluxContinuProvider.notifier);
      const essentiel = DigestTopicSection(
        kind: SectionKind.essentiel,
        label: 'Actus du jour',
        accent: Color(0xFFB0470A),
        coreVisibleCount: 3,
        topics: [],
      );

      // Queue the fold (simulates the user scrolling past the section).
      await notifier.markScrolledPastForNextSession(essentiel);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_todayKey()), contains('essentiel'));
      expect(notifier.persistQueuedSnapshot(), contains('essentiel'));

      // User taps the folded card to re-expand. The fix must clear both the
      // in-memory queue AND the prefs blob, otherwise the next cold launch
      // would restore the fold and leave the section permanently folded.
      notifier.unfoldLocally(essentiel);
      // Give the unawaited _persistFolded a tick to flush.
      await Future<void>.delayed(Duration.zero);

      expect(notifier.persistQueuedSnapshot(), isEmpty);
      expect(prefs.getStringList(_todayKey()) ?? const <String>[],
          isNot(contains('essentiel')));
    });

    test('markScrolledPastForNextSession exposes the key in state', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final notifier = container.read(fluxContinuProvider.notifier);
      const tech = FeedThemeSection(
        kind: SectionKind.theme,
        label: 'Tech',
        accent: Color(0xFF2C3E50),
        coreVisibleCount: 3,
        themeSlug: 'tech',
        items: [],
      );

      await notifier.markScrolledPastForNextSession(tech);
      final state = container.read(fluxContinuProvider).valueOrNull;

      expect(state, isNotNull);
      expect(state!.markedForNextSession, contains('theme:tech'));
      expect(state.isMarkedForNextSession(tech), isTrue);
    });

    test('unfoldLocally removes the key from state.markedForNextSession',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final notifier = container.read(fluxContinuProvider.notifier);
      const essentiel = DigestTopicSection(
        kind: SectionKind.essentiel,
        label: 'Actus du jour',
        accent: Color(0xFFB0470A),
        coreVisibleCount: 3,
        topics: [],
      );

      await notifier.markScrolledPastForNextSession(essentiel);
      expect(
        container.read(fluxContinuProvider).valueOrNull?.markedForNextSession,
        contains('essentiel'),
      );

      notifier.unfoldLocally(essentiel);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(fluxContinuProvider).valueOrNull?.markedForNextSession,
        isNot(contains('essentiel')),
      );
    });

    test(
        'applyPendingFoldsToState drops promoted keys from '
        'markedForNextSession (but keeps excluded ones)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final notifier = container.read(fluxContinuProvider.notifier);
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

      notifier.applyPendingFoldsToState(exceptKeys: {'theme:tech'});
      final state = container.read(fluxContinuProvider).valueOrNull;

      expect(state, isNotNull);
      expect(state!.markedForNextSession, isNot(contains('essentiel')));
      expect(state.markedForNextSession, contains('theme:tech'));
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

    test('5 favorites cap (6th ignored)', () async {
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
          ThemeFavoriteRef(slug: 'economy'),
          ThemeFavoriteRef(slug: 'politics'),
          ThemeFavoriteRef(slug: 'sport'), // 6th — must be dropped
        ]),
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

      // Initial fetch (page 1) — 10 items (= page limit), hasNext=true.
      // The page must be FULL to keep hasMore=true after the safety-net
      // guard "items.length < limit ⇒ hasMore=false" (cf.
      // `_kThemeSectionPageLimit` in flux_continu_provider.dart).
      final pageOneIds = List.generate(10, (i) => 'a${i + 1}');
      final pageTwoIds = List.generate(3, (i) => 'b${i + 1}');
      when(() => feedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async =>
          _feedResponseWithIds(pageOneIds, page: 1, hasNext: true));
      // Load-more fetch (page 2) — 3 new items, hasNext=false (last page).
      when(() => feedRepo.getFeed(
            page: 2,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async =>
          _feedResponseWithIds(pageTwoIds, page: 2, hasNext: false));

      final container = makeContainer(
        interests: _interestsState(favorites: const [
          ThemeFavoriteRef(slug: 'tech'),
        ]),
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
      final updated =
          after.sections.whereType<FeedThemeSection>().single;
      expect(updated.items.map((c) => c.id), [...pageOneIds, ...pageTwoIds]);
      expect(updated.currentPage, 2);
      expect(updated.hasMore, false);
      expect(updated.isLoadingMore, false);
    });

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
      when(() => feedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            serein: any(named: 'serein'),
            personalized: any(named: 'personalized'),
          )).thenAnswer((_) async =>
          _feedResponseWithIds(const ['a1', 'a2', 'a3'], page: 1, hasNext: true));

      final container = makeContainer(
        interests: _interestsState(favorites: const [
          ThemeFavoriteRef(slug: 'tech'),
        ]),
      );
      addTearDown(container.dispose);

      final initial = await container.read(fluxContinuProvider.future);
      final themeSection =
          initial.sections.whereType<FeedThemeSection>().single;
      expect(themeSection.items.length, 3);
      expect(themeSection.hasMore, false,
          reason: 'partial page must short-circuit pagination');
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

    test('EssentielSection (hi-fi) and "Actus du jour" coexist in sections',
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
          DigestTopic(
            topicId: 't1',
            label: 'Topic A',
            articles: const [DigestItem(contentId: 'a1', title: 'A')],
          ),
          DigestTopic(
            topicId: 't2',
            label: 'Topic B',
            articles: const [DigestItem(contentId: 'b1', title: 'B')],
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
          userInterestsProvider.overrideWith(
            () => _StubUserInterestsNotifier(_interestsState()),
          ),
          sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref)),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      // Both must be present, with distinct sectionKeys.
      final essentielV3 = state.sections.whereType<EssentielSection>().toList();
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
    });
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
          essentielRepositoryProvider
              .overrideWithValue(_OneArticleEssentielRepository(hiFi)),
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
        state.sections
            .whereType<DigestTopicSection>()
            .where((s) => s.kind == SectionKind.essentiel),
        isEmpty,
        reason: 'A fully-deduped "Actus du jour" must be dropped, not orphaned',
      );
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
