import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/shared/widgets/read_state_mark.dart';

/// La duplication de cette pastille en trois copies avait déjà produit un bug :
/// celle de la carte Essentiel codait `check` en dur, donc ne pouvait pas
/// afficher une complétion. Le choix de la variante ne vit plus qu'ici, piloté
/// par [ReadState].
void main() {
  Widget wrap(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      );

  IconData iconOf(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon)).icon!;

  testWidgets('unread → rien', (tester) async {
    await tester.pumpWidget(
      wrap(const ReadStateMark(color: Colors.green, state: ReadState.unread)),
    );
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('opened → coche verte + contour pointillé, pas de coche pleine',
      (tester) async {
    await tester.pumpWidget(
      wrap(const ReadStateMark(color: Colors.green, state: ReadState.opened)),
    );

    expect(iconOf(tester), PhosphorIcons.check(PhosphorIconsStyle.bold));
    // Coche verte (couleur du token), pas blanche → signal secondaire.
    expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.green);
    // Contour pointillé présent (CustomPaint du DashedRRectPainter).
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('partiallyRead → simple coche blanche pleine', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ReadStateMark(color: Colors.green, state: ReadState.partiallyRead),
      ),
    );

    expect(iconOf(tester), PhosphorIcons.check(PhosphorIconsStyle.bold));
    expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.white);
  });

  testWidgets('completed → double coche blanche', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ReadStateMark(color: Colors.green, state: ReadState.completed),
      ),
    );

    expect(iconOf(tester), PhosphorIcons.checks(PhosphorIconsStyle.bold));
    expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.white);
  });

  testWidgets('taille conservée entre les marches', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ReadStateMark(
          color: Colors.green,
          size: 18,
          state: ReadState.partiallyRead,
        ),
      ),
    );
    final read = tester.getSize(find.byType(ReadStateMark));

    await tester.pumpWidget(
      wrap(
        const ReadStateMark(
          color: Colors.green,
          size: 18,
          state: ReadState.completed,
        ),
      ),
    );

    expect(tester.getSize(find.byType(ReadStateMark)), read);
  });
}
