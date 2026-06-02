import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show TokenSpan;
import 'package:facteur/features/feed/widgets/coverage_spectrum_bar.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

Perspective _p(String name, {String bias = 'center'}) => Perspective(
      title: 'Titre $name',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '',
      biasStance: bias,
    );

Future<void> _pumpInline(
  WidgetTester tester, {
  required PerspectivesSectionStatus status,
  List<Perspective> perspectives = const [],
  bool isExpanded = false,
  PerspectivesAnalysisState analysisState = PerspectivesAnalysisState.idle,
  String? analysisText,
  required VoidCallback onToggle,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: PerspectivesInlineSection(
              status: status,
              perspectives: perspectives,
              biasDistribution: const {'left': 1, 'center': 1, 'right': 1},
              contentId: 'test-content-id',
              sourceName: 'Test',
              analysisState: analysisState,
              analysisText: analysisText,
              isExpanded: isExpanded,
              onToggle: onToggle,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final caret = PhosphorIcons.caretDown(PhosphorIconsStyle.regular);

  testWidgets('loading shows header shimmer without caret or body', (
    tester,
  ) async {
    var toggleCount = 0;

    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.loading,
      isExpanded: true,
      onToggle: () => toggleCount++,
    );

    expect(find.text('Couverture médiatique'), findsOneWidget);
    expect(find.byType(CoverageSpectrumBarShimmer), findsOneWidget);
    expect(find.byIcon(caret), findsNothing);
    expect(find.textContaining("marquent l'angle éditorial"), findsNothing);
    expect(find.text('CET ARTICLE'), findsNothing);

    await tester.tap(find.text('Couverture médiatique'));
    expect(toggleCount, 0);
  });

  testWidgets('empty shows grey zero label without caret and is not tappable', (
    tester,
  ) async {
    var toggleCount = 0;

    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.empty,
      onToggle: () => toggleCount++,
    );

    expect(find.text('Couverture médiatique (0)'), findsOneWidget);
    expect(find.byType(CoverageSpectrumBarShimmer), findsNothing);
    expect(find.byIcon(caret), findsNothing);

    await tester.tap(find.text('Couverture médiatique (0)'));
    expect(toggleCount, 0);
  });

  testWidgets('ready keeps caret and toggles on tap', (tester) async {
    var toggleCount = 0;

    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A')],
      onToggle: () => toggleCount++,
    );

    expect(find.text('Couverture médiatique (1)'), findsOneWidget);
    expect(find.byType(CoverageSpectrumBar), findsOneWidget);
    expect(find.byIcon(caret), findsOneWidget);

    await tester.tap(find.text('Couverture médiatique (1)'));
    expect(toggleCount, 1);
  });

  testWidgets(
    'expanded ready puts analysis above variants and removes ref block',
    (tester) async {
      await _pumpInline(
        tester,
        status: PerspectivesSectionStatus.ready,
        perspectives: [
          _p('A'),
          _p('B', bias: 'left'),
        ],
        isExpanded: true,
        analysisState: PerspectivesAnalysisState.done,
        analysisText: 'Synthèse test',
        onToggle: () {},
      );

      final analysisTop =
          tester.getTopLeft(find.text('Analyse Facteur').first).dy;
      final firstVariantTop =
          tester.getTopLeft(find.text('Titre A', findRichText: true)).dy;

      expect(analysisTop, lessThan(firstVariantTop));
      expect(find.text('CET ARTICLE'), findsNothing);
      expect(
        find.text(
          'Analyse générée par Mistral Large · l\'IA peut faire des erreurs.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('PivotWashTitle washes the reader title pivot when expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const Scaffold(
          body: PivotWashTitle(
            title: 'Le gouvernement annonce une réforme',
            pivot: TokenSpan(start: 3, end: 15, text: 'gouvernement'),
            animate: false,
          ),
        ),
      ),
    );

    final pivotText = find.text('gouvernement');
    expect(pivotText, findsOneWidget);

    final pivotContainer = tester.widget<Container>(
      find.ancestor(of: pivotText, matching: find.byType(Container)).first,
    );
    final decoration = pivotContainer.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF9E9E9E).withValues(alpha: 0.14));
  });
}
