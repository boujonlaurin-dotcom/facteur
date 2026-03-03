import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/custom_topics/widgets/cluster_chip.dart';
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

Content _makeContent({
  String? clusterTopic,
  int clusterHiddenCount = 0,
  List<Content> clusterHiddenArticles = const [],
}) {
  return Content(
    id: 'c1',
    title: 'Test Article',
    url: 'https://example.com',
    contentType: ContentType.article,
    publishedAt: DateTime(2024, 1, 1),
    source: Source.fallback(),
    clusterTopic: clusterTopic,
    clusterHiddenCount: clusterHiddenCount,
    clusterHiddenArticles: clusterHiddenArticles,
  );
}

void main() {
  late MockTopicRepository mockRepo;
  late MockAuthStateNotifier mockAuth;

  setUp(() {
    mockRepo = MockTopicRepository();
    mockAuth = MockAuthStateNotifier();
  });

  Widget createWidget(Content content) {
    when(() => mockRepo.getTopics()).thenAnswer((_) async => []);

    return ProviderScope(
      overrides: [
        topicRepositoryProvider.overrideWithValue(mockRepo),
        app_auth.authStateProvider.overrideWith((ref) => mockAuth),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: ClusterChip(content: content)),
        ),
      ),
    );
  }

  group('ClusterChip', () {
    testWidgets('renders nothing when clusterHiddenCount is 0',
        (tester) async {
      await tester.pumpWidget(createWidget(_makeContent()));

      expect(find.byType(ClusterChip), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('renders nothing when clusterTopic is null',
        (tester) async {
      await tester.pumpWidget(createWidget(
        _makeContent(clusterHiddenCount: 3),
      ));

      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('displays correct count text with topic name',
        (tester) async {
      await tester.pumpWidget(createWidget(
        _makeContent(
          clusterTopic: 'ai',
          clusterHiddenCount: 4,
        ),
      ));

      expect(
        find.text('4 autres articles sur Intelligence artificielle'),
        findsOneWidget,
      );
    });

    testWidgets('displays count text for different topics',
        (tester) async {
      await tester.pumpWidget(createWidget(
        _makeContent(
          clusterTopic: 'climate',
          clusterHiddenCount: 2,
        ),
      ));

      expect(
        find.text('2 autres articles sur Climat'),
        findsOneWidget,
      );
    });

    testWidgets('tap opens topic explorer modal sheet', (tester) async {
      await tester.pumpWidget(createWidget(
        _makeContent(
          clusterTopic: 'tech',
          clusterHiddenCount: 3,
        ),
      ));

      await tester.tap(find.textContaining('3 autres articles'));
      await tester.pumpAndSettle();

      // Modal sheet should open with topic name and follow button
      expect(find.text('Technologie'), findsWidgets);
      expect(find.text('Suivre ce sujet'), findsOneWidget);
    });

    testWidgets('passes hidden articles to TopicExplorerSheet',
        (tester) async {
      final hiddenArticles = [
        Content(
          id: 'h1',
          title: 'Hidden 1',
          url: 'https://example.com/h1',
          contentType: ContentType.article,
          publishedAt: DateTime(2024, 1, 1),
          source: Source.fallback(),
        ),
        Content(
          id: 'h2',
          title: 'Hidden 2',
          url: 'https://example.com/h2',
          contentType: ContentType.article,
          publishedAt: DateTime(2024, 1, 1),
          source: Source.fallback(),
        ),
      ];

      await tester.pumpWidget(createWidget(
        _makeContent(
          clusterTopic: 'ai',
          clusterHiddenCount: 2,
          clusterHiddenArticles: hiddenArticles,
        ),
      ));

      await tester.tap(find.textContaining('2 autres articles'));
      await tester.pumpAndSettle();

      // Modal sheet should show article count
      expect(find.text('2 articles recents'), findsOneWidget);
    });
  });
}
