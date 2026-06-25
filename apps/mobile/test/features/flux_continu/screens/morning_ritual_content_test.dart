import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/screens/morning_ritual_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(body: child),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('MorningRitualContent', () {
    testWidgets('greeting + date affichés instantanément, sans spinner', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(
        MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: const [],
          editionReady: false,
          reduceMotion: true,
          onOpen: () {},
        ),
      ));

      expect(find.text('Bonjour.'), findsOneWidget);
      expect(
        find.text('Ton édition du mercredi 27 mai vient d\'arriver.'),
        findsOneWidget,
      );
      // Promesse « no loading » : jamais de spinner au repos.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('édition prête : sommaire révélé + CTA interactif', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(
        const MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: ['Technologie', 'Actus du jour', 'Mot du jour'],
          editionReady: true,
          reduceMotion: true,
          onOpen: _noop,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Technologie   ·   Actus du jour   ·   Mot du jour'),
        findsOneWidget,
      );
      expect(find.text('Ouvrir l\'édition'), findsOneWidget);

      // Le sommaire est interactif (gate ouvert) dès que l'édition est prête.
      final gate = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey('morning-summary-gate')),
      );
      expect(gate.ignoring, isFalse);
    });

    testWidgets('édition pas prête : sommaire masqué + non interactif', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(
        const MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: ['Technologie'],
          editionReady: false,
          reduceMotion: true,
          onOpen: _noop,
        ),
      ));

      // Greeting toujours visible, mais le sommaire est verrouillé (gate fermé).
      expect(find.text('Bonjour.'), findsOneWidget);
      final gate = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey('morning-summary-gate')),
      );
      expect(gate.ignoring, isTrue);

      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0.0);
    });
  });
}

void _noop() {}
