import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/widgets/smart_search_field.dart';
import 'package:facteur/config/theme.dart';

void main() {
  Widget buildTestWidget({
    required TextEditingController controller,
    required ValueChanged<String> onSubmit,
    required VoidCallback onClear,
    VoidCallback? onSearch,
  }) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SmartSearchField(
            controller: controller,
            onSubmit: onSubmit,
            onClear: onClear,
            onSearch: onSearch,
          ),
        ),
      ),
    );
  }

  group('SmartSearchField', () {
    testWidgets('renders with hint text', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        onSubmit: (_) {},
        onClear: () {},
      ));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Rechercher une source...'), findsOneWidget);
    });

    testWidgets('does NOT fire onSubmit while typing (no debounce)',
        (tester) async {
      String? lastQuery;
      final controller = TextEditingController();
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        onSubmit: (q) => lastQuery = q,
        onClear: () {},
      ));

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump(const Duration(milliseconds: 500));

      expect(lastQuery, isNull,
          reason: 'Search must only fire on explicit submit, not on typing.');
    });

    testWidgets('fires onSubmit on keyboard submit (trimmed)', (tester) async {
      String? lastQuery;
      final controller = TextEditingController();
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        onSubmit: (q) => lastQuery = q,
        onClear: () {},
      ));

      await tester.enterText(find.byType(TextField), '  lemonde.fr  ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(lastQuery, 'lemonde.fr');
    });

    testWidgets('clear button appears when text is entered and triggers onClear',
        (tester) async {
      var clearCalled = false;
      final controller = TextEditingController();
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        onSubmit: (_) {},
        onClear: () => clearCalled = true,
      ));

      // No clear button initially.
      expect(find.byType(IconButton), findsNothing);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(find.byType(IconButton), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(clearCalled, isTrue);
    });
  });
}
