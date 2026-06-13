import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
    'inline expanded + perspectives non vides → intro derrière le bouton info',
    (tester) async {
      await _pumpInline(
        tester,
        perspectives: [
          _p('A'),
          _p('B', bias: 'left'),
        ],
      );

      expect(find.textContaining(introSnippet), findsNothing);

      await tester.tap(
        find.byIcon(PhosphorIcons.info(PhosphorIconsStyle.regular)).first,
      );
      await tester.pumpAndSettle();

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

  testWidgets('inline high divergence → badge polarisation rendu', (
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

    expect(find.text('POLARISÉ'), findsOneWidget);
    expect(find.textContaining('Forte polarisation'), findsNothing);
  });

  testWidgets('inline low divergence → badge traitements similaires rendu', (
    tester,
  ) async {
    await _pumpInline(
      tester,
      perspectives: [
        _p('A'),
        _p('B', bias: 'right'),
      ],
      divergenceLevel: 'low',
    );

    expect(find.text('TRAITEMENTS SIMILAIRES'), findsOneWidget);
  });
}
