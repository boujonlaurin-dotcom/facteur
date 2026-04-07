import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/widgets/divergence_analysis_block.dart';

void main() {
  Widget buildWidget({
    String? divergenceAnalysis,
    String? biasHighlights,
    VoidCallback? onCompare,
    int perspectiveCount = 0,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DivergenceAnalysisBlock(
            divergenceAnalysis: divergenceAnalysis,
            biasHighlights: biasHighlights,
            onCompare: onCompare,
            perspectiveCount: perspectiveCount,
          ),
        ),
      ),
    );
  }

  group('DivergenceAnalysisBlock', () {
    testWidgets('renders nothing when divergenceAnalysis is null', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text("\u{1F50D} L'analyse Facteur"), findsNothing);
    });

    testWidgets('displays analysis text when provided', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Libération insiste sur l\'impact social.',
      ));
      expect(find.text("\u{1F50D} L'analyse Facteur"), findsOneWidget);
    });

    testWidgets('shows collapsed text with "Lire la suite" by default', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
      ));
      expect(find.text('Lire la suite\u2026'), findsOneWidget);
    });

    testWidgets('expands text on tap and hides "Lire la suite"', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
      ));
      // Tap to expand
      await tester.tap(find.text('Lire la suite\u2026'));
      await tester.pump();
      expect(find.text('Lire la suite\u2026'), findsNothing);
    });

    testWidgets('hides bias highlights when null', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
      ));
      expect(find.text('Très couvert à gauche'), findsNothing);
    });

    testWidgets('shows CTA when onCompare is provided with perspectives', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
        onCompare: () => tapped = true,
        perspectiveCount: 3,
      ));
      final ctaFinder = find.text('Toutes les perspectives');
      expect(ctaFinder, findsOneWidget);

      await tester.tap(ctaFinder);
      expect(tapped, isTrue);
    });

    testWidgets('hides CTA button when onCompare is null', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
      ));
      expect(find.text('Toutes les perspectives'), findsNothing);
    });
  });
}
