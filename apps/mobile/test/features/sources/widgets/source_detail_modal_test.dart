import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/features/sources/widgets/source_detail_modal.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/config/theme.dart';

void main() {
  testWidgets('SourceDetailModal displays rational and hides top description',
      (WidgetTester tester) async {
    final source = Source(
      id: 'test-id',
      name: 'Test Source',
      type: SourceType.article,
      description: 'This is the rational for the source evaluation.',
      isTrusted: false,
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SourceDetailModal(
            source: source,
            onToggleTrust: () {},
          ),
        ),
      )),
    );

    // Verify that the rational is displayed
    expect(find.text('This is the rational for the source evaluation.'),
        findsOneWidget);

    // Verify that it's NOT displayed as a separate description block at the top
    // (In the implementation, we removed the block that used Theme.of(context).textTheme.bodyMedium)
    // We can check if there's only one occurrence of the text.
    expect(find.text('This is the rational for the source evaluation.'),
        findsOneWidget);
  });

  testWidgets('renders Derniers articles when recentItems provided',
      (tester) async {
    final source = Source(
      id: 'test-id',
      name: 'Test Source',
      type: SourceType.article,
    );
    const recent = [
      SmartSearchRecentItem(title: 'Article récent A'),
      SmartSearchRecentItem(title: 'Article récent B'),
      SmartSearchRecentItem(title: 'Article récent C'),
    ];

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourceDetailModal(
              source: source,
              onToggleTrust: () {},
              recentItems: recent,
            ),
          ),
        ),
      )),
    );

    expect(find.text('Derniers articles'), findsOneWidget);
    expect(find.text('Article récent A'), findsOneWidget);
    expect(find.text('Article récent B'), findsOneWidget);
    expect(find.text('Article récent C'), findsOneWidget);
  });

  testWidgets('hides Derniers articles when recentItems is null/empty',
      (tester) async {
    final source = Source(
      id: 'test-id',
      name: 'Test Source',
      type: SourceType.article,
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourceDetailModal(
              source: source,
              onToggleTrust: () {},
            ),
          ),
        ),
      )),
    );

    expect(find.text('Derniers articles'), findsNothing);
  });

  testWidgets('shows priority slider with inline help text when trusted',
      (tester) async {
    final source = Source(
      id: 'test-id',
      name: 'Test Source',
      type: SourceType.article,
      isTrusted: true,
      priorityMultiplier: 2.0,
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourceDetailModal(
              source: source,
              onToggleTrust: () {},
              onPriorityChanged: (_) {},
            ),
          ),
        ),
      )),
    );

    expect(find.text('Fréquence'), findsOneWidget);
    expect(
        find.text('Ajustez à quel point vous souhaitez voir cette source'),
        findsOneWidget);
  });
}
