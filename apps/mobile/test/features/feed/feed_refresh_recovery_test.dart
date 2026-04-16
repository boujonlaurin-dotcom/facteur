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

/// Regression tests for the auth-recovery fix on FeedNotifier.refresh().
///
/// Bug : quand un pull-to-refresh échoue (DioException 403 « stale JWT »,
/// timeout réseau, 500), le notifier passait en `AsyncError` → `state.value`
/// devenait `null` → tous les handlers guardés sur `if (currentState == null)
/// return;` se transformaient en no-op, ET le pull-to-refresh suivant restait
/// coincé sur le même cycle. Conséquence : « refresh mort » jusqu'au kill+relogin.
///
/// Fix : `refresh()` conserve l'état précédent (AsyncData avec les items déjà
/// chargés) si présent, et ne rethrow plus — le RefreshIndicator termine
/// proprement, les retries sont possibles.
///
/// Cf. docs/bugs/bug-feed-403-auth-recovery.md.
class MockFeedRepository extends Mock implements FeedRepository {}

class MockPersonalizationRepository extends Mock
    implements PersonalizationRepository {}

class MockAuthStateNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  MockAuthStateNotifier()
      : super(const app_auth.AuthState(
            user: supabase.User(
                id: 'u1',
                appMetadata: {},
                userMetadata: {},
                aud: 'authenticated',
                createdAt: '2023-01-01')));

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

  Content makeContent(String id) => Content(
        id: id,
        title: 'Title $id',
        url: 'url',
        contentType: ContentType.article,
        publishedAt: DateTime.now(),
        source: mockSource,
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

  DioException _dioException({required int statusCode, String? detail}) {
    final req = RequestOptions(path: '/feed/');
    return DioException(
      requestOptions: req,
      response: Response<dynamic>(
        requestOptions: req,
        statusCode: statusCode,
        data: detail != null ? {'detail': detail} : null,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  group('FeedNotifier.refresh() — recovery from transient failures', () {
    test(
      'DioException 403 after a successful initial load → keeps previous items, no AsyncError freeze',
      () async {
        final initialItems = [makeContent('a'), makeContent('b')];

        // First call (build): return 2 items.
        when(() => mockFeedRepo.getFeed(
              page: any(named: 'page'),
              limit: any(named: 'limit'),
              mode: any(named: 'mode'),
              theme: any(named: 'theme'),
              topic: any(named: 'topic'),
              sourceId: any(named: 'sourceId'),
              entity: any(named: 'entity'),
              keyword: any(named: 'keyword'),
              serein: any(named: 'serein'),
            )).thenAnswer(
          (_) async => FeedResponse(
            items: initialItems,
            pagination:
                Pagination(page: 1, perPage: 20, total: 2, hasNext: false),
          ),
        );

        final notifier = container.read(feedProvider.notifier);
        await container.read(feedProvider.future);
        expect(container.read(feedProvider).value!.items.length, 2);

        // Simulate the 2nd call (refresh) failing with 403 "Email not confirmed".
        when(() => mockFeedRepo.getFeed(
              page: any(named: 'page'),
              limit: any(named: 'limit'),
              mode: any(named: 'mode'),
              theme: any(named: 'theme'),
              topic: any(named: 'topic'),
              sourceId: any(named: 'sourceId'),
              entity: any(named: 'entity'),
              keyword: any(named: 'keyword'),
              serein: any(named: 'serein'),
            )).thenThrow(_dioException(
          statusCode: 403,
          detail: 'Email not confirmed',
        ));

        // Act : refresh fails. Must NOT rethrow and must NOT wipe items.
        await notifier.refresh();

        final asyncState = container.read(feedProvider);
        expect(asyncState.hasError, isFalse,
            reason: 'state must not be AsyncError when we have previous items');
        expect(asyncState.value, isNotNull);
        expect(asyncState.value!.items.length, 2,
            reason: 'previous items must be preserved on refresh failure');
        expect(asyncState.value!.items.map((c) => c.id), ['a', 'b']);
      },
    );

    test(
      'subsequent refresh after a failure can succeed (no frozen provider)',
      () async {
        final initialItems = [makeContent('a')];
        final refreshedItems = [makeContent('x'), makeContent('y')];
        var callCount = 0;

        when(() => mockFeedRepo.getFeed(
              page: any(named: 'page'),
              limit: any(named: 'limit'),
              mode: any(named: 'mode'),
              theme: any(named: 'theme'),
              topic: any(named: 'topic'),
              sourceId: any(named: 'sourceId'),
              entity: any(named: 'entity'),
              keyword: any(named: 'keyword'),
              serein: any(named: 'serein'),
            )).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            // initial build
            return FeedResponse(
              items: initialItems,
              pagination:
                  Pagination(page: 1, perPage: 20, total: 1, hasNext: false),
            );
          } else if (callCount == 2) {
            // first refresh → 500
            throw _dioException(statusCode: 500);
          } else {
            // second refresh → success
            return FeedResponse(
              items: refreshedItems,
              pagination:
                  Pagination(page: 1, perPage: 20, total: 2, hasNext: false),
            );
          }
        });

        final notifier = container.read(feedProvider.notifier);
        await container.read(feedProvider.future);
        expect(container.read(feedProvider).value!.items.length, 1);

        await notifier.refresh(); // fails, items preserved
        expect(container.read(feedProvider).value!.items.length, 1,
            reason: 'items preserved after first failed refresh');

        await notifier.refresh(); // succeeds
        expect(container.read(feedProvider).value!.items.length, 2);
        expect(container.read(feedProvider).value!.items.map((c) => c.id),
            ['x', 'y']);
      },
    );

    test(
      'initial load failure (no previous items) → AsyncError is expected',
      () async {
        when(() => mockFeedRepo.getFeed(
              page: any(named: 'page'),
              limit: any(named: 'limit'),
              mode: any(named: 'mode'),
              theme: any(named: 'theme'),
              topic: any(named: 'topic'),
              sourceId: any(named: 'sourceId'),
              entity: any(named: 'entity'),
              keyword: any(named: 'keyword'),
              serein: any(named: 'serein'),
            )).thenThrow(_dioException(statusCode: 500));

        // Trigger build; it should surface as AsyncError since there's no
        // prior state to fall back to.
        final async = await container
            .read(feedProvider.future)
            .then<Object?>((s) => s)
            .catchError((Object e) => e);

        expect(async, isA<DioException>());
        // And the notifier state is AsyncError (correct behaviour for a cold
        // first load with no items to preserve).
        expect(container.read(feedProvider).hasError, isTrue);
      },
    );
  });
}
