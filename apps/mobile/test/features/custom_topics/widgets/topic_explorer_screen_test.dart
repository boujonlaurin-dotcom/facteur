import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/custom_topics/screens/topic_explorer_screen.dart';
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

Content _makeArticle(String id, String title) {
  return Content(
    id: id,
    title: title,
    url: 'https://example.com/$id',
    contentType: ContentType.article,
    publishedAt: DateTime(2024, 1, 1),
    source: Source.fallback(),
    topics: ['ai'],
  );
}

void main() {
  late MockTopicRepository mockRepo;
  late MockAuthStateNotifier mockAuth;

  setUp(() {
    mockRepo = MockTopicRepository();
    mockAuth = MockAuthStateNotifier();
  });

  Widget createWidget({
    String topicSlug = 'ai',
    String? topicName = 'Intelligence artificielle',
    List<Content>? initialArticles,
    List<UserTopicProfile>? followedTopics,
  }) {
    when(() => mockRepo.getTopics())
        .thenAnswer((_) async => followedTopics ?? []);

    return ProviderScope(
      overrides: [
        topicRepositoryProvider.overrideWithValue(mockRepo),
        app_auth.authStateProvider.overrideWith((ref) => mockAuth),
      ],
      child: MaterialApp(
        home: TopicExplorerScreen(
          topicSlug: topicSlug,
          topicName: topicName,
          initialArticles: initialArticles,
        ),
      ),
    );
  }

  group('TopicExplorerScreen', () {
    testWidgets('shows topic name in app bar', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Intelligence artificielle'), findsOneWidget);
    });

    testWidgets('shows parent theme label in app bar subtitle',
        (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Tech & Science'), findsOneWidget);
    });

    testWidgets('shows "Suivre ce sujet" button when not followed',
        (tester) async {
      await tester.pumpWidget(createWidget(followedTopics: []));
      await tester.pumpAndSettle();

      expect(find.text('Suivre ce sujet'), findsOneWidget);
      expect(
        find.textContaining('Recevez plus d\'articles'),
        findsOneWidget,
      );
    });

    testWidgets('shows "Suivi" + slider when topic is followed',
        (tester) async {
      await tester.pumpWidget(createWidget(
        followedTopics: [
          const UserTopicProfile(
            id: 't1',
            name: 'Intelligence artificielle',
            slugParent: 'ai',
            priorityMultiplier: 1.0,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Suivi'), findsOneWidget);
      expect(find.text('Priorité :'), findsOneWidget);
    });

    testWidgets('follow button calls followTopic on provider',
        (tester) async {
      when(() => mockRepo.followTopic(any())).thenAnswer(
        (_) async => const UserTopicProfile(
          id: 't1',
          name: 'Intelligence artificielle',
          slugParent: 'ai',
        ),
      );

      await tester.pumpWidget(createWidget(followedTopics: []));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suivre ce sujet'));
      await tester.pump();

      verify(() => mockRepo.followTopic('Intelligence artificielle')).called(1);
    });

    testWidgets('shows article list when initialArticles provided',
        (tester) async {
      final articles = [
        _makeArticle('a1', 'Article IA 1'),
        _makeArticle('a2', 'Article IA 2'),
        _makeArticle('a3', 'Article IA 3'),
      ];

      await tester.pumpWidget(createWidget(initialArticles: articles));
      await tester.pumpAndSettle();

      expect(find.text('3 articles recents'), findsOneWidget);
      expect(find.text('Article IA 1'), findsOneWidget);
      expect(find.text('Article IA 2'), findsOneWidget);
    });

    testWidgets('shows empty state when no articles', (tester) async {
      await tester.pumpWidget(createWidget(initialArticles: []));
      await tester.pumpAndSettle();

      expect(find.text('Aucun article disponible'), findsOneWidget);
      expect(
        find.textContaining('apparaîtront ici'),
        findsOneWidget,
      );
    });

    testWidgets('uses getTopicLabel fallback when topicName is null',
        (tester) async {
      await tester.pumpWidget(createWidget(
        topicSlug: 'climate',
        topicName: null,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Climat'), findsOneWidget);
    });

    testWidgets('article count shows singular form for 1 article',
        (tester) async {
      final articles = [_makeArticle('a1', 'Seul Article')];

      await tester.pumpWidget(createWidget(initialArticles: articles));
      await tester.pumpAndSettle();

      expect(find.text('1 article recent'), findsOneWidget);
    });
  });
}
