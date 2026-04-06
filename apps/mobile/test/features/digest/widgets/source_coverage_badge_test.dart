import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/widgets/source_coverage_badge.dart';

void main() {
  Widget buildWidget({required int perspectiveCount, bool isTrending = false}) {
    return MaterialApp(
      home: Scaffold(
        body: SourceCoverageBadge(
          perspectiveCount: perspectiveCount,
          isTrending: isTrending,
        ),
      ),
    );
  }

  group('SourceCoverageBadge', () {
    testWidgets('displays perspective count', (tester) async {
      await tester.pumpWidget(buildWidget(perspectiveCount: 12));
      expect(find.text('Couvert par 12 sources'), findsOneWidget);
    });

    testWidgets('shows trending icon when isTrending is true', (tester) async {
      await tester.pumpWidget(buildWidget(perspectiveCount: 5, isTrending: true));
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });

    testWidgets('hides trending icon when isTrending is false', (tester) async {
      await tester.pumpWidget(buildWidget(perspectiveCount: 5));
      expect(find.byIcon(Icons.trending_up), findsNothing);
    });

    testWidgets('hidden when count is zero', (tester) async {
      await tester.pumpWidget(buildWidget(perspectiveCount: 0));
      expect(find.text('Couvert par 0 sources'), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('displays singular when count is 1', (tester) async {
      await tester.pumpWidget(buildWidget(perspectiveCount: 1));
      expect(find.text('Couvert par 1 source'), findsOneWidget);
    });
  });
}
