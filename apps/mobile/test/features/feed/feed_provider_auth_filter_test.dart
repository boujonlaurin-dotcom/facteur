import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/sources/models/source_model.dart';

class MockFeedRepository extends Mock implements FeedRepository {}

class MockAuthStateNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  MockAuthStateNotifier() : super(app_auth.AuthState(user: makeUser('u1')));

  void setAuth(app_auth.AuthState next) {
    state = next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

supabase.User makeUser(String id) => supabase.User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2023-01-01',
      emailConfirmedAt: '2023-01-01',
    );

void main() {
  late MockFeedRepository feedRepository;
  late MockAuthStateNotifier authNotifier;
  late ProviderContainer container;
  late int feedCalls;

  final source = Source(
    id: 'source-1',
    name: 'Source 1',
    url: 'https://example.test',
    type: SourceType.article,
    theme: 'TECH',
  );

  Content content(String id) => Content(
        id: id,
        title: 'Title $id',
        url: 'https://example.test/$id',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 1, 1),
        source: source,
      );

  void stubFeed() {
    when(
      () => feedRepository.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        mode: any(named: 'mode'),
        theme: any(named: 'theme'),
        topic: any(named: 'topic'),
        sourceId: any(named: 'sourceId'),
        entity: any(named: 'entity'),
        keyword: any(named: 'keyword'),
        includeUnfollowed: any(named: 'includeUnfollowed'),
        serein: any(named: 'serein'),
      ),
    ).thenAnswer((invocation) async {
      feedCalls++;
      final sourceId = invocation.namedArguments[#sourceId] as String?;
      final theme = invocation.namedArguments[#theme] as String?;
      final keyword = invocation.namedArguments[#keyword] as String?;
      final suffix = sourceId ?? theme ?? keyword ?? 'default';
      return FeedResponse(
        items: [content(suffix)],
        pagination: Pagination(page: 1, perPage: 20, total: 1, hasNext: false),
      );
    });
  }

  setUp(() {
    feedRepository = MockFeedRepository();
    authNotifier = MockAuthStateNotifier();
    feedCalls = 0;
    stubFeed();

    container = ProviderContainer(
      overrides: [
        feedRepositoryProvider.overrideWithValue(feedRepository),
        app_auth.authStateProvider.overrideWith((ref) => authNotifier),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('token refresh does not reset filters or refetch the feed', () async {
    final notifier = container.read(feedProvider.notifier);
    await container.read(feedProvider.future);

    await notifier.setSource('source-1');
    expect(notifier.selectedSourceId, 'source-1');
    expect(container.read(feedFilterSelectionProvider).sourceId, 'source-1');

    final callsBeforeTokenRefresh = feedCalls;

    authNotifier.setAuth(
      authNotifier.state.copyWith(lastTokenRefreshAt: DateTime(2026, 1, 1, 12)),
    );
    await container.pump();

    expect(notifier.selectedSourceId, 'source-1');
    expect(container.read(feedFilterSelectionProvider).sourceId, 'source-1');
    expect(feedCalls, callsBeforeTokenRefresh);
  });

  test(
    'same-user rebuild restores selection from feedFilterSelectionProvider',
    () async {
      final notifier = container.read(feedProvider.notifier);
      await container.read(feedProvider.future);

      await notifier.setKeyword('climat');
      expect(notifier.selectedKeyword, 'climat');

      authNotifier.setAuth(authNotifier.state.copyWith(needsOnboarding: true));
      await container.read(feedProvider.future);
      expect(container.read(feedProvider).value!.items, isEmpty);

      authNotifier.setAuth(authNotifier.state.copyWith(needsOnboarding: false));
      await container.read(feedProvider.future);

      expect(container.read(feedProvider.notifier).selectedKeyword, 'climat');
      expect(container.read(feedFilterSelectionProvider).keyword, 'climat');
      expect(container.read(feedProvider).value!.items.single.id, 'climat');
    },
  );

  test('provider recreation keeps same-user filter selection', () async {
    final notifier = container.read(feedProvider.notifier);
    await container.read(feedProvider.future);

    await notifier.setTheme('TECH');
    expect(container.read(feedFilterSelectionProvider).theme, 'TECH');

    container.invalidate(feedProvider);
    await container.read(feedProvider.future);

    expect(container.read(feedProvider.notifier).selectedTheme, 'TECH');
    expect(container.read(feedProvider).value!.items.single.id, 'TECH');
  });

  test('user change resets active filters', () async {
    final notifier = container.read(feedProvider.notifier);
    await container.read(feedProvider.future);

    await notifier.setTheme('TECH');
    expect(container.read(feedFilterSelectionProvider).theme, 'TECH');

    authNotifier.setAuth(app_auth.AuthState(user: makeUser('u2')));
    await container.read(feedProvider.future);
    await container.pump();

    expect(container.read(feedProvider.notifier).selectedTheme, isNull);
    expect(
      container.read(feedFilterSelectionProvider),
      FeedFilterSelection.empty,
    );
  });
}
