import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/repositories/personalization_repository.dart';
import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Regression tests for `FeedNotifier.refreshForWidget()` — the explicit
/// refresh path wired to the home-screen widget's refresh button.
///
/// Bug (widget « 1 seul article » chez Django) : le bouton refresh du widget
/// se contentait d'appeler `refresh()`, qui (a) ne pousse jamais la version
/// canonique **non filtrée** quand un filtre Flâner est actif, et (b) peut
/// rester un no-op silencieux. `refreshForWidget()` garantit qu'un appui
/// re-pousse toujours le Flux non filtré, sans perturber l'état filtré affiché.
class MockFeedRepository extends Mock implements FeedRepository {}

class MockPersonalizationRepository extends Mock
    implements PersonalizationRepository {}

class MockAuthStateNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  MockAuthStateNotifier()
      : super(
          const app_auth.AuthState(
            user: supabase.User(
              id: 'u1',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2023-01-01',
              emailConfirmedAt: '2023-01-01',
            ),
          ),
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFeedRepository mockFeedRepo;
  late MockPersonalizationRepository mockPersoRepo;
  late MockAuthStateNotifier mockAuthNotifier;
  late ProviderContainer container;

  final mockSource = Source(
    id: 's1',
    name: 'Source 1',
    url: 'url',
    type: SourceType.article,
    theme: 'TECH',
  );

  Content makeContent(String id) => Content(
        id: id,
        title: 'Title $id',
        url: 'url',
        contentType: ContentType.article,
        publishedAt: DateTime.now(),
        source: mockSource,
      );

  FeedResponse resp(List<Content> items, {bool hasNext = false}) =>
      FeedResponse(
        items: items,
        pagination: Pagination(
          page: 1,
          perPage: 20,
          total: items.length,
          hasNext: hasNext,
        ),
      );

  setUp(() {
    mockFeedRepo = MockFeedRepository();
    mockPersoRepo = MockPersonalizationRepository();
    mockAuthNotifier = MockAuthStateNotifier();

    container = ProviderContainer(
      overrides: [
        feedRepositoryProvider.overrideWithValue(mockFeedRepo),
        personalizationRepositoryProvider.overrideWithValue(mockPersoRepo),
        app_auth.authStateProvider.overrideWith((ref) => mockAuthNotifier),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  DioException dioError() {
    final req = RequestOptions(path: '/feed/');
    return DioException(
      requestOptions: req,
      response: Response<dynamic>(
        requestOptions: req,
        statusCode: 500,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  test(
    'refreshForWidget fetches the UNFILTERED feed even while a Flâner filter is active, '
    'without disturbing the in-app filtered state',
    () async {
      // getFeed returns the filtered payload when `mode` is set, the canonical
      // unfiltered payload otherwise — so we can assert which one was fetched.
      when(
        () => mockFeedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          contentType: any(named: 'contentType'),
          savedOnly: any(named: 'savedOnly'),
          mode: any(named: 'mode'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          hasNote: any(named: 'hasNote'),
          sourceId: any(named: 'sourceId'),
          entity: any(named: 'entity'),
          keyword: any(named: 'keyword'),
          includeUnfollowed: any(named: 'includeUnfollowed'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
          followedOnly: any(named: 'followedOnly'),
          forceFresh: any(named: 'forceFresh'),
        ),
      ).thenAnswer((inv) async {
        final mode = inv.namedArguments[#mode] as String?;
        if (mode == 'tech') {
          return resp([makeContent('filtered-1')]);
        }
        return resp([makeContent('flux-a'), makeContent('flux-b')]);
      });

      final notifier = container.read(feedProvider.notifier);
      await container.read(feedProvider.future);

      // Apply an in-app filter → visible feed becomes the filtered payload.
      await notifier.setFilter('tech');
      expect(container.read(feedProvider).value!.items.map((c) => c.id), [
        'filtered-1',
      ]);

      // Widget refresh button.
      await notifier.refreshForWidget();

      // The visible (filtered) state must be untouched...
      expect(
        container.read(feedProvider).value!.items.map((c) => c.id),
        ['filtered-1'],
        reason: 'refreshForWidget must not overwrite the in-app filtered view',
      );

      // ...and an unfiltered, force-fresh fetch must have happened for the widget.
      verify(
        () => mockFeedRepo.getFeed(
          page: 1,
          limit: any(named: 'limit'),
          mode: null,
          theme: null,
          topic: null,
          sourceId: null,
          entity: null,
          keyword: null,
          serein: any(named: 'serein'),
          forceFresh: true,
        ),
      ).called(1);
    },
  );

  test(
    'refreshForWidget (unfiltered) leaves the visible feed alone — it refreshes '
    'the widget, not the screen under the finger',
    () async {
      var call = 0;
      when(
        () => mockFeedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          contentType: any(named: 'contentType'),
          savedOnly: any(named: 'savedOnly'),
          mode: any(named: 'mode'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          hasNote: any(named: 'hasNote'),
          sourceId: any(named: 'sourceId'),
          entity: any(named: 'entity'),
          keyword: any(named: 'keyword'),
          includeUnfollowed: any(named: 'includeUnfollowed'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
          followedOnly: any(named: 'followedOnly'),
          forceFresh: any(named: 'forceFresh'),
        ),
      ).thenAnswer((_) async {
        call++;
        if (call == 1) return resp([makeContent('old')]);
        return resp([makeContent('fresh-1'), makeContent('fresh-2')]);
      });

      final notifier = container.read(feedProvider.notifier);
      await container.read(feedProvider.future);
      expect(container.read(feedProvider).value!.items.map((c) => c.id), [
        'old',
      ]);

      await notifier.refreshForWidget();

      // Le `state = AsyncData(...)` d'avant s'exécutait juste après le
      // `router.go('/flaner')` du deep-link : l'état visible était remplacé
      // pendant que FlanerScreen se montait (« le bouton refresh plante
      // Flâner »). Cf. docs/bugs/bug-widget-fiabilite.md (C4).
      expect(
        container.read(feedProvider).value!.items.map((c) => c.id),
        ['old'],
        reason: 'refreshForWidget must never mutate the visible feed state',
      );

      // Le snapshot non filtré, lui, a bien été rafraîchi (c'est ce qui part
      // vers le widget).
      expect(
        notifier.globalItems.map((c) => c.id),
        ['fresh-1', 'fresh-2'],
      );
    },
  );

  test(
    'refreshForWidget never throws and preserves state on a network failure',
    () async {
      var call = 0;
      when(
        () => mockFeedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          contentType: any(named: 'contentType'),
          savedOnly: any(named: 'savedOnly'),
          mode: any(named: 'mode'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          hasNote: any(named: 'hasNote'),
          sourceId: any(named: 'sourceId'),
          entity: any(named: 'entity'),
          keyword: any(named: 'keyword'),
          includeUnfollowed: any(named: 'includeUnfollowed'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
          followedOnly: any(named: 'followedOnly'),
          forceFresh: any(named: 'forceFresh'),
        ),
      ).thenAnswer((_) async {
        call++;
        if (call == 1) return resp([makeContent('a'), makeContent('b')]);
        throw dioError();
      });

      final notifier = container.read(feedProvider.notifier);
      await container.read(feedProvider.future);
      expect(container.read(feedProvider).value!.items.length, 2);

      // Must complete without throwing.
      await notifier.refreshForWidget();

      final state = container.read(feedProvider);
      expect(state.hasError, isFalse);
      expect(state.value!.items.map((c) => c.id), ['a', 'b']);
    },
  );

  // ────────────────────────────────────────────────────────────
  // C5 — profondeur du payload widget
  // ────────────────────────────────────────────────────────────
  //
  // Le widget était alimenté par `state.items`, qui rétrécit au fil de la
  // lecture (overlay `_consumedContentIds`). Après quelques articles lus il ne
  // restait que ~9 lignes sur l'écran d'accueil, et rien ne reconstituait la
  // profondeur. Cf. docs/bugs/bug-widget-fiabilite.md (C5).
  group('buffer widget (mergeIntoWidgetBuffer)', () {
    late FeedNotifier notifier;

    setUp(() async {
      when(
        () => mockFeedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          contentType: any(named: 'contentType'),
          savedOnly: any(named: 'savedOnly'),
          mode: any(named: 'mode'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          hasNote: any(named: 'hasNote'),
          sourceId: any(named: 'sourceId'),
          entity: any(named: 'entity'),
          keyword: any(named: 'keyword'),
          includeUnfollowed: any(named: 'includeUnfollowed'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
          followedOnly: any(named: 'followedOnly'),
          forceFresh: any(named: 'forceFresh'),
        ),
      ).thenAnswer((_) async => resp(const []));

      notifier = container.read(feedProvider.notifier);
      await container.read(feedProvider.future);
    });

    test('ne rétrécit pas quand la liste visible rétrécit (lecture in-app)',
        () {
      final full = [
        makeContent('a'),
        makeContent('b'),
        makeContent('c'),
        makeContent('d'),
      ];
      expect(notifier.mergeIntoWidgetBuffer(full).length, 4);

      // L'utilisateur lit a et b → `state.items` n'en contient plus que 2.
      final afterReading = [makeContent('c'), makeContent('d')];
      final merged = notifier.mergeIntoWidgetBuffer(afterReading);

      expect(merged.length, 4, reason: 'le widget ne perd pas de profondeur');
      expect(merged.map((c) => c.id), ['c', 'd', 'a', 'b']);
    });

    test('les entrées fraîches passent en tête, dédupliquées par id', () {
      notifier.mergeIntoWidgetBuffer([makeContent('old1'), makeContent('old2')]);
      final merged = notifier.mergeIntoWidgetBuffer([
        makeContent('new1'),
        makeContent('old1'),
      ]);
      expect(merged.map((c) => c.id), ['new1', 'old1', 'old2']);
    });

    test('cape à 80 en évinçant les plus anciennes', () {
      notifier.mergeIntoWidgetBuffer(
        List.generate(80, (i) => makeContent('old$i')),
      );
      final merged = notifier.mergeIntoWidgetBuffer(
        List.generate(10, (i) => makeContent('new$i')),
      );
      expect(merged.length, 80);
      expect(merged.take(10).map((c) => c.id),
          List.generate(10, (i) => 'new$i'));
      expect(merged.map((c) => c.id), isNot(contains('old79')));
    });

    test('une page vide préserve le buffer', () {
      notifier.mergeIntoWidgetBuffer([makeContent('a'), makeContent('b')]);
      final merged = notifier.mergeIntoWidgetBuffer(const []);
      expect(merged.map((c) => c.id), ['a', 'b']);
    });
  });
}
