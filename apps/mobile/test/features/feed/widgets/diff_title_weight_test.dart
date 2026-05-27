import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/widgets/diff_title.dart';

/// PR 6.1 — re-mapping discret de l'opacité du surlignage par `weight` LLM.
///
/// Le surlignage du key span (Container avec BoxDecoration colorée) suit un
/// mapping discret nettement contrasté, avec floor visible. animateIn=false
/// → t=1.
///
/// Spec :
///   weight = 1.0    → alpha = 0.30 (max)
///   weight = 0.5    → alpha = 0.20
///   weight = 0.25   → alpha = 0.12 (floor lisible)
///   weight = null   → alpha = 0.22 (fallback rétrocompat, sans modulation)
void main() {
  Widget host(DiffTitle child) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  /// Récupère l'alpha appliqué à la couleur du Container du key span.
  /// On suppose un seul Container dans l'arbre — c'est le wash du key.
  double? keyWashAlpha(WidgetTester tester) {
    final containers = tester.widgetList<Container>(find.byType(Container));
    for (final c in containers) {
      final dec = c.decoration;
      if (dec is BoxDecoration && dec.color != null) {
        final col = dec.color!;
        // Le Container du wash a une couleur dérivée de biasColor (red ici).
        // On le distingue des autres Container vides en filtrant sur "a une
        // couleur non-transparente et un borderRadius".
        if (dec.borderRadius != null) {
          // alpha est dans [0,1] en double API moderne (Color.a) ou /255 sinon.
          return col.a;
        }
      }
    }
    return null;
  }

  group('DiffTitle — weight modulation', () {
    testWidgets('weight = 1.0 → alpha ≈ 0.30', (tester) async {
      await tester.pumpWidget(host(DiffTitle(
        title: 'Macron annonce une réforme',
        highlightSpans: const [
          HighlightSpan(
            start: 7,
            end: 14,
            text: 'annonce',
            bias: 'right',
            weight: 1.0,
          ),
        ],
        sharedTokens: const [],
        biasColor: Colors.red,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      )));
      await tester.pumpAndSettle();

      final alpha = keyWashAlpha(tester);
      expect(alpha, isNotNull);
      expect(alpha!, closeTo(0.30, 0.005));
    });

    testWidgets('weight = 0.5 → alpha ≈ 0.20', (tester) async {
      await tester.pumpWidget(host(DiffTitle(
        title: 'Macron annonce une réforme',
        highlightSpans: const [
          HighlightSpan(
            start: 7,
            end: 14,
            text: 'annonce',
            bias: 'right',
            weight: 0.5,
          ),
        ],
        sharedTokens: const [],
        biasColor: Colors.red,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      )));
      await tester.pumpAndSettle();

      final alpha = keyWashAlpha(tester);
      expect(alpha, isNotNull);
      expect(alpha!, closeTo(0.20, 0.005));
    });

    testWidgets('weight = 0.25 → alpha ≈ 0.12', (tester) async {
      await tester.pumpWidget(host(DiffTitle(
        title: 'Macron annonce une réforme',
        highlightSpans: const [
          HighlightSpan(
            start: 7,
            end: 14,
            text: 'annonce',
            bias: 'right',
            weight: 0.25,
          ),
        ],
        sharedTokens: const [],
        biasColor: Colors.red,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      )));
      await tester.pumpAndSettle();

      final alpha = keyWashAlpha(tester);
      expect(alpha, isNotNull);
      expect(alpha!, closeTo(0.12, 0.005));
    });

    testWidgets('weight = null → alpha ≈ 0.22 (rétrocompat)', (tester) async {
      // C'est le cas pre-PR 5 : l'API ne renvoie pas weight. Le fallback (?? 1.0)
      // garantit que le rendu est identique à l'avant-PR 6 (alpha = 0.22).
      await tester.pumpWidget(host(DiffTitle(
        title: 'Macron annonce une réforme',
        highlightSpans: const [
          HighlightSpan(start: 7, end: 14, text: 'annonce', bias: 'right'),
        ],
        sharedTokens: const [],
        biasColor: Colors.red,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      )));
      await tester.pumpAndSettle();

      final alpha = keyWashAlpha(tester);
      expect(alpha, isNotNull);
      expect(alpha!, closeTo(0.22, 0.005));
    });
  });
}
