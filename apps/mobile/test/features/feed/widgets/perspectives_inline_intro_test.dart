import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
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
  bool isExpanded = true,
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
                perspectives: perspectives,
                biasDistribution: const {'center': 0},
                keywords: const [],
                contentId: 'test-content-id',
                sourceBiasStance: 'center',
                sourceName: 'Test',
                divergenceLevel: divergenceLevel,
                referenceTitle: 'Titre référence',
                isExpanded: isExpanded,
                onToggle: () {},
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

  testWidgets(
    'inline expanded + perspectives non vides → intro rendue en haut du groupe',
    (tester) async {
      await _pumpInline(
        tester,
        perspectives: [
          _p('A'),
          _p('B', bias: 'left'),
        ],
      );

      expect(find.textContaining(introSnippet), findsOneWidget);
    },
  );

  testWidgets(
    'inline expanded + perspectives vides → pas d\'intro (rien à introduire)',
    (tester) async {
      await _pumpInline(tester, perspectives: const []);

      expect(find.textContaining(introSnippet), findsNothing);
    },
  );

  testWidgets('inline collapsé → pas d\'intro (body non rendu)', (
    tester,
  ) async {
    await _pumpInline(tester, perspectives: [_p('A')], isExpanded: false);

    expect(find.textContaining(introSnippet), findsNothing);
  });

  testWidgets('inline high divergence → phrase polarisation rendue', (
    tester,
  ) async {
    await _pumpInline(
      tester,
      perspectives: [
        _p('A'),
        _p('B', bias: 'right'),
      ],
      divergenceLevel: 'high',
    );

    expect(
      find.text('Forte polarisation dans le traitement de ce sujet'),
      findsOneWidget,
    );
  });
}
