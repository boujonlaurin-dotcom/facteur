import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/lettres/models/letter.dart';
import 'package:facteur/features/lettres/widgets/letter_completion_overlay.dart';

Letter _archived() => Letter(
      id: 'letter_1',
      letterNum: '01',
      title: 'Tes premières sources',
      message: 'msg',
      signature: 'Le Facteur',
      status: LetterStatus.archived,
      actions: const [],
      completedActions: const [],
      progress: 1.0,
      startedAt: DateTime.utc(2026, 5, 1),
      archivedAt: DateTime.utc(2026, 5, 3),
    );

Widget _wrap(Widget child) {
  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(path: '/test', builder: (_, __) => child),
      GoRoute(path: '/lettres', builder: (_, __) => const SizedBox.shrink()),
    ],
  );
  return MaterialApp.router(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    routerConfig: router,
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('renders cachet, title and CTAs after animation', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(_wrap(LetterCompletionOverlay(
      letter: _archived(),
      onDismiss: () => dismissed++,
    )));
    await tester.pumpAndSettle();

    expect(find.text('CLASSÉE'), findsOneWidget);
    expect(find.text('Lettre classée.'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(dismissed, 0);
  });

  testWidgets('Continuer button calls onDismiss', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(_wrap(LetterCompletionOverlay(
      letter: _archived(),
      onDismiss: () => dismissed++,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });
}
