import 'package:facteur/config/theme.dart';
import 'package:facteur/shared/widgets/glass_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Résout la couleur de fond effective du pill : le `DecoratedBox` qui porte à
/// la fois une `color` non-null ET une bordure (l'arête extérieure sombre) —
/// c'est celui qui reçoit `fillColor`.
Color _fillColorOf(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
  for (final box in boxes) {
    final deco = box.decoration;
    if (deco is BoxDecoration && deco.color != null && deco.border != null) {
      return deco.color!;
    }
  }
  fail('Aucun DecoratedBox de fond trouvé dans le GlassPill');
}

Future<Color> _pumpAndReadFill(WidgetTester tester, {Color? fillTint}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: GlassPill(
            fillTint: fillTint,
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    ),
  );
  return _fillColorOf(tester);
}

void main() {
  group('GlassPill.fillTint', () {
    testWidgets('sans fillTint → fond inchangé (aucune régression call-sites)',
        (tester) async {
      final fill = await _pumpAndReadFill(tester);
      // Fond quasi-opaque dérivé du token clair (alpha 0.98), aucune teinte.
      expect(fill.a, closeTo(0.98, 0.001));
    });

    testWidgets('avec fillTint success → fond teinté (alphaBlend)',
        (tester) async {
      const tint = Color(0x2427AE60); // success @ ~14% alpha
      final base = await _pumpAndReadFill(tester);
      final tinted = await _pumpAndReadFill(tester, fillTint: tint);

      // Le fond change et bascule vers le vert : l'écart vert-rouge grimpe
      // (le fond crème est légèrement rougeâtre, la teinte success l'inverse).
      expect(tinted, isNot(equals(base)));
      expect(tinted.g - tinted.r, greaterThan(base.g - base.r));
      // Le fond reste opaque (alphaBlend sur un fond déjà à alpha 0.98).
      expect(tinted.a, greaterThanOrEqualTo(base.a));
    });
  });
}
