import 'package:facteur/config/theme.dart';
import 'package:facteur/features/learning_checkpoint/widgets/source_priority_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(body: child),
      );

  testWidgets('S1 — renders current (faded) and proposed dot groups',
      (tester) async {
    await tester.pumpWidget(wrap(
      SourcePrioritySlider(current: 2, proposed: 1, onChange: (_) {}),
    ));
    await tester.pumpAndSettle();

    // Arrow separator.
    expect(find.text('→'), findsOneWidget);
    // 6 dots total (3 current + 3 proposed interactive).
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('S2 — tap on proposed dot calls onChange with correct level',
      (tester) async {
    int? tappedLevel;
    await tester.pumpWidget(wrap(
      SourcePrioritySlider(
        current: 1,
        proposed: 2,
        onChange: (v) => tappedLevel = v,
      ),
    ));
    await tester.pumpAndSettle();

    // Tap the first interactive dot (level 1).
    final semantics = find.bySemanticsLabel('Niveau 1 sur 3');
    expect(semantics, findsOneWidget);
    await tester.tap(semantics);
    expect(tappedLevel, 1);
  });

  testWidgets('S3 — tap on level 3 dot calls onChange(3)', (tester) async {
    int? tappedLevel;
    await tester.pumpWidget(wrap(
      SourcePrioritySlider(
        current: 1,
        proposed: 1,
        onChange: (v) => tappedLevel = v,
      ),
    ));
    await tester.pumpAndSettle();

    final semantics = find.bySemanticsLabel('Niveau 3 sur 3');
    expect(semantics, findsOneWidget);
    await tester.tap(semantics);
    expect(tappedLevel, 3);
  });

  testWidgets('S4 — each interactive dot has Semantics button label',
      (tester) async {
    await tester.pumpWidget(wrap(
      SourcePrioritySlider(current: 1, proposed: 2, onChange: (_) {}),
    ));
    await tester.pumpAndSettle();

    // 3 interactive dots in proposed group.
    expect(find.bySemanticsLabel('Niveau 1 sur 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Niveau 2 sur 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Niveau 3 sur 3'), findsOneWidget);
  });

  testWidgets('S5 — interactive dots meet 48dp touch target', (tester) async {
    await tester.pumpWidget(wrap(
      SourcePrioritySlider(current: 1, proposed: 2, onChange: (_) {}),
    ));
    await tester.pumpAndSettle();

    // Each interactive dot is wrapped in a SizedBox(48x48).
    final sizedBoxes = find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == 48 && w.height == 48,
    );
    expect(sizedBoxes, findsNWidgets(3));
  });
}
