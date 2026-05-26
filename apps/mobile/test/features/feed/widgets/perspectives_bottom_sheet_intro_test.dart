import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

/// PR 6.1 — phrase d'intro pédagogique sous le titre « Couverture
/// médiatique », au-dessus de la bias bar. Affichée uniquement quand
/// `perspectives.isNotEmpty`.
Perspective _persp(String name) => Perspective(
      title: 'Titre pour $name',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '',
      biasStance: 'center',
    );

Future<void> _pumpSheet(
  WidgetTester tester, {
  required List<Perspective> perspectives,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 844,
            child: PerspectivesBottomSheet(
              perspectives: perspectives,
              biasDistribution: const {'center': 0},
              keywords: const [],
              contentId: 'test-content-id',
              sourceBiasStance: 'center',
              sourceName: 'Test',
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

  testWidgets('perspectives non vides → phrase d\'intro présente',
      (tester) async {
    await _pumpSheet(tester, perspectives: [_persp('Source-FR-1')]);

    expect(find.textContaining(introSnippet), findsOneWidget);
  });

  testWidgets('perspectives vides → phrase d\'intro absente (empty state)',
      (tester) async {
    await _pumpSheet(tester, perspectives: const []);

    expect(find.textContaining(introSnippet), findsNothing);
  });
}
