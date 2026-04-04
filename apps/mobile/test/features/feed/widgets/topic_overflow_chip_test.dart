import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/feed/widgets/topic_overflow_chip.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/sources/models/source_model.dart';

class MockFeedRepository extends Mock implements FeedRepository {}

Content _makeContent({
  int topicOverflowCount = 0,
  String? topicOverflowLabel,
  String? topicOverflowKey,
  String? topicOverflowType,
  List<String> topicOverflowHiddenIds = const [],
}) {
  return Content(
    id: 'c1',
    title: 'Test Article',
    url: 'https://example.com',
    contentType: ContentType.article,
    publishedAt: DateTime(2024, 1, 1),
    source: Source(
      id: 's1',
      name: 'Test Source',
      url: 'https://example.com',
      type: SourceType.article,
      theme: 'tech',
    ),
    topicOverflowCount: topicOverflowCount,
    topicOverflowLabel: topicOverflowLabel,
    topicOverflowKey: topicOverflowKey,
    topicOverflowType: topicOverflowType,
    topicOverflowHiddenIds: topicOverflowHiddenIds,
  );
}

void main() {
  late MockFeedRepository mockFeedRepo;

  setUp(() {
    mockFeedRepo = MockFeedRepository();
    when(() => mockFeedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          mode: any(named: 'mode'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          savedOnly: any(named: 'savedOnly'),
          hasNote: any(named: 'hasNote'),
          sourceId: any(named: 'sourceId'),
          entity: any(named: 'entity'),
          serein: any(named: 'serein'),
          contentType: any(named: 'contentType'),
        )).thenAnswer((_) async => FeedResponse(
          items: [],
          pagination:
              Pagination(page: 1, perPage: 20, total: 0, hasNext: false),
        ));
  });

  Widget createWidget(Content content) {
    return ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(mockFeedRepo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: TopicOverflowChip(content: content)),
        ),
      ),
    );
  }

  group('TopicOverflowChip', () {
    testWidgets('renders nothing when topicOverflowCount is 0',
        (tester) async {
      await tester.pumpWidget(createWidget(_makeContent()));

      expect(find.byType(TopicOverflowChip), findsOneWidget);
      // Should render SizedBox.shrink, no GestureDetector
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('displays correct count and label for theme group',
        (tester) async {
      await tester.pumpWidget(createWidget(_makeContent(
        topicOverflowCount: 6,
        topicOverflowLabel: 'Culture & Idées',
        topicOverflowKey: 'culture',
        topicOverflowType: 'theme',
      )));

      expect(
        find.text('6 autres articles Culture & Idées'),
        findsOneWidget,
      );
    });

    testWidgets('displays correct count and label for topic group',
        (tester) async {
      await tester.pumpWidget(createWidget(_makeContent(
        topicOverflowCount: 4,
        topicOverflowLabel: 'Justice',
        topicOverflowKey: 'justice',
        topicOverflowType: 'topic',
      )));

      expect(
        find.text('4 autres articles Justice'),
        findsOneWidget,
      );
    });

    testWidgets('displays various labels correctly', (tester) async {
      await tester.pumpWidget(createWidget(_makeContent(
        topicOverflowCount: 3,
        topicOverflowLabel: 'Économie',
        topicOverflowKey: 'economy',
        topicOverflowType: 'theme',
      )));

      expect(
        find.text('3 autres articles Économie'),
        findsOneWidget,
      );
    });

    testWidgets('has GestureDetector when count > 0', (tester) async {
      await tester.pumpWidget(createWidget(_makeContent(
        topicOverflowCount: 2,
        topicOverflowLabel: 'Tech & Innovation',
        topicOverflowKey: 'tech',
        topicOverflowType: 'theme',
      )));

      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('tap on theme chip triggers setTheme', (tester) async {
      await tester.pumpWidget(createWidget(_makeContent(
        topicOverflowCount: 5,
        topicOverflowLabel: 'Économie',
        topicOverflowKey: 'economy',
        topicOverflowType: 'theme',
        topicOverflowHiddenIds: ['h1', 'h2', 'h3', 'h4', 'h5'],
      )));

      // Tap the chip — this triggers feedProvider.notifier.setTheme('economy')
      // which calls getFeed with theme filter. The mock will be called.
      await tester.tap(find.textContaining('5 autres articles'));
      await tester.pump();

      // Verify the feed was refreshed with theme filter
      verify(() => mockFeedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            theme: 'economy',
            mode: any(named: 'mode'),
            topic: any(named: 'topic'),
            savedOnly: any(named: 'savedOnly'),
            hasNote: any(named: 'hasNote'),
            sourceId: any(named: 'sourceId'),
            entity: any(named: 'entity'),
            serein: any(named: 'serein'),
            contentType: any(named: 'contentType'),
          )).called(1);
    });

    testWidgets('tap on topic chip triggers setTopic', (tester) async {
      await tester.pumpWidget(createWidget(_makeContent(
        topicOverflowCount: 3,
        topicOverflowLabel: 'Justice',
        topicOverflowKey: 'justice',
        topicOverflowType: 'topic',
        topicOverflowHiddenIds: ['h1', 'h2', 'h3'],
      )));

      await tester.tap(find.textContaining('3 autres articles'));
      await tester.pump();

      // Verify the feed was refreshed with topic filter
      verify(() => mockFeedRepo.getFeed(
            page: 1,
            limit: any(named: 'limit'),
            topic: 'justice',
            theme: any(named: 'theme'),
            mode: any(named: 'mode'),
            savedOnly: any(named: 'savedOnly'),
            hasNote: any(named: 'hasNote'),
            sourceId: any(named: 'sourceId'),
            entity: any(named: 'entity'),
            serein: any(named: 'serein'),
            contentType: any(named: 'contentType'),
          )).called(1);
    });
  });
}
