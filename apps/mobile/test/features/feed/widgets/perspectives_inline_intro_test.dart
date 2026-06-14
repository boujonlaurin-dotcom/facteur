import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/widgets/divergence_inline_badge.dart';
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
  const introSnippet = "marquent l'angle éditorial";
  final infoIcon = PhosphorIcons.info(PhosphorIconsStyle.regular);

  testWidgets('ready : intro derrière le bouton info de l\'en-tête',
      (tester) async {
    await _pumpInline(tester, perspectives: [_p('A'), _p('B', bias: 'left')]);
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining(introSnippet), findsNothing);

    await tester.tap(find.byIcon(infoIcon).first);
    await tester.pumpAndSettle();

    expect(find.textContaining(introSnippet), findsOneWidget);
  });

  testWidgets('loading : ni bouton info ni intro', (tester) async {
    await _pumpInline(
      tester,
      perspectives: const [],
      status: PerspectivesSectionStatus.loading,
    );

    expect(find.byIcon(infoIcon), findsNothing);
    expect(find.textContaining(introSnippet), findsNothing);
  });

  testWidgets('ready high divergence → badge POLARISÉ', (tester) async {
    await _pumpInline(
      tester,
      perspectives: [_p('A'), _p('B', bias: 'right')],
      divergenceLevel: 'high',
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('POLARISÉ'), findsOneWidget);
  });

  testWidgets('ready low divergence → badge TRAITEMENTS SIMILAIRES',
      (tester) async {
    await _pumpInline(
      tester,
      perspectives: [_p('A'), _p('B', bias: 'right')],
      divergenceLevel: 'low',
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('TRAITEMENTS SIMILAIRES'), findsOneWidget);
  });

  testWidgets('badge de la couverture utilise l’échelle agrandie 1.45',
      (tester) async {
    await _pumpInline(
      tester,
      perspectives: [_p('A'), _p('B', bias: 'right')],
      divergenceLevel: 'medium',
    );
    await tester.pump(const Duration(seconds: 1));

    final badge = tester.widget<DivergenceInlineBadge>(
      find.byType(DivergenceInlineBadge),
    );
    expect(badge.scale, 1.45);
  });
}
