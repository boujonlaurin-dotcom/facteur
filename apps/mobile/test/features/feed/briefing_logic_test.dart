import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/core/api/providers.dart';
import 'package:facteur/features/sources/models/source_model.dart';

import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// Mocks
class MockFeedRepository extends Mock implements FeedRepository {}

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
  Future<void> signInWithEmail(String email, String password,
      {bool rememberMe = true}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmail(String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  void setOnboardingCompleted() {}

  @override
  Future<void> setNeedsOnboarding(bool value) async {}

  @override
  void clearError() {}

  @override
  void clearPendingEmailConfirmation() {}

  @override
  Future<void> refreshUser() async {}

  @override
  Future<void> refreshOnboardingStatus() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockFeedRepository mockRepository;
  late MockAuthStateNotifier mockAuthNotifier;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockFeedRepository();
    mockAuthNotifier = MockAuthStateNotifier();

    container = ProviderContainer(
      overrides: [
        feedRepositoryProvider.overrideWithValue(mockRepository),
        app_auth.authStateProvider.overrideWith((ref) => mockAuthNotifier),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('FeedNotifier marks briefing item as read and calls repository',
      () async {
    // 1. Setup Initial State
    final content = Content(
      id: '1',
      title: 'Test Article',
      url: 'http://test.com',
      publishedAt: DateTime.now(),
      source: Source(
          id: 's1',
          name: 'Source',
          type: SourceType.article,
          url: 's.com',
          theme: 'News'),
      contentType: ContentType.article,
    );

    final briefingItem = DailyTop3Item(
        rank: 1, reason: 'Une', isConsumed: false, content: content);

    final initialState = FeedState(
      items: [],
      briefing: [briefingItem],
    );

    // Initial mock behavior
    when(() => mockRepository.getFeed(page: 1, limit: 20, mode: null))
        .thenAnswer((_) async => FeedResponse(
            items: [],
            briefing: [briefingItem],
            pagination:
                Pagination(page: 1, perPage: 20, total: 1, hasNext: false)));

    when(() => mockRepository.markBriefingAsRead('1')).thenAnswer((_) async {});

    when(() => mockRepository.updateContentStatus('1', ContentStatus.consumed))
        .thenAnswer((_) async {});

    // Initialize notifier
    final notifier = container.read(feedProvider.notifier);
    // Force build
    await container.read(feedProvider.future);

    // 2. Action: Mark as Consumed
    await notifier.markContentAsConsumed(content);

    // 3. Verification
    final state = container.read(feedProvider).value!;

    // Check Briefing Item State
    expect(state.briefing[0].isConsumed, true,
        reason: 'Briefing item should be marked as consumed in state');

    // Check Repository Call
    verify(() => mockRepository.markBriefingAsRead('1')).called(1);
  });
}
