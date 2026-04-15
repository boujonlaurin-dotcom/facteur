import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/widgets/example_chips.dart';
import 'package:facteur/config/theme.dart';

void main() {
  group('ExampleChips', () {
    testWidgets('renders all 4 example chips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: ExampleChips(onTap: (_) {}),
          ),
        ),
      );

      expect(find.text("Lenny's newsletter"), findsOneWidget);
      expect(find.text('r/france'), findsOneWidget);
      expect(find.text('@fireship'), findsOneWidget);
      expect(find.text('Stratechery'), findsOneWidget);
    });

    testWidgets('fires callback with correct text on tap', (tester) async {
      String? tappedText;

      await tester.pumpWidget(
        MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: ExampleChips(onTap: (text) => tappedText = text),
          ),
        ),
      );

      await tester.tap(find.text('r/france'));
      expect(tappedText, 'r/france');

      await tester.tap(find.text('@fireship'));
      expect(tappedText, '@fireship');
    });

    testWidgets('displays "Essaie :" label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: ExampleChips(onTap: (_) {}),
          ),
        ),
      );

      expect(find.text('Essaie :'), findsOneWidget);
    });
  });
}
