import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/detail/deck/widgets/deck_progress_bar.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required int index,
    int length = 5,
    double progress = 0,
    bool completed = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(
          body: DeckProgressBar(
            index: index,
            length: length,
            progress: progress,
            completed: completed,
          ),
        ),
      ),
    );
  }

  /// Aplats peints dans le segment [i], piste comprise (toujours en premier).
  List<Color> fillsOf(WidgetTester tester, int i) => tester
      .widgetList<ColoredBox>(
        find.descendant(
          of: find.byKey(DeckProgressBar.segmentKey(i)),
          matching: find.byType(ColoredBox),
        ),
      )
      .map((box) => box.color)
      .toList();

  /// Un segment « porte de l'encre » dès qu'il peint autre chose que sa piste.
  bool isInked(WidgetTester tester, int i) => fillsOf(tester, i).length > 1;

  double currentFillFactor(WidgetTester tester, int i) => tester
      .widget<FractionallySizedBox>(
        find.descendant(
          of: find.byKey(DeckProgressBar.segmentKey(i)),
          matching: find.byType(FractionallySizedBox),
        ),
      )
      .widthFactor!;

  group('DeckProgressBar', () {
    testWidgets('à l’article k, k+1 segments portent de l’encre', (
      tester,
    ) async {
      await pumpBar(tester, index: 2, length: 5);

      expect([for (var i = 0; i < 5; i++) isInked(tester, i)], [
        true,
        true,
        true,
        false,
        false,
      ]);
    });

    testWidgets('au 1ᵉʳ article, le 1ᵉʳ segment est déjà atteint', (
      tester,
    ) async {
      await pumpBar(tester, index: 0, length: 5);

      expect(isInked(tester, 0), isTrue);
      expect(isInked(tester, 1), isFalse);
    });

    testWidgets(
      'au dernier article, plus aucun segment vide — la barre est pleine',
      (tester) async {
        await pumpBar(tester, index: 4, length: 5);

        expect(
          [for (var i = 0; i < 5; i++) isInked(tester, i)],
          everyElement(isTrue),
        );
      },
    );

    testWidgets('le segment courant suit la progression de lecture', (
      tester,
    ) async {
      await pumpBar(tester, index: 1, length: 3, progress: 0.4);

      expect(currentFillFactor(tester, 1), closeTo(0.4, 0.001));
    });

    testWidgets('article terminé : son segment se remplit entièrement', (
      tester,
    ) async {
      // Le latch de complétion peut se fermer avant que le scroll n’atteigne le
      // bas : le segment ne doit pas rester à moitié vide pour autant.
      await pumpBar(
        tester,
        index: 1,
        length: 3,
        progress: 0.7,
        completed: true,
      );

      expect(currentFillFactor(tester, 1), 1.0);
    });
  });
}
