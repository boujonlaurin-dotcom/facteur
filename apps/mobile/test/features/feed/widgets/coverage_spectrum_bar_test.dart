import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/coverage_spectrum_bar.dart';

void main() {
  // La barre délègue sa largeur au parent → hôte à largeur bornée (comme le
  // header qui l'enveloppe dans un Flexible(ConstrainedBox(min70/max150))).
  Widget host(Map<String, int> distribution) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 150,
            child: CoverageSpectrumBar(distribution: distribution),
          ),
        ),
      ),
    );
  }

  // Les 5 segments sont désormais des AnimatedContainer toujours montés (largeur
  // explicite animée, 0 si count nul) — cf. refonte carrousel. On lit la largeur
  // via les contraintes (width → BoxConstraints.tightFor → maxWidth).
  List<double> segmentWidths(WidgetTester tester) => tester
      .widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(CoverageSpectrumBar),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .map((c) => c.constraints?.maxWidth ?? 0.0)
      .toList();

  group('CoverageSpectrumBar', () {
    testWidgets('hauteur fixe 11, largeur déléguée, 5 segments montés',
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
        find
            .descendant(
              of: find.byType(CoverageSpectrumBar),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sized.height, 11);
      // Largeur non fixée par la barre (déléguée au parent).
      expect(sized.width, isNull);

      // 5 segments toujours montés ; distribution uniforme → 5 largeurs égales > 0.
      final widths = segmentWidths(tester);
      expect(widths.length, 5);
      expect(widths.every((w) => w > 0), isTrue);
      for (final w in widths) {
        expect(w, closeTo(widths.first, 0.5));
      }
    });

    testWidgets('largeur proportionnelle à la distribution brute',
        (tester) async {
      await tester.pumpWidget(host(const {
        'left': 4,
        'center-left': 0,
        'center': 2,
        'center-right': 0,
        'right': 0,
      }));
      await tester.pumpAndSettle();

      final widths = segmentWidths(tester);
      expect(widths.length, 5);
      // Seuls left (idx 0) et center (idx 2) ont une largeur ; ratio 4:2 = 2:1.
      final visible = [
        for (var i = 0; i < widths.length; i++)
          if (widths[i] > 0) (i, widths[i]),
      ];
      expect(visible.map((e) => e.$1).toList(), [0, 2]);
      expect(visible[0].$2, closeTo(visible[1].$2 * 2, 0.5));
    });

    testWidgets('aucune largeur de segment pour une distribution vide',
        (tester) async {
      await tester.pumpWidget(host(const <String, int>{}));
      await tester.pumpAndSettle();

      final widths = segmentWidths(tester);
      // 5 segments montés mais tous à largeur nulle (rien de visible).
      expect(widths.length, 5);
      expect(widths.every((w) => w == 0), isTrue);
    });

    testWidgets('showAnchorLabels : repères Gauche / Droite sous la barre',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 150,
              child: CoverageSpectrumBar(
                distribution: {
                  'left': 1,
                  'center': 1,
                  'right': 1,
                },
                showAnchorLabels: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gauche'), findsOneWidget);
      expect(find.text('Droite'), findsOneWidget);
      // Permanents : présents même sans interaction.
      // La barre conserve sa largeur pleine déléguée (150) malgré la Column.
      expect(
        tester.getSize(find.byType(CoverageSpectrumBar)).width,
        closeTo(150, 0.5),
      );
    });

    testWidgets('sans showAnchorLabels : aucun repère (défaut)',
        (tester) async {
      await tester.pumpWidget(host(const {
        'left': 1,
        'center': 1,
        'right': 1,
      }));
      await tester.pumpAndSettle();

      expect(find.text('Gauche'), findsNothing);
      expect(find.text('Droite'), findsNothing);
    });

    testWidgets('interactive : tap mappe la position x → clé de stance',
        (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 150,
              child: CoverageSpectrumBar(
                distribution: const {
                  'left': 1,
                  'center-left': 1,
                  'center': 1,
                  'center-right': 1,
                  'right': 1,
                },
                onSegmentTap: tapped.add,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Cible tactile élargie à 24 px de haut quand interactive.
      expect(tester.getSize(find.byType(CoverageSpectrumBar)).height, 24);

      final rect = tester.getRect(find.byType(CoverageSpectrumBar));
      // Tap à gauche → 'left' ; tap à droite → 'right'.
      await tester.tapAt(Offset(rect.left + 5, rect.center.dy));
      await tester.tapAt(Offset(rect.right - 5, rect.center.dy));
      await tester.pumpAndSettle();

      expect(tapped.first, 'left');
      expect(tapped.last, 'right');
    });
  });
}
