import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/widgets/divergence_analysis_block.dart';
import 'package:facteur/features/digest/widgets/markdown_text.dart';
import 'package:facteur/features/feed/widgets/initial_circle.dart';

void main() {
  Widget buildWidget({
    String? divergenceAnalysis,
    String? biasHighlights,
    String? divergenceLevel,
    VoidCallback? onCompare,
    int perspectiveCount = 0,
    List<SourceMini> perspectiveSources = const [],
    String? excludeSourceId,
    String? excludeSourceName,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DivergenceAnalysisBlock(
            divergenceAnalysis: divergenceAnalysis,
            biasHighlights: biasHighlights,
            divergenceLevel: divergenceLevel,
            onCompare: onCompare,
            perspectiveCount: perspectiveCount,
            perspectiveSources: perspectiveSources,
            excludeSourceId: excludeSourceId,
            excludeSourceName: excludeSourceName,
          ),
        ),
      ),
    );
  }

  group('DivergenceAnalysisBlock', () {
    testWidgets('renders nothing when divergenceAnalysis is null',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.textContaining('Analyse de biais'), findsNothing);
    });

    testWidgets('displays badge header when analysis is provided',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Libération insiste sur l\'impact social.',
        perspectiveCount: 3,
      ));
      // Badge "🔍 Analyse de biais" (no sources count in badge anymore)
      expect(
        find.text('\u{1F50D} Analyse de biais'),
        findsOneWidget,
      );
    });

    testWidgets(
        'inline divergence line shows colored label + sources when level=medium',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse',
        divergenceLevel: 'medium',
        perspectiveCount: 3,
      ));
      expect(find.text('Angles différents · 3 sources'), findsOneWidget);
    });

    testWidgets('inline divergence line hidden when level is null',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse',
        perspectiveCount: 3,
      ));
      expect(find.text('Angles différents · 3 sources'), findsNothing);
      expect(find.text('Fort désaccord · 3 sources'), findsNothing);
    });

    testWidgets('analysis text is hidden by default (E1.b collapsed)',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte secrète',
      ));
      // MarkdownText non rendu (texte caché)
      expect(find.byType(MarkdownText), findsNothing);
      // Chevron "Lire l'analyse" visible
      expect(find.text("Lire l'analyse"), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('uses InkWell wrapper for toggle', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
      ));
      // Parent InkWell wraps the card; the collapsed CTA OutlinedButton
      // adds its own internal InkWell — assert at least the parent is there.
      expect(find.byType(InkWell), findsAtLeastNWidgets(1));
    });

    testWidgets('tap on chevron reveals analysis text', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte révélée',
      ));
      await tester.tap(find.text("Lire l'analyse"));
      await tester.pump();
      // Texte révélé via MarkdownText, chevron "Réduire" visible
      expect(find.text("Lire l'analyse"), findsNothing);
      expect(find.text('Réduire'), findsOneWidget);
      expect(find.byType(MarkdownText), findsOneWidget);
      final markdown = tester.widget<MarkdownText>(find.byType(MarkdownText));
      expect(markdown.text, equals('Analyse texte révélée'));
    });

    testWidgets('tap on Réduire collapses analysis', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse',
      ));
      // Expand
      await tester.tap(find.text("Lire l'analyse"));
      await tester.pump();
      expect(find.byType(MarkdownText), findsOneWidget);
      // Collapse via Réduire
      await tester.tap(find.text('Réduire'));
      await tester.pump();
      expect(find.byType(MarkdownText), findsNothing);
      expect(find.text("Lire l'analyse"), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('CTA "Voir les N perspectives" appears only when expanded',
        (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
        onCompare: () => tapped = true,
        perspectiveCount: 3,
      ));
      // Replié : CTA caché
      expect(find.text('Voir les 3 perspectives'), findsNothing);

      // Déplier
      await tester.tap(find.text("Lire l'analyse"));
      await tester.pump();

      final ctaFinder = find.text('Voir les 3 perspectives');
      expect(ctaFinder, findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);

      await tester.tap(ctaFinder);
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('hides CTA button when onCompare is null even when expanded',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
        perspectiveCount: 3,
      ));
      await tester.tap(find.text("Lire l'analyse"));
      await tester.pump();
      expect(find.text('Voir les 3 perspectives'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('hides CTA when perspectiveCount <= 1', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
        onCompare: () {},
        perspectiveCount: 1,
      ));
      await tester.tap(find.text("Lire l'analyse"));
      await tester.pump();
      expect(find.text('Voir les 1 perspectives'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('tooltip ⓘ is no longer rendered', (tester) async {
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse texte',
      ));
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets(
        'CTA shows up to 3 other-source logos and excludes the singleton source',
        (tester) async {
      const singleton = SourceMini(id: 's0', name: 'Ouest-France');
      const others = [
        SourceMini(id: 's1', name: 'Le Monde'),
        SourceMini(id: 's2', name: 'France Info'),
        SourceMini(id: 's3', name: 'Libération'),
        SourceMini(id: 's4', name: 'Le Figaro'),
      ];
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse',
        onCompare: () {},
        perspectiveCount: 5,
        perspectiveSources: [singleton, ...others],
        excludeSourceId: singleton.id,
        excludeSourceName: singleton.name,
      ));
      await tester.tap(find.text("Lire l'analyse"));
      await tester.pump();

      // No logo for the singleton source ('O' initial) in the CTA area.
      expect(
        find.descendant(
          of: find.byType(OutlinedButton),
          matching: find.text('O'),
        ),
        findsNothing,
      );
      // Up to 3 InitialCircles for the 3 first other sources (L, F, L).
      final circlesInCta = find.descendant(
        of: find.byType(OutlinedButton),
        matching: find.byType(InitialCircle),
      );
      expect(circlesInCta, findsNWidgets(3));
    });

    testWidgets('CTA logos degrade to zero when no other source is available',
        (tester) async {
      const only = SourceMini(id: 's0', name: 'Ouest-France');
      await tester.pumpWidget(buildWidget(
        divergenceAnalysis: 'Analyse',
        onCompare: () {},
        perspectiveCount: 1,
        perspectiveSources: [only],
        excludeSourceId: only.id,
        excludeSourceName: only.name,
      ));
      // perspectiveCount = 1 → "Voir les perspectives" CTA hidden anyway.
      await tester.tap(find.text("Lire l'analyse"));
      await tester.pump();
      expect(find.textContaining('perspectives'), findsNothing);
    });
  });
}
