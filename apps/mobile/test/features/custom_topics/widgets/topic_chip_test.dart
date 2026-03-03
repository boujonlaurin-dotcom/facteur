import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:facteur/features/custom_topics/widgets/topic_chip.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/custom_topics/providers/custom_topics_provider.dart';
import 'package:facteur/features/custom_topics/repositories/topic_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

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

Content _makeContent({List<String> topics = const []}) {
  return Content(
    id: 'c1',
    title: 'Test Article',
    url: 'https://example.com',
    contentType: ContentType.article,
    publishedAt: DateTime(2024, 1, 1),
    source: Source.fallback(),
    topics: topics,
  );
}

void main() {
  late MockTopicRepository mockRepo;
  late MockAuthStateNotifier mockAuth;

  setUp(() {
    mockRepo = MockTopicRepository();
    mockAuth = MockAuthStateNotifier();
  });

  Widget createWidget(Content content, {List<UserTopicProfile>? topics}) {
    when(() => mockRepo.getTopics()).thenAnswer((_) async => topics ?? []);

    return ProviderScope(
      overrides: [
        topicRepositoryProvider.overrideWithValue(mockRepo),
        app_auth.authStateProvider.overrideWith((ref) => mockAuth),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: TopicChip(content: content)),
        ),
      ),
    );
  }

  group('TopicChip', () {
    testWidgets('renders SizedBox.shrink when content has no topics',
        (tester) async {
      await tester.pumpWidget(createWidget(_makeContent()));
      await tester.pumpAndSettle();

      expect(find.byType(TopicChip), findsOneWidget);
      // Should render SizedBox.shrink, meaning no visible chip
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('shows "+" icon when topic is not followed', (tester) async {
      await tester.pumpWidget(createWidget(
        _makeContent(topics: ['tech']),
      ));
      await tester.pumpAndSettle();

      // Unfollowed state: shows a "+" icon
      expect(find.byIcon(PhosphorIcons.plus(PhosphorIconsStyle.bold)),
          findsOneWidget);
    });

    testWidgets('shows check icon when topic is followed by slugParent',
        (tester) async {
      await tester.pumpWidget(createWidget(
        _makeContent(topics: ['tech']),
        topics: [
          const UserTopicProfile(
            id: 't1',
            name: 'Technologie',
            slugParent: 'tech',
          ),
        ],
      ));
      await tester.pumpAndSettle();

      // Followed state: shows a check icon
      expect(find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)),
          findsOneWidget);
    });

    testWidgets('tapping "+" follows the topic', (tester) async {
      when(() => mockRepo.followTopic(any()))
          .thenAnswer((_) async => const UserTopicProfile(
                id: 'new1',
                name: 'Technologie',
                slugParent: 'tech',
              ));

      await tester.pumpWidget(createWidget(
        _makeContent(topics: ['tech']),
      ));
      await tester.pumpAndSettle();

      // Tap the "+" icon
      await tester.tap(find.byIcon(PhosphorIcons.plus(PhosphorIconsStyle.bold)));
      await tester.pumpAndSettle();

      // Should show a snackbar
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('tapping check icon opens modal sheet', (tester) async {
      await tester.pumpWidget(createWidget(
        _makeContent(topics: ['tech']),
        topics: [
          const UserTopicProfile(
            id: 't1',
            name: 'Technologie',
            slugParent: 'tech',
          ),
        ],
      ));
      await tester.pumpAndSettle();

      // Tap the check icon
      await tester.tap(find.byIcon(PhosphorIcons.check(PhosphorIconsStyle.bold)));
      await tester.pumpAndSettle();

      // Modal sheet should open with topic name
      expect(find.text('Technologie'), findsWidgets);
    });
  });
}
