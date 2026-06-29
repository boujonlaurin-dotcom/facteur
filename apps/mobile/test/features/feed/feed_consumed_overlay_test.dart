import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/services/read_sync_service.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/repositories/personalization_repository.dart';
import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Régression : le badge « Lu » disparaissait au retour dans le feed quand un
/// reload (pull-to-refresh, reprise d'app, pagination) reconstruisait les
/// `Content` depuis la réponse réseau — encore `unseen` tant que le POST
/// `/status` n'avait pas abouti — sans ré-appliquer le set consommé en mémoire.
///
/// Le fix fait de [consumedContentIdsProvider] la source d'autorité ré-appliquée
/// sur chaque reload via `_overlayConsumed`. Ces tests vérifient que refresh()
/// et loadMore() préservent le statut consommé même quand le serveur répond
/// `unseen`.
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

  // Toujours `unseen` : simule la réponse serveur stale (POST /status pas
  // encore abouti).
  Content makeContent(String id) => Content(
    id: id,
    title: 'Title $id',
    url: 'url',
    contentType: ContentType.article,
    publishedAt: DateTime.now(),
    source: mockSource,
  );

  FeedResponse feedOf(List<Content> items, {bool hasNext = false}) =>
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

  void stubGetFeed(FeedResponse Function() answer) {
    when(
      () => mockFeedRepo.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        mode: any(named: 'mode'),
        theme: any(named: 'theme'),
        topic: any(named: 'topic'),
        sourceId: any(named: 'sourceId'),
        entity: any(named: 'entity'),
        keyword: any(named: 'keyword'),
        serein: any(named: 'serein'),
      ),
    ).thenAnswer((_) async => answer());
  }

  test(
    'refresh() ré-applique le statut consommé depuis consumedContentIdsProvider '
    'même quand le serveur renvoie unseen',
    () async {
      stubGetFeed(() => feedOf([makeContent('a'), makeContent('b')]));

      final notifier = container.read(feedProvider.notifier);
      await container.read(feedProvider.future);

      // L'utilisateur ouvre 'a' → markConsumed alimente le set durable.
      container.read(consumedContentIdsProvider.notifier).state = {'a'};

      await notifier.refresh();

      final items = container.read(feedProvider).value!.items;
      expect(
        items.firstWhere((c) => c.id == 'a').status,
        ContentStatus.consumed,
        reason: 'le badge « Lu » doit survivre à un pull-to-refresh',
      );
      expect(items.firstWhere((c) => c.id == 'b').status, ContentStatus.unseen);
    },
  );

  test(
    'loadMore() superpose le statut consommé sur les items appendus',
    () async {
      var callCount = 0;
      stubGetFeed(() {
        callCount++;
        if (callCount == 1) {
          return feedOf([makeContent('a')], hasNext: true);
        }
        // Page 2 contient 'c' déjà lu dans la session.
        return feedOf([makeContent('c')]);
      });

      final notifier = container.read(feedProvider.notifier);
      await container.read(feedProvider.future);

      container.read(consumedContentIdsProvider.notifier).state = {'c'};

      await notifier.loadMore();

      final items = container.read(feedProvider).value!.items;
      expect(
        items.firstWhere((c) => c.id == 'c').status,
        ContentStatus.consumed,
        reason: 'un article lu en session reste « Lu » à la pagination',
      );
    },
  );

  test(
    'build() initial superpose le set consommé déjà réamorcé (cold-load) '
    'avant l\'arrivée de la page réseau unseen',
    () async {
      stubGetFeed(() => feedOf([makeContent('a'), makeContent('b')]));

      // La file durable Hive a réamorcé le set avant le premier build réseau.
      container.read(consumedContentIdsProvider.notifier).state = {'a'};

      await container.read(feedProvider.future);

      final items = container.read(feedProvider).value!.items;
      expect(
        items.firstWhere((c) => c.id == 'a').status,
        ContentStatus.consumed,
        reason: 'le cold-load ne doit pas repeindre un article lu en non-lu',
      );
      expect(items.firstWhere((c) => c.id == 'b').status, ContentStatus.unseen);
    },
  );

  test(
    'refresh() sans aucun id consommé laisse tous les items unseen',
    () async {
      stubGetFeed(() => feedOf([makeContent('a'), makeContent('b')]));

      final notifier = container.read(feedProvider.notifier);
      await container.read(feedProvider.future);
      await notifier.refresh();

      final items = container.read(feedProvider).value!.items;
      expect(items.every((c) => c.status == ContentStatus.unseen), isTrue);
    },
  );
}
