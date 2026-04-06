import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/widgets/divergence_analysis_block.dart';

void main() {
  Widget buildWidget({
    String? divergenceAnalysis,
    String? biasHighlights,
    VoidCallback? onCompare,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DivergenceAnalysisBlock(
            divergenceAnalysis: divergenceAnalysis,
            biasHighlights: biasHighlights,
            onCompare: onCompare,
          ),
        ),
      ),
    );
  }

  group('DivergenceAnalysisBlock', () {
    testWidgets('renders nothing when divergenceAnalysis is null', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('\u{1F50D} Analyse des angles m\u00e9diatiques'), findsNothing);
    });

    testWidgets('displays analysis text when provided', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Lib\u00e9ration insiste sur l\'impact social.',
      ));
      expect(find.text('\u{1F50D} Analyse des angles m\u00e9diatiques'), findsOneWidget);
      expect(find.text('Lib\u00e9ration insiste sur l\'impact social.'), findsOneWidget);
    });

    testWidgets('displays bias highlights when provided', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
        biasHighlights: 'Tr\u00e8s couvert \u00e0 gauche',
      ));
      expect(find.text('Tr\u00e8s couvert \u00e0 gauche'), findsOneWidget);
    });

    testWidgets('hides bias highlights when null', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
      ));
      expect(find.text('Tr\u00e8s couvert \u00e0 gauche'), findsNothing);
    });

    testWidgets('shows CTA button when onCompare is provided', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
        onCompare: () => tapped = true,
      ));
      final ctaFinder = find.text('Comparer les sources \u2192');
      expect(ctaFinder, findsOneWidget);

      await tester.tap(ctaFinder);
      expect(tapped, isTrue);
    });

    testWidgets('hides CTA button when onCompare is null', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
      ));
      expect(find.text('Comparer les sources \u2192'), findsNothing);
    });
  });
}
