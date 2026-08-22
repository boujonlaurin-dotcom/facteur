import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/detail/screens/content_detail_screen.dart';
import 'package:facteur/features/digest/widgets/divergence_inline_badge.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show
        ConsensusBlock,
        ConsensusCta,
        ConsensusStatement,
        DisplayGates,
        PerspectiveData,
        PerspectivesResponse,
        TokenSpan;
import 'package:facteur/features/feed/widgets/consensus_widgets.dart';
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
  int coverageCount = 0,
  VoidCallback? onOpenAnalysis,
  ConsensusBlock consensus = const ConsensusBlock.absent(),
  DisplayGates? display,
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
                coverageCount: coverageCount,
                biasDistribution: const {'left': 1, 'center': 1, 'right': 1},
                contentId: 'test-content-id',
                sourceName: 'Test',
                onOpenAnalysis: onOpenAnalysis,
                consensus: consensus,
                display: display ??
                    DisplayGates.fromCoverageCount(
                      coverageCount > 0
                          ? coverageCount
                          : perspectives.length + 1,
                    ),
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
  testWidgets('loading : libellé + shimmer + squelette plein-format',
      (tester) async {
    await _pumpInline(tester, status: PerspectivesSectionStatus.loading);

    expect(find.text(consensusSectionTitle, findRichText: true), findsOneWidget);
    expect(find.byType(CoverageSpectrumBarShimmer), findsOneWidget);
    // Squelette : le carrousel garde sa hauteur (pas un mince filet), sans
    // vraies cartes ni CTA, et sans message « … ».
    final horizontalCarousel = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .singleWhere(
          (scrollView) => scrollView.scrollDirection == Axis.horizontal,
        );
    expect(
      tester.getSize(find.byWidget(horizontalCarousel)).height,
      223,
    );
    expect(find.byType(CoverageComparisonCard), findsNothing);
    expect(find.text(consensusAiCardTitle), findsNothing);
    expect(find.textContaining('Recherche'), findsNothing);
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

  testWidgets('empty : message lisible puis fondu doux et collapse',
      (tester) async {
    await _pumpInline(tester, status: PerspectivesSectionStatus.empty);

    // Titre + message explicite, lisibles pendant la pause.
    expect(find.text(consensusSectionTitle, findRichText: true), findsOneWidget);
    expect(find.text("Pas d'autre source trouvée"), findsOneWidget);
    expect(find.byType(CoverageSpectrumBarShimmer), findsNothing);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1.0,
    );

    // Pause de lecture : le bandeau reste visible.
    await tester.pump(const Duration(milliseconds: 1799));
    expect(find.text("Pas d'autre source trouvée"), findsOneWidget);

    // Timer 1800 ms → fondu démarre.
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );

    // Collapse après le fondu (450 ms) + AnimatedSize (250 ms).
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text("Pas d'autre source trouvée"), findsNothing);
  });

  testWidgets(
      'ready complet : qualifier au header, constats > barre > sous-titre > '
      'carrousel, badge POLARISÉ absent', (tester) async {
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A'), _p('B', bias: 'left')],
      coverageCount: 3,
      consensus: const ConsensusBlock(
        state: ConsensusBlock.stateAvailable,
        qualifier: 'polarized',
        agreements: [ConsensusStatement(text: 'Un accord partagé.')],
        disagreements: [ConsensusStatement(text: 'Un axe de désaccord.')],
        cta: ConsensusCta(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // Header : « Analyse des angles (polarisé) » — le qualificatif vient du
    // backend et n'apparaît qu'une fois (badge POLARISÉ supprimé du Reader).
    expect(
      find.textContaining('(polarisé)', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(DivergenceInlineBadge), findsNothing);

    // Constats présents.
    final agreement =
        find.textContaining('Un accord partagé.', findRichText: true);
    final disagreement =
        find.textContaining('Un axe de désaccord.', findRichText: true);
    expect(agreement, findsOneWidget);
    expect(disagreement, findsOneWidget);

    // Ordre vertical : constats > barre > sous-titre > carrousel.
    final bar = find.byType(CoverageSpectrumBar);
    final subtitle = find.text(consensusCarouselSubtitle(3));
    final carousel = find.byType(ListView);
    expect(bar, findsOneWidget);
    expect(subtitle, findsOneWidget);
    expect(carousel, findsOneWidget);
    expect(
      tester.getRect(agreement).top,
      lessThan(tester.getRect(disagreement).top),
    );
    expect(
      tester.getRect(disagreement).bottom,
      lessThanOrEqualTo(tester.getRect(bar).top),
    );
    expect(
      tester.getRect(bar).bottom,
      lessThanOrEqualTo(tester.getRect(subtitle).top),
    );
    expect(
      tester.getRect(subtitle).bottom,
      lessThanOrEqualTo(tester.getRect(carousel).top),
    );
    expect(tester.getSize(carousel).height, 223);
  });

  testWidgets('ready : carte IA en DERNIER, après les cartes sources',
      (tester) async {
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A'), _p('B', bias: 'left')],
      coverageCount: 3,
    );
    await tester.pump(const Duration(seconds: 1));

    // La ListView virtualise : la carte IA (dernier item) se rejoint par
    // scroll, après TOUTES les cartes sources.
    final aiCard = find.text(consensusAiCardTitle);
    await tester.scrollUntilVisible(
      aiCard,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(aiCard, findsOneWidget);
    final cardRects = find
        .byType(CoverageComparisonCard)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .toList();
    for (final rect in cardRects) {
      expect(rect.left, lessThan(tester.getRect(aiCard).left));
    }
  });

  testWidgets('gates 2 médias : cartes sans barre ni carte IA',
      (tester) async {
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A')],
      coverageCount: 2,
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CoverageComparisonCard), findsOneWidget);
    expect(find.byType(CoverageSpectrumBar), findsNothing);
    expect(find.text(consensusAiCardTitle), findsNothing);
    expect(find.text(consensusCarouselSubtitle(2)), findsOneWidget);
  });

  testWidgets('pending : footnote sablier, pas de constats', (tester) async {
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A'), _p('B')],
      coverageCount: 3,
      consensus: const ConsensusBlock(state: ConsensusBlock.statePending),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(consensusPendingFootnote(3)), findsOneWidget);
    expect(find.byType(ConsensusStatementRow), findsNothing);
  });

  testWidgets('convergent sans désaccord : footnote égalité', (tester) async {
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A'), _p('B')],
      coverageCount: 3,
      consensus: const ConsensusBlock(
        state: ConsensusBlock.stateAvailable,
        qualifier: 'convergent',
        agreements: [ConsensusStatement(text: 'Tout le monde est d\'accord.')],
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(consensusConvergentFootnote(3)), findsOneWidget);
    expect(
      find.textContaining('(avis convergents)', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('solo : texte seul, sans carrousel ni cloche', (tester) async {
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A')],
      coverageCount: 1,
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(consensusSoloText('Test')), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(CoverageComparisonCard), findsNothing);
    expect(find.textContaining('Me prévenir'), findsNothing);
  });

  testWidgets('ready : tap sur la carte IA déclenche onOpenAnalysis',
      (tester) async {
    var opened = 0;
    await _pumpInline(
      tester,
      status: PerspectivesSectionStatus.ready,
      perspectives: [_p('A'), _p('B')],
      coverageCount: 3,
      onOpenAnalysis: () => opened++,
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.scrollUntilVisible(
      find.text(consensusAiCardAction),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text(consensusAiCardAction));
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
