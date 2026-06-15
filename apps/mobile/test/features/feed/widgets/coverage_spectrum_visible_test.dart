import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/coverage_spectrum_bar.dart';

void main() {
  testWidgets('chaque segment a une taille non nulle (h8, largeur bornée)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 150,
            child: CoverageSpectrumBar(distribution: {
              'left': 1, 'center-left': 1, 'center': 1, 'center-right': 1, 'right': 1,
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final szBox = tester.getSize(find.byType(CoverageSpectrumBar));
    expect(szBox.height, 8);

    final boxes = find.byType(DecoratedBox);
    final count = boxes.evaluate().length;
    for (var i = 0; i < count; i++) {
      final size = tester.getSize(boxes.at(i));
      expect(size.width, greaterThan(0), reason: 'segment[$i] width = 0');
      expect(size.height, greaterThan(0), reason: 'segment[$i] height = 0');
    }
  });
}
