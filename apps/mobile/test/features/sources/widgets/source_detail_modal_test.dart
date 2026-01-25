import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/widgets/source_detail_modal.dart';
import 'package:facteur/features/sources/models/source_model.dart';
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
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SourceDetailModal(
            source: source,
            onToggleTrust: () {},
          ),
        ),
      ),
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
}
