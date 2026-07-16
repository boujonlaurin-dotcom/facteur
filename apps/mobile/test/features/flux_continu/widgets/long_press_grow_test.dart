import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/flux_continu/widgets/long_press_grow.dart';

void main() {
  // Enfant hittable (couleur opaque) — un SizedBox nu n'absorbe pas le pointeur,
  // le long-press ne serait jamais reconnu.
  Widget wrap(Widget nudge) =>
      MaterialApp(home: Scaffold(body: Center(child: nudge)));

  Widget child() => Container(width: 100, height: 100, color: Colors.blue);

  /// `ScaleTransition` porté par le nudge (scopé pour ignorer ceux de MaterialApp).
  ScaleTransition scaleOf(WidgetTester tester) => tester.widget<ScaleTransition>(
        find.descendant(
          of: find.byType(LongPressGrowNudge),
          matching: find.byType(ScaleTransition),
        ),
      );

  testWidgets('long-press grows the child then settles back to 1.0',
      (tester) async {
    await tester.pumpWidget(wrap(LongPressGrowNudge(child: child())));

    // Au repos, échelle neutre.
    expect(scaleOf(tester).scale.value, 1.0);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Container)));
    await tester.pump(const Duration(milliseconds: 600)); // deadline long-press
    await tester.pump(const Duration(milliseconds: 80)); // mi-grow

    expect(scaleOf(tester).scale.value, greaterThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
    // Retour à 1.0 après l'animation.
    expect(scaleOf(tester).scale.value, closeTo(1.0, 0.001));
  });

  testWidgets('long-press fires onLongPress (analytics hook) exactly once',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(wrap(
      LongPressGrowNudge(onLongPress: () => count++, child: child()),
    ));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Container)));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(count, 1);
  });

  testWidgets(
      'a plain tap (below the long-press deadline) does not grow or fire',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(wrap(
      LongPressGrowNudge(onLongPress: () => count++, child: child()),
    ));

    await tester.tap(find.byType(Container));
    await tester.pump(const Duration(milliseconds: 80));

    expect(count, 0);
    expect(scaleOf(tester).scale.value, 1.0);
  });
}
