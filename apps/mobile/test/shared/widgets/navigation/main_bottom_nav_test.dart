import 'package:facteur/config/theme.dart';
import 'package:facteur/shared/widgets/navigation/main_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({
    required int currentIndex,
    required ValueChanged<int> onSelect,
  }) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        bottomNavigationBar: MainBottomNav(
          currentIndex: currentIndex,
          onSelect: onSelect,
        ),
      ),
    );
  }

  group('MainBottomNav', () {
    testWidgets('tap onglet inactif → onSelect(indexCible)', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        wrap(currentIndex: 0, onSelect: taps.add),
      );

      await tester.tap(find.text('Flâner'));
      await tester.pump();

      expect(taps, [1]);
    });

    testWidgets('tap onglet actif → onSelect(indexCourant) (scroll-to-top géré '
        'par le shell)', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        wrap(currentIndex: 0, onSelect: taps.add),
      );

      await tester.tap(find.text('L’Essentiel'));
      await tester.pump();

      expect(taps, [0]);
    });

    testWidgets('reflète l\'onglet actif via la sémantique', (tester) async {
      await tester.pumpWidget(
        wrap(currentIndex: 1, onSelect: (_) {}),
      );

      final flaner = tester.getSemantics(find.text('Flâner'));
      expect(flaner.hasFlag(SemanticsFlag.isSelected), isTrue);
    });
  });
}
