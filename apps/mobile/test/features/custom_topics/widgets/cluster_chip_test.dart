import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/custom_topics/widgets/cluster_chip.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/screens/cluster_view_screen.dart';
import 'package:facteur/features/sources/models/source_model.dart';

class MockFeedRepository extends Mock implements FeedRepository {}

Content _makeContent({
  String? clusterTopic,
  int clusterHiddenCount = 0,
  List<String> clusterHiddenIds = const [],
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
    clusterHiddenIds: clusterHiddenIds,
  );
}

void main() {
  late MockFeedRepository mockFeedRepo;

  setUp(() {
    mockFeedRepo = MockFeedRepository();
    when(() => mockFeedRepo.getContent(any()))
        .thenAnswer((_) async => null);
  });

  Widget createWidget(Content content) {
    return ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(mockFeedRepo),
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
        find.text('4 articles récents sur \u2022 Intelligence artificielle'),
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
        find.text('2 autres articles sur \u2022 Climat'),
        findsOneWidget,
      );
    });

    testWidgets('tap opens immersive cluster view', (tester) async {
      await tester.pumpWidget(createWidget(
        _makeContent(
          clusterTopic: 'tech',
          clusterHiddenCount: 3,
          clusterHiddenIds: ['h1', 'h2', 'h3'],
        ),
      ));

      await tester.tap(find.textContaining('3 autres articles'));
      await tester.pumpAndSettle();

      // ClusterViewScreen should be pushed
      expect(find.byType(ClusterViewScreen), findsOneWidget);
      expect(find.text('\u{1F4BB} Technologie'), findsOneWidget);
    });
  });
}
