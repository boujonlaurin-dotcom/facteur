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
    testWidgets('low → Consensus en text_tertiary (non bold)', (tester) async {
      await tester.pumpWidget(host('low'));
      await tester.pumpAndSettle();

      expect(find.text('CONSENSUS'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      final label = tester.widget<Text>(find.text('CONSENSUS'));
      expect(label.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('medium → Avis variés en text_tertiary (non bold)',
        (tester) async {
      await tester.pumpWidget(host('medium'));
      await tester.pumpAndSettle();

      expect(find.text('AVIS VARIÉS'), findsOneWidget);
      final label = tester.widget<Text>(find.text('AVIS VARIÉS'));
      expect(label.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('high → Polarisé en text_primary bold', (tester) async {
      await tester.pumpWidget(host('high'));
      await tester.pumpAndSettle();

      expect(find.text('POLARISÉ'), findsOneWidget);
      final label = tester.widget<Text>(find.text('POLARISÉ'));
      expect(label.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('null → SizedBox.shrink (silence, pas de rendu)',
        (tester) async {
      await tester.pumpWidget(host(null));
      await tester.pumpAndSettle();

      expect(find.text('CONSENSUS'), findsNothing);
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
