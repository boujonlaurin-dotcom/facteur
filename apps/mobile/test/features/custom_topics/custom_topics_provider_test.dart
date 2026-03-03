import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/custom_topics/providers/custom_topics_provider.dart';
import 'package:facteur/features/custom_topics/repositories/topic_repository.dart';
import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// Mocks
class MockTopicRepository extends Mock implements TopicRepository {}

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

class _UnauthNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  _UnauthNotifier() : super(const app_auth.AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockTopicRepository mockRepo;
  late MockAuthStateNotifier mockAuthNotifier;
  late ProviderContainer container;

  final mockTopics = [
    const UserTopicProfile(
        id: 't1', name: 'IA', priorityMultiplier: 1.0),
    const UserTopicProfile(
        id: 't2', name: 'Climate', priorityMultiplier: 1.5, slugParent: 'env'),
  ];

  setUp(() {
    mockRepo = MockTopicRepository();
    mockAuthNotifier = MockAuthStateNotifier();

    container = ProviderContainer(
      overrides: [
        topicRepositoryProvider.overrideWithValue(mockRepo),
        app_auth.authStateProvider.overrideWith((ref) => mockAuthNotifier),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('build / initial load', () {
    test('loads topics on initialization', () async {
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);

      final topics = await container.read(customTopicsProvider.future);

      expect(topics.length, 2);
      expect(topics[0].name, 'IA');
      expect(topics[1].name, 'Climate');
      verify(() => mockRepo.getTopics()).called(1);
    });

    test('returns empty list when not authenticated', () async {
      final unauthContainer = ProviderContainer(
        overrides: [
          topicRepositoryProvider.overrideWithValue(mockRepo),
          app_auth.authStateProvider.overrideWith((ref) => _UnauthNotifier()),
        ],
      );

      final topics = await unauthContainer.read(customTopicsProvider.future);
      expect(topics, isEmpty);
      verifyNever(() => mockRepo.getTopics());

      unauthContainer.dispose();
    });

    test('returns empty list on API error during build', () async {
      when(() => mockRepo.getTopics()).thenThrow(Exception('Network error'));

      expect(
        () => container.read(customTopicsProvider.future),
        throwsException,
      );
    });
  });

  group('followTopic', () {
    test('adds placeholder optimistically then replaces with server response',
        () async {
      when(() => mockRepo.getTopics())
          .thenAnswer((_) async => [mockTopics[0]]);
      when(() => mockRepo.followTopic('Climate')).thenAnswer((_) async =>
          const UserTopicProfile(
              id: 'new-uuid',
              name: 'Climate',
              slugParent: 'env',
              keywords: ['rechauffement', 'carbone']));

      // Wait for initial load
      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      // Initial state: 1 topic
      expect(container.read(customTopicsProvider).value!.length, 1);

      final result = await notifier.followTopic('Climate');

      // After completion: 2 topics, placeholder replaced with server data
      final topics = container.read(customTopicsProvider).value!;
      expect(topics.length, 2);
      expect(result!.id, 'new-uuid');
      expect(result.slugParent, 'env');
      expect(result.keywords, ['rechauffement', 'carbone']);
      // No temp IDs remaining
      expect(topics.any((t) => t.id.startsWith('temp_')), isFalse);
    });

    test('rolls back on API error', () async {
      when(() => mockRepo.getTopics())
          .thenAnswer((_) async => [mockTopics[0]]);
      when(() => mockRepo.followTopic(any()))
          .thenThrow(Exception('API error'));

      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      // Initial: 1 topic
      expect(container.read(customTopicsProvider).value!.length, 1);

      await expectLater(
        () => notifier.followTopic('Bad Topic'),
        throwsException,
      );

      // Rollback: should be back to 1 topic
      expect(container.read(customTopicsProvider).value!.length, 1);
      expect(container.read(customTopicsProvider).value![0].id, 't1');
    });
  });

  group('unfollowTopic', () {
    test('removes topic optimistically and calls API', () async {
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);
      when(() => mockRepo.unfollowTopic('t1')).thenAnswer((_) async {});

      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      expect(container.read(customTopicsProvider).value!.length, 2);

      await notifier.unfollowTopic('t1');

      // Optimistic: immediately removed
      final topics = container.read(customTopicsProvider).value!;
      expect(topics.length, 1);
      expect(topics[0].id, 't2');
      verify(() => mockRepo.unfollowTopic('t1')).called(1);
    });

    test('rolls back on API error', () async {
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);
      when(() => mockRepo.unfollowTopic(any()))
          .thenThrow(Exception('Network error'));

      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      await expectLater(
        () => notifier.unfollowTopic('t1'),
        throwsException,
      );

      // Rollback: should still have 2 topics
      expect(container.read(customTopicsProvider).value!.length, 2);
    });
  });

  group('updatePriority', () {
    test('updates priority optimistically then syncs server response',
        () async {
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);
      when(() => mockRepo.updateTopicPriority('t1', 2.0)).thenAnswer(
          (_) async => const UserTopicProfile(
              id: 't1',
              name: 'IA',
              priorityMultiplier: 2.0,
              compositeScore: 10));

      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      await notifier.updatePriority('t1', 2.0);

      // After server sync: priority updated and composite_score synced
      final topics = container.read(customTopicsProvider).value!;
      final updated = topics.firstWhere((t) => t.id == 't1');
      expect(updated.priorityMultiplier, 2.0);
      expect(updated.compositeScore, 10);
    });

    test('rolls back on API error', () async {
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);
      when(() => mockRepo.updateTopicPriority(any(), any()))
          .thenThrow(Exception('Server error'));

      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      await expectLater(
        () => notifier.updatePriority('t1', 3.0),
        throwsException,
      );

      // Rollback: original priority restored
      final topics = container.read(customTopicsProvider).value!;
      final rolled = topics.firstWhere((t) => t.id == 't1');
      expect(rolled.priorityMultiplier, 1.0);
    });

    test('does not affect other topics when updating one', () async {
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);
      when(() => mockRepo.updateTopicPriority('t1', 0.5)).thenAnswer(
          (_) async => const UserTopicProfile(
              id: 't1', name: 'IA', priorityMultiplier: 0.5));

      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      await notifier.updatePriority('t1', 0.5);

      final topics = container.read(customTopicsProvider).value!;
      // t2 should be unchanged
      final t2 = topics.firstWhere((t) => t.id == 't2');
      expect(t2.priorityMultiplier, 1.5);
      expect(t2.name, 'Climate');
    });
  });

  group('isFollowed', () {
    test('returns true for existing topic (case-insensitive)', () async {
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);

      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      expect(notifier.isFollowed('ia'), isTrue);
      expect(notifier.isFollowed('IA'), isTrue);
      expect(notifier.isFollowed('Ia'), isTrue);
      expect(notifier.isFollowed('climate'), isTrue);
    });

    test('returns false for non-existing topic', () async {
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);

      await container.read(customTopicsProvider.future);
      final notifier = container.read(customTopicsProvider.notifier);

      expect(notifier.isFollowed('Unknown'), isFalse);
      expect(notifier.isFollowed(''), isFalse);
    });

    test('returns false when state has no value', () async {
      // Don't load topics - state will be loading
      when(() => mockRepo.getTopics())
          .thenAnswer((_) => Future.delayed(const Duration(seconds: 10), () => []));

      final notifier = container.read(customTopicsProvider.notifier);

      expect(notifier.isFollowed('IA'), isFalse);
    });
  });

  group('refresh', () {
    test('re-fetches topics from server', () async {
      when(() => mockRepo.getTopics())
          .thenAnswer((_) async => [mockTopics[0]]);

      await container.read(customTopicsProvider.future);
      expect(container.read(customTopicsProvider).value!.length, 1);

      // Server now returns 2 topics
      when(() => mockRepo.getTopics()).thenAnswer((_) async => mockTopics);

      final notifier = container.read(customTopicsProvider.notifier);
      await notifier.refresh();

      expect(container.read(customTopicsProvider).value!.length, 2);
      verify(() => mockRepo.getTopics()).called(2);
    });
  });
}
