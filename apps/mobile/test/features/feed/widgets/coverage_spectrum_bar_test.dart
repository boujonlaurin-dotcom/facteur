import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/coverage_spectrum_bar.dart';

void main() {
  Widget host(Map<String, int> distribution) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: Center(child: CoverageSpectrumBar(distribution: distribution)),
      ),
    );
  }

  group('CoverageSpectrumBar', () {
    testWidgets('rend 5 segments distincts à taille fixe 96x9',
        (tester) async {
      await tester.pumpWidget(host(const {
        'left': 1,
        'center-left': 1,
        'center': 1,
        'center-right': 1,
        'right': 1,
      }));
      await tester.pumpAndSettle();

      final sized = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(CoverageSpectrumBar),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(sized.width, 96);
      expect(sized.height, 9);

      // 5 Expanded inside the inner Row (un par segment).
      expect(
        find.descendant(
          of: find.byType(CoverageSpectrumBar),
          matching: find.byType(Expanded),
        ),
        findsNWidgets(5),
      );
    });

    testWidgets('flex proportionnel à la distribution brute',
        (tester) async {
      await tester.pumpWidget(host(const {
        'left': 4,
        'center-left': 0,
        'center': 2,
        'center-right': 0,
        'right': 0,
      }));
      await tester.pumpAndSettle();

      final expandeds = tester
          .widgetList<Expanded>(
            find.descendant(
              of: find.byType(CoverageSpectrumBar),
              matching: find.byType(Expanded),
            ),
          )
          .toList();

      // L=4, CL=floor 1, C=2, CR=floor 1, R=floor 1
      expect(expandeds.map((e) => e.flex).toList(), [4, 1, 2, 1, 1]);
    });

    testWidgets('floor=1 pour segments à zéro (visibilité minimale)',
        (tester) async {
      await tester.pumpWidget(host(const <String, int>{}));
      await tester.pumpAndSettle();

      final expandeds = tester
          .widgetList<Expanded>(
            find.descendant(
              of: find.byType(CoverageSpectrumBar),
              matching: find.byType(Expanded),
            ),
          )
          .toList();

      expect(expandeds.map((e) => e.flex).toList(), [1, 1, 1, 1, 1]);
    });
  });
}
