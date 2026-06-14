import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/detail/screens/content_detail_screen.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show PerspectiveData, PerspectivesResponse, TokenSpan;
import 'package:facteur/features/feed/widgets/coverage_comparison_card.dart';
import 'package:facteur/features/feed/widgets/coverage_spectrum_bar.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

// sourceDomain vide → la carte utilise le fallback (pas d'Image.network en test).
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
  String? divergenceLevel,
  VoidCallback? onOpenAnalysis,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 390,
              child: PerspectivesInlineSection(
                status: status,
                perspectives: perspectives,
                biasDistribution: const {'left': 1, 'center': 1, 'right': 1},
                contentId: 'test-content-id',
                sourceName: 'Test',
                divergenceLevel: divergenceLevel,
                onOpenAnalysis: onOpenAnalysis,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('loading : libellé + shimmer, pas de carrousel ni CTA',
      (tester) async {
    await _pumpInline(tester, status: PerspectivesSectionStatus.loading);

    expect(find.text('Couverture médiatique'), findsOneWidget);
    expect(find.byType(CoverageSpectrumBarShimmer), findsOneWidget);
    expect(find.byType(CoverageComparisonCard), findsNothing);
    expect(find.text('Analyse Facteur'), findsNothing);
  });

  test('partial empty response keeps perspectives status loading', () {
    expect(resolvePerspectivesStatus(null), PerspectivesSectionStatus.loading);
    expect(
      resolvePerspectivesStatus(
        PerspectivesResponse(
          perspectives: const [],
          keywords: const [],
          biasDistribution: const {},
          partial: true,
        ),
      ),
      PerspectivesSectionStatus.loading,
    );
    expect(
      resolvePerspectivesStatus(
        PerspectivesResponse(
          perspectives: [
            PerspectiveData(
              title: 'Titre',
              url: 'https://example.com/a',
              sourceName: 'A',
              sourceDomain: 'example.com',
              biasStance: 'center',
            ),
          ],
          keywords: const [],
          biasDistribution: const {},
          partial: true,
        ),
      ),
      PerspectivesSectionStatus.ready,
    );
    expect(
      resolvePerspectivesStatus(
        PerspectivesResponse(
          perspectives: const [],
          keywords: const [],
          biasDistribution: const {},
        ),
      ),
      PerspectivesSectionStatus.empty,
    );
  });

  testWidgets('empty fades out after delay then collapses', (tester) async {
    await _pumpInline(tester, status: PerspectivesSectionStatus.empty);

    expect(find.text('Couverture médiatique (0)'), findsOneWidget);
    expect(find.byType(CoverageSpectrumBarShimmer), findsNothing);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0.28,
    );

    // Pause de lecture : le bandeau reste visible.
    await tester.pump(const Duration(milliseconds: 1999));
    expect(find.text('Couverture médiatique (0)'), findsOneWidget);

    // Timer 2000 ms → fading + slide démarrent.
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );

    // Collapse après le slide (650 ms) + AnimatedSize (250 ms).
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Couverture médiatique (0)'), findsNothing);
  });

  testWidgets('ready : carrousel de cartes + carte CTA, pas de caret',
      (tester) async {
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A'), _p('B', bias: 'left')],
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Couverture médiatique (2)'), findsOneWidget);
    expect(find.byType(CoverageSpectrumBar), findsOneWidget);
    expect(find.byType(CoverageComparisonCard), findsNWidgets(2));
    // Carte CTA Analyse en fin de carrousel.
    expect(find.text('Analyse Facteur'), findsOneWidget);
    // Le disclaimer Mistral n'est plus inline (il vit dans le bottom sheet).
    expect(find.textContaining('Mistral'), findsNothing);
  });

  testWidgets('ready : tap sur la carte CTA déclenche onOpenAnalysis',
      (tester) async {
    var opened = 0;
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A')],
      onOpenAnalysis: () => opened++,
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.ensureVisible(find.text('Lancer'));
    await tester.tap(find.text('Lancer'));
    expect(opened, 1);
  });

  testWidgets('PivotWashTitle washes the reader title pivot when expanded',
      (tester) async {
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
