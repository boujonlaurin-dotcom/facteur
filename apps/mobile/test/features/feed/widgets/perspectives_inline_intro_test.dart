import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/widgets/divergence_inline_badge.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show ConsensusBlock, DisplayGates;
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
  required List<Perspective> perspectives,
  PerspectivesSectionStatus status = PerspectivesSectionStatus.ready,
  String? divergenceLevel,
  ConsensusBlock consensus = const ConsensusBlock.absent(),
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
                biasDistribution: const {'center': 0},
                keywords: const [],
                contentId: 'test-content-id',
                sourceBiasStance: 'center',
                sourceName: 'Test',
                divergenceLevel: divergenceLevel,
                consensus: consensus,
                display: DisplayGates.fromCoverageCount(
                  perspectives.length + 1,
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
  // Le bouton info de l'en-tête ouvre une modal expliquant la divergence
  // (le surlignage est désactivé → kHighlightIntroText n'est plus rendu).
  const infoSnippet = 'Facteur mesure la divergence';
  final infoIcon = PhosphorIcons.info(PhosphorIconsStyle.regular);

  testWidgets('ready : explication divergence derrière le bouton info de l\'en-tête',
      (tester) async {
    await _pumpInline(tester, perspectives: [_p('A'), _p('B', bias: 'left')]);
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining(infoSnippet), findsNothing);

    await tester.tap(find.byIcon(infoIcon).first);
    await tester.pumpAndSettle();

    expect(find.textContaining(infoSnippet), findsOneWidget);
  });

  testWidgets('loading : ni bouton info ni explication', (tester) async {
    await _pumpInline(
      tester,
      perspectives: const [],
      status: PerspectivesSectionStatus.loading,
    );

    expect(find.byIcon(infoIcon), findsNothing);
    expect(find.textContaining(infoSnippet), findsNothing);
  });

  testWidgets(
      'badge POLARISÉ supprimé du Reader, même avec divergenceLevel fourni',
      (tester) async {
    await _pumpInline(
      tester,
      perspectives: [_p('A'), _p('B', bias: 'right')],
      divergenceLevel: 'high',
    );
    await tester.pump(const Duration(seconds: 1));

    // « polarisé » ne vient plus que du qualifier backend (header) — ici
    // absent → aucune mention, et plus jamais de badge.
    expect(find.byType(DivergenceInlineBadge), findsNothing);
    expect(find.text('POLARISÉ'), findsNothing);
    expect(find.textContaining('polarisé', findRichText: true), findsNothing);
  });

  testWidgets('qualifier backend → suffixe unique au header', (tester) async {
    await _pumpInline(
      tester,
      perspectives: [_p('A'), _p('B', bias: 'right')],
      divergenceLevel: 'high',
      consensus: const ConsensusBlock(
        state: ConsensusBlock.stateAvailable,
        qualifier: 'polarized',
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.textContaining('(polarisé)', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(DivergenceInlineBadge), findsNothing);
  });
}
