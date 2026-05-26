import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/widgets/diff_title.dart';

/// PR 6.1 — bump typo pour les key spans à `weight == 1.0`.
///
/// Le Text enfant du WidgetSpan d'un key chunk doit avoir
/// `fontWeight = FontWeight.w700` quand `weight = 1.0`, et `FontWeight.w400`
/// sinon (incluant null pour rétrocompat). animateIn=false → cascade
/// terminée immédiatement.
void main() {
  Widget host(DiffTitle child) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  /// Récupère le fontWeight du premier Text descendant du Container du wash.
  /// On distingue le Container du wash via son borderRadius (signature du
  /// key span dans DiffTitle).
  FontWeight? keyTextFontWeight(WidgetTester tester) {
    final containers = tester.widgetList<Container>(find.byType(Container));
    for (final c in containers) {
      final dec = c.decoration;
      if (dec is BoxDecoration && dec.borderRadius != null) {
        final textFinder = find.descendant(
          of: find.byWidget(c),
          matching: find.byType(Text),
        );
        if (textFinder.evaluate().isNotEmpty) {
          return tester.widget<Text>(textFinder.first).style?.fontWeight;
        }
      }
    }
    return null;
  }

  DiffTitle buildDiff({double? weight}) => DiffTitle(
        title: 'Macron annonce une réforme',
        highlightSpans: [
          HighlightSpan(
            start: 7,
            end: 14,
            text: 'annonce',
            bias: 'right',
            weight: weight,
          ),
        ],
        sharedTokens: const [],
        biasColor: Colors.red,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      );

  group('DiffTitle — strong editorial fontWeight bump', () {
    testWidgets('weight = 1.0 → fontWeight.w700', (tester) async {
      await tester.pumpWidget(host(buildDiff(weight: 1.0)));
      await tester.pumpAndSettle();
      expect(keyTextFontWeight(tester), FontWeight.w700);
    });

    testWidgets('weight = 0.5 → fontWeight.w400 (pas de bump)', (tester) async {
      await tester.pumpWidget(host(buildDiff(weight: 0.5)));
      await tester.pumpAndSettle();
      expect(keyTextFontWeight(tester), FontWeight.w400);
    });

    testWidgets('weight = 0.25 → fontWeight.w400', (tester) async {
      await tester.pumpWidget(host(buildDiff(weight: 0.25)));
      await tester.pumpAndSettle();
      expect(keyTextFontWeight(tester), FontWeight.w400);
    });

    testWidgets('weight = null → fontWeight.w400 (rétrocompat)',
        (tester) async {
      await tester.pumpWidget(host(buildDiff(weight: null)));
      await tester.pumpAndSettle();
      expect(keyTextFontWeight(tester), FontWeight.w400);
    });
  });
}
