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

// Mocks
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

  final mockContent = Content(
    id: 'c1',
    title: 'Title',
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

  test('muteSource should filter items optimistically', () async {
    // 1. Setup Feed with one item
    final briefing = <DailyTop3Item>[];
    final items = [mockContent];

    when(() => mockFeedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            mode: any(named: 'mode')))
        .thenAnswer((_) async => FeedResponse(
            items: items,
            briefing: briefing,
            pagination:
                Pagination(page: 1, perPage: 20, total: 1, hasNext: false)));

    when(() => mockPersoRepo.muteSource(any())).thenAnswer((_) async {});

    final notifier = container.read(feedProvider.notifier);
    await container.read(feedProvider.future); // Wait initial load

    // Verify initial state has 1 item
    expect(container.read(feedProvider).value!.items.length, 1);

    // 2. Action: Mute Source
    final muteFuture = notifier.muteSource(mockContent);

    // 3. Verification: Optimistic update should have removed the item IMMEDIATELY
    expect(container.read(feedProvider).value!.items.length, 0,
        reason: 'Item should be removed from state BEFORE API call completes');

    await muteFuture; // Complete the API call
    verify(() => mockPersoRepo.muteSource('s1')).called(1);
  });

  test('muteSourceById should work even if content is not in current state',
      () async {
    // 1. Setup Feed with one item
    final items = [mockContent];

    when(() => mockFeedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            mode: any(named: 'mode')))
        .thenAnswer((_) async => FeedResponse(
            items: items,
            briefing: [],
            pagination:
                Pagination(page: 1, perPage: 20, total: 1, hasNext: false)));

    when(() => mockPersoRepo.muteSource(any())).thenAnswer((_) async {});

    final notifier = container.read(feedProvider.notifier);
    await container.read(feedProvider.future);

    // 2. Action: Mute Source by ID (simulate calling from Nudge where content might be just an ID)
    await notifier.muteSourceById('s1');

    // 3. Verification
    expect(container.read(feedProvider).value!.items.length, 0);
    verify(() => mockPersoRepo.muteSource('s1')).called(1);
  });
}
