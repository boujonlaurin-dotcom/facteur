import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/shared/widgets/read_state_mark.dart';

/// La duplication de cette pastille en trois copies avait déjà produit un bug :
/// celle de la carte Essentiel codait `check` en dur, donc ne pouvait pas
/// afficher une complétion. Le choix `check`/`checks` ne vit plus qu'ici.
void main() {
  Widget wrap(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      );

  IconData iconOf(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon)).icon!;

  testWidgets('ouvert seulement → simple coche', (tester) async {
    await tester.pumpWidget(wrap(const ReadStateMark(color: Colors.green)));

    expect(iconOf(tester), PhosphorIcons.check(PhosphorIconsStyle.bold));
  });

  testWidgets('lu jusqu\'au bout → double coche', (tester) async {
    await tester.pumpWidget(
      wrap(const ReadStateMark(color: Colors.green, isCompleted: true)),
    );

    expect(iconOf(tester), PhosphorIcons.checks(PhosphorIconsStyle.bold));
  });

  testWidgets('même taille et même couleur dans les deux états',
      (tester) async {
    Size sizeOf(Finder f) => tester.getSize(f);

    await tester.pumpWidget(
      wrap(const ReadStateMark(color: Colors.green, size: 18)),
    );
    final open = sizeOf(find.byType(ReadStateMark));
    final openColor = tester.widget<Icon>(find.byType(Icon)).color;

    await tester.pumpWidget(
      wrap(
        const ReadStateMark(
          color: Colors.green,
          size: 18,
          isCompleted: true,
        ),
      ),
    );

    // Un chevron de plus, rien d'autre : aucune surface où lire un reproche.
    expect(sizeOf(find.byType(ReadStateMark)), open);
    expect(tester.widget<Icon>(find.byType(Icon)).color, openColor);
  });
}
