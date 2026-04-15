import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/widgets/smart_search_field.dart';
import 'package:facteur/config/theme.dart';

void main() {
  Widget buildTestWidget({required ValueChanged<String> onSearch}) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SmartSearchField(onSearch: onSearch),
        ),
      ),
    );
  }

  group('SmartSearchField', () {
    testWidgets('renders with hint text', (tester) async {
      await tester.pumpWidget(buildTestWidget(onSearch: (_) {}));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Rechercher une source...'), findsOneWidget);
    });

    testWidgets('debounces input at 350ms', (tester) async {
      String? lastQuery;
      await tester.pumpWidget(
          buildTestWidget(onSearch: (q) => lastQuery = q));

      await tester.enterText(find.byType(TextField), 'test');

      // Before debounce fires
      await tester.pump(const Duration(milliseconds: 200));
      expect(lastQuery, isNull);

      // After debounce fires
      await tester.pump(const Duration(milliseconds: 200));
      expect(lastQuery, 'test');
    });

    testWidgets('fires immediately on submit', (tester) async {
      String? lastQuery;
      await tester.pumpWidget(
          buildTestWidget(onSearch: (q) => lastQuery = q));

      await tester.enterText(find.byType(TextField), 'lemonde.fr');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(lastQuery, 'lemonde.fr');
    });

    testWidgets('clear button appears when text is entered', (tester) async {
      String? lastQuery;
      await tester.pumpWidget(
          buildTestWidget(onSearch: (q) => lastQuery = q));

      // No clear button initially
      expect(find.byType(IconButton), findsNothing);

      // Enter text
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      // Clear button should appear
      expect(find.byType(IconButton), findsOneWidget);

      // Tap clear
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(lastQuery, '');
      // TextField should be empty
      final textField =
          tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '');
    });

    testWidgets('trims whitespace from query', (tester) async {
      String? lastQuery;
      await tester.pumpWidget(
          buildTestWidget(onSearch: (q) => lastQuery = q));

      await tester.enterText(find.byType(TextField), '  test  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(lastQuery, 'test');
    });
  });
}
