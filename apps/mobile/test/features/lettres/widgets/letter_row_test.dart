import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/lettres/models/letter.dart';
import 'package:facteur/features/lettres/widgets/letter_row.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(
      backgroundColor: FacteurPalettes.light.backgroundPrimary,
      body: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

Letter _letter({
  required LetterStatus status,
  String id = 'letter_1',
  String num = '01',
  double progress = 0.5,
  int totalActions = 4,
  int doneActions = 2,
}) {
  final actions = <LetterAction>[];
  for (var i = 0; i < totalActions; i++) {
    actions.add(LetterAction(
      id: 'a$i',
      label: 'Action $i',
      help: '',
      status: i < doneActions
          ? LetterActionStatus.done
          : (i == doneActions && status == LetterStatus.active
              ? LetterActionStatus.active
              : LetterActionStatus.todo),
    ));
  }
  return Letter(
    id: id,
    letterNum: num,
    title: 'Tes premières sources',
    message: 'msg',
    signature: 'Le Facteur',
    status: status,
    actions: actions,
    completedActions: List.generate(doneActions, (i) => 'a$i'),
    progress: progress,
    startedAt: DateTime.utc(2026, 5, 2),
    archivedAt: status == LetterStatus.archived
        ? DateTime.utc(2026, 5, 1)
        : null,
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('active row shows EN COURS pill + progress', (tester) async {
    await tester.pumpWidget(
      _wrap(LetterRow(letter: _letter(status: LetterStatus.active))),
    );
    await tester.pumpAndSettle();
    expect(find.text('EN COURS'), findsOneWidget);
    expect(find.text('Tes premières sources'), findsOneWidget);
    expect(find.text('2/4'), findsOneWidget);
  });

  testWidgets('upcoming row shows À VENIR pill', (tester) async {
    await tester.pumpWidget(
      _wrap(LetterRow(letter: _letter(status: LetterStatus.upcoming))),
    );
    await tester.pumpAndSettle();
    expect(find.text('À VENIR'), findsOneWidget);
  });

  testWidgets('archived row shows CLASSÉE pill', (tester) async {
    await tester.pumpWidget(
      _wrap(LetterRow(letter: _letter(status: LetterStatus.archived))),
    );
    await tester.pumpAndSettle();
    expect(find.text('CLASSÉE'), findsOneWidget);
  });

  testWidgets('tap fires onTap callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(LetterRow(
      letter: _letter(status: LetterStatus.active),
      onTap: () => tapped++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(LetterRow));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}
