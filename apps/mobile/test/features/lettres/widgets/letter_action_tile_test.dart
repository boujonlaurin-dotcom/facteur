import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/lettres/models/letter.dart';
import 'package:facteur/features/lettres/widgets/letter_action_tile.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(
      backgroundColor: FacteurPalettes.light.backgroundPrimary,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

LetterAction _action(LetterActionStatus status) => LetterAction(
      id: 'add_5_sources',
      label: 'Ajouter 5 sources',
      help: 'Pour démarrer ton flux',
      status: status,
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('renders done state with strikethrough + check icon',
      (tester) async {
    await tester.pumpWidget(
      _wrap(LetterActionTile(action: _action(LetterActionStatus.done))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ajouter 5 sources'), findsOneWidget);
    expect(find.text('VALIDÉE · CACHET APPOSÉ'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('renders active state with status text', (tester) async {
    await tester.pumpWidget(
      _wrap(LetterActionTile(action: _action(LetterActionStatus.active))),
    );
    await tester.pumpAndSettle();
    expect(find.text('ÉTAPE EN COURS'), findsOneWidget);
  });

  testWidgets('renders todo state with waiting label', (tester) async {
    await tester.pumpWidget(
      _wrap(LetterActionTile(action: _action(LetterActionStatus.todo))),
    );
    await tester.pumpAndSettle();
    expect(find.text('EN ATTENTE'), findsOneWidget);
  });

  testWidgets('tap fires onTap callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(LetterActionTile(
      action: _action(LetterActionStatus.active),
      onTap: () => tapped++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(LetterActionTile));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}
