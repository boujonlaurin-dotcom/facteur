import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/lettres/models/facteur_grade.dart';
import 'package:facteur/features/lettres/widgets/grade_ladder.dart';

Widget _wrap(FacteurGrade grade) => MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(body: GradeLadder(grade: grade)),
    );

FacteurGrade _grade(int level) => FacteurGrade(
      level: level,
      title: facteurLadder[level - 1].title,
      completedLetters: level - 1,
      nextLevelAt: level < facteurLadder.length ? level : null,
      globalProgress: 0,
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('renders all 6 grade titles', (tester) async {
    await tester.pumpWidget(_wrap(_grade(3)));
    await tester.pump();

    for (final entry in facteurLadder) {
      expect(find.text(entry.title), findsOneWidget);
    }
  });

  testWidgets('ladder is non-interactive (no InkWell)', (tester) async {
    await tester.pumpWidget(_wrap(_grade(3)));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(GradeLadder),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('future grades are dimmed via Opacity', (tester) async {
    // Au niveau 1, les 5 grades supérieurs sont verrouillés/grisés.
    await tester.pumpWidget(_wrap(_grade(1)));
    await tester.pump();

    final opacities = tester
        .widgetList<Opacity>(find.descendant(
          of: find.byType(GradeLadder),
          matching: find.byType(Opacity),
        ))
        .toList();
    expect(opacities.length, 5);
  });
}
