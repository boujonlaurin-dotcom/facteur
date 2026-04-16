import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/widgets/example_chips.dart';
import 'package:facteur/config/theme.dart';

void main() {
  Widget pumpChips(VoidCallback callback,
      {void Function(String)? onTap}) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: ExampleChips(onTap: onTap ?? (_) {}),
      ),
    );
  }

  group('ExampleChips', () {
    testWidgets('renders the curated FR examples', (tester) async {
      await tester.pumpWidget(pumpChips(() {}));

      // A few representative labels covering the 4 source types.
      expect(find.text('@HugoDécrypte'), findsOneWidget);
      expect(find.text('@Underscore_'), findsOneWidget);
      expect(find.text('Snowball'), findsOneWidget);
      expect(find.text('Sismique'), findsOneWidget);
      expect(find.text('GDIY'), findsOneWidget);
      expect(find.text('r/france'), findsOneWidget);
      expect(find.text('Numerama'), findsOneWidget);
      expect(find.text('Le Grand Continent'), findsOneWidget);
    });

    testWidgets('fires callback with correct text on tap', (tester) async {
      String? tappedText;

      await tester.pumpWidget(pumpChips(() {},
          onTap: (text) => tappedText = text));

      await tester.tap(find.text('r/france'));
      expect(tappedText, 'r/france');

      await tester.tap(find.text('@HugoDécrypte'));
      expect(tappedText, '@HugoDécrypte');
    });

    testWidgets('displays "Quelques exemples :" label', (tester) async {
      await tester.pumpWidget(pumpChips(() {}));

      expect(find.text('Quelques exemples :'), findsOneWidget);
    });
  });
}
