import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/widgets/source_result_card.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/config/theme.dart';

void main() {
  final sampleResult = SmartSearchResult(
    name: 'Le Monde',
    type: 'article',
    url: 'https://lemonde.fr',
    feedUrl: 'https://lemonde.fr/rss/une.xml',
    description: 'Journal quotidien francais',
    inCatalog: true,
    sourceId: 'test-source-id',
    recentItems: const [
      SmartSearchRecentItem(title: 'Premier article'),
      SmartSearchRecentItem(title: 'Deuxieme article'),
      SmartSearchRecentItem(title: 'Troisieme article'),
    ],
    score: 0.9,
  );

  Widget buildTestWidget({
    SmartSearchResult? result,
    VoidCallback? onAdd,
    VoidCallback? onPreview,
    bool isAdded = false,
  }) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SourceResultCard(
            result: result ?? sampleResult,
            onAdd: onAdd ?? () {},
            onPreview: onPreview ?? () {},
            isAdded: isAdded,
          ),
        ),
      ),
    );
  }

  group('SourceResultCard', () {
    testWidgets('displays source name and description', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Le Monde'), findsOneWidget);
      expect(find.text('Journal quotidien francais'), findsOneWidget);
    });

    testWidgets('displays recent items', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Derniers articles :'), findsOneWidget);
      expect(find.text('Premier article'), findsOneWidget);
      expect(find.text('Deuxieme article'), findsOneWidget);
      expect(find.text('Troisieme article'), findsOneWidget);
    });

    testWidgets('displays type label', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Article'), findsOneWidget);
    });

    testWidgets('shows Ajouter button when not added', (tester) async {
      await tester.pumpWidget(buildTestWidget(isAdded: false));

      expect(find.text('Ajouter'), findsOneWidget);
      expect(find.text('Ajoutee'), findsNothing);
    });

    testWidgets('shows Ajoutee state when added', (tester) async {
      await tester.pumpWidget(buildTestWidget(isAdded: true));

      expect(find.text('Ajoutee'), findsOneWidget);
      expect(find.text('Ajouter'), findsNothing);
    });

    testWidgets('calls onAdd when Ajouter tapped', (tester) async {
      var addCalled = false;
      await tester.pumpWidget(
          buildTestWidget(onAdd: () => addCalled = true));

      await tester.tap(find.text('Ajouter'));
      expect(addCalled, true);
    });

    testWidgets('calls onPreview when Apercu tapped', (tester) async {
      var previewCalled = false;
      await tester.pumpWidget(
          buildTestWidget(onPreview: () => previewCalled = true));

      await tester.tap(find.text('Apercu'));
      expect(previewCalled, true);
    });

    testWidgets('handles YouTube type correctly', (tester) async {
      final ytResult = SmartSearchResult(
        name: 'HugoDecrypte',
        type: 'youtube',
        url: 'https://youtube.com/@HugoDecrypte',
        feedUrl: 'https://youtube.com/feeds/videos.xml?channel_id=123',
      );

      await tester.pumpWidget(buildTestWidget(result: ytResult));

      expect(find.text('HugoDecrypte'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
    });

    testWidgets('handles result with no recent items', (tester) async {
      final noItemsResult = SmartSearchResult(
        name: 'Empty Source',
        type: 'rss',
        url: 'https://empty.com',
        feedUrl: 'https://empty.com/feed',
      );

      await tester.pumpWidget(buildTestWidget(result: noItemsResult));

      expect(find.text('Empty Source'), findsOneWidget);
      expect(find.text('Derniers articles :'), findsNothing);
    });
  });
}
