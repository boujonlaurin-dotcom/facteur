import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/widgets/divergence_inline_badge.dart';

void main() {
  Widget host(String? level) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: Center(child: DivergenceInlineBadge(divergenceLevel: level)),
      ),
    );
  }

  group('DivergenceInlineBadge', () {
    testWidgets('low → Traitements similaires en text_secondary non bold', (
      tester,
    ) async {
      await tester.pumpWidget(host('low'));
      await tester.pumpAndSettle();

      expect(find.text('TRAITEMENTS SIMILAIRES'), findsOneWidget);
      final label = tester.widget<Text>(find.text('TRAITEMENTS SIMILAIRES'));
      expect(label.style?.fontWeight, FontWeight.w500);
      expect(
        find.descendant(
          of: find.byType(DivergenceInlineBadge),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('medium → Avis variés en text_tertiary (non bold)', (
      tester,
    ) async {
      await tester.pumpWidget(host('medium'));
      await tester.pumpAndSettle();

      expect(find.text('AVIS VARIÉS'), findsOneWidget);
      final label = tester.widget<Text>(find.text('AVIS VARIÉS'));
      expect(label.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('medium + prominentMedium → boost léger (w600, secondary)', (
      tester,
    ) async {
      final colors = FacteurTheme.lightTheme.extension<FacteurColors>()!;
      await tester.pumpWidget(
        MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: DivergenceInlineBadge(
                divergenceLevel: 'medium',
                prominentMedium: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(find.text('AVIS VARIÉS'));
      // Boost léger : w600 (ni w500 discret, ni w700 réservé à high) en
      // text_secondary (ni tertiary discret, ni text_primary réservé à high).
      expect(label.style?.fontWeight, FontWeight.w600);
      expect(label.style?.color, colors.textSecondary);
    });

    testWidgets('prominentMedium sans effet sur high (reste w700/primary)', (
      tester,
    ) async {
      final colors = FacteurTheme.lightTheme.extension<FacteurColors>()!;
      await tester.pumpWidget(
        MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: DivergenceInlineBadge(
                divergenceLevel: 'high',
                prominentMedium: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(find.text('POLARISÉ'));
      expect(label.style?.fontWeight, FontWeight.w700);
      expect(label.style?.color, colors.textPrimary);
    });

    testWidgets('high → Polarisé en text_primary bold', (tester) async {
      await tester.pumpWidget(host('high'));
      await tester.pumpAndSettle();

      expect(find.text('POLARISÉ'), findsOneWidget);
      final label = tester.widget<Text>(find.text('POLARISÉ'));
      expect(label.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('null → SizedBox.shrink (silence, pas de rendu)', (
      tester,
    ) async {
      await tester.pumpWidget(host(null));
      await tester.pumpAndSettle();

      expect(find.text('TRAITEMENTS SIMILAIRES'), findsNothing);
      expect(find.text('AVIS VARIÉS'), findsNothing);
      expect(find.text('POLARISÉ'), findsNothing);
      // Aucun CustomPaint sous notre widget (les CustomPaint du framework
      // sont au-dessus du DivergenceInlineBadge dans l'arbre).
      expect(
        find.descendant(
          of: find.byType(DivergenceInlineBadge),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('valeur inconnue → silence (pas de crash)', (tester) async {
      await tester.pumpWidget(host('unknown_random_value'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(DivergenceInlineBadge),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });
  });
}
