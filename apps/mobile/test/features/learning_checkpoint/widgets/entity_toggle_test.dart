import 'package:facteur/config/theme.dart';
import 'package:facteur/features/learning_checkpoint/widgets/entity_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(body: child),
      );

  testWidgets('E1 — mute kind renders "Masquer"', (tester) async {
    await tester.pumpWidget(wrap(
      EntityToggle(
        kind: EntityToggleKind.mute,
        preActive: true,
        onChange: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Masquer'), findsOneWidget);
  });

  testWidgets('E2 — follow kind renders "Suivre"', (tester) async {
    await tester.pumpWidget(wrap(
      EntityToggle(
        kind: EntityToggleKind.follow,
        preActive: true,
        onChange: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Suivre'), findsOneWidget);
  });

  testWidgets('E3 — tap toggles and calls onChange with inverted value',
      (tester) async {
    bool? received;
    await tester.pumpWidget(wrap(
      EntityToggle(
        kind: EntityToggleKind.mute,
        preActive: true,
        onChange: (v) => received = v,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Masquer'));
    expect(received, false);
  });

  testWidgets('E4 — preActive=false calls onChange(true) on tap',
      (tester) async {
    bool? received;
    await tester.pumpWidget(wrap(
      EntityToggle(
        kind: EntityToggleKind.follow,
        preActive: false,
        onChange: (v) => received = v,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivre'));
    expect(received, true);
  });

  testWidgets('E5 — Semantics: toggled state announced', (tester) async {
    await tester.pumpWidget(wrap(
      EntityToggle(
        kind: EntityToggleKind.mute,
        preActive: true,
        onChange: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(find.bySemanticsLabel('Masquer'));
    expect(semantics.hasFlag(SemanticsFlag.isToggled), isTrue);
  });

  testWidgets('E6 — meets 48dp minimum height', (tester) async {
    await tester.pumpWidget(wrap(
      EntityToggle(
        kind: EntityToggleKind.mute,
        preActive: true,
        onChange: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    final constrainedBox = find.byWidgetPredicate(
      (w) =>
          w is ConstrainedBox &&
          w.constraints.minHeight == 48,
    );
    expect(constrainedBox, findsOneWidget);
  });
}
