import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/flux_continu/widgets/auto_grow_pulse.dart';

void main() {
  Widget wrap(Widget pulse) =>
      MaterialApp(home: Scaffold(body: Center(child: pulse)));

  Widget child() => Container(width: 100, height: 100, color: Colors.blue);

  ScaleTransition scaleOf(WidgetTester tester) => tester.widget<ScaleTransition>(
        find.descendant(
          of: find.byType(AutoGrowPulse),
          matching: find.byType(ScaleTransition),
        ),
      );

  testWidgets('idle (null token) keeps the child at neutral scale 1.0',
      (tester) async {
    await tester.pumpWidget(wrap(AutoGrowPulse(child: child())));
    expect(scaleOf(tester).scale.value, 1.0);

    // Aucun geste ne doit déclencher l'animation : le widget est déclaratif.
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Container)));
    await tester.pump(const Duration(milliseconds: 800));
    expect(scaleOf(tester).scale.value, 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a new non-null playToken grows the child then settles to 1.0',
      (tester) async {
    await tester.pumpWidget(
      wrap(const AutoGrowPulse(playToken: null, child: SizedBox())),
    );

    // Rebuild avec un token non-null → l'animation démarre.
    await tester.pumpWidget(
      wrap(AutoGrowPulse(playToken: 1, child: child())),
    );
    await tester.pump(const Duration(milliseconds: 80)); // mi-grow
    expect(scaleOf(tester).scale.value, greaterThan(1.0));

    await tester.pumpAndSettle();
    expect(scaleOf(tester).scale.value, closeTo(1.0, 0.001));
  });

  testWidgets('the same token value does not replay the animation',
      (tester) async {
    await tester.pumpWidget(wrap(AutoGrowPulse(playToken: 7, child: child())));
    await tester.pumpAndSettle();
    expect(scaleOf(tester).scale.value, closeTo(1.0, 0.001));

    // Rebuild avec le MÊME token → pas de rejeu (didUpdateWidget no-op).
    await tester.pumpWidget(wrap(AutoGrowPulse(playToken: 7, child: child())));
    await tester.pump(const Duration(milliseconds: 80));
    expect(scaleOf(tester).scale.value, 1.0);
  });

  testWidgets('a changed token value replays the animation', (tester) async {
    await tester.pumpWidget(wrap(AutoGrowPulse(playToken: 1, child: child())));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(AutoGrowPulse(playToken: 2, child: child())));
    await tester.pump(const Duration(milliseconds: 80));
    expect(scaleOf(tester).scale.value, greaterThan(1.0));
    await tester.pumpAndSettle();
  });
}
