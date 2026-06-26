import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/screens/morning_ritual_screen.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
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
    EditionSummaryEntry entry(String label, {bool isVeille = false}) =>
        EditionSummaryEntry(
          label: label,
          accent: const Color(0xFF2C3E50),
          isVeille: isVeille,
        );

    testWidgets('greeting + date affichés, sans spinner', (tester) async {
      await tester.pumpWidget(_wrap(
        MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: const [],
          reduceMotion: true,
          onOpen: () {},
          onPersonalize: () {},
        ),
      ));

      expect(find.text('Salut,'), findsOneWidget);
      expect(
        find.text('Ton essentiel du mercredi 27 mai t\'attend.'),
        findsOneWidget,
      );
      // Phrase grisée d'intro (remplace l'ancien kicker orange + pointillés).
      expect(find.text('Tu y trouveras le meilleur de...'), findsOneWidget);
      expect(find.text('L\'ESSENTIEL DU JOUR'), findsNothing);
      // Promesse « no loading » : jamais de spinner au repos.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('reduceMotion : chips + CTA visibles immédiatement', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(
        MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: [
            entry('Technologie'),
            entry('Actus du jour'),
            entry('Mot du jour'),
          ],
          reduceMotion: true,
          onOpen: () {},
          onPersonalize: () {},
        ),
      ));
      // Un seul pump suffit (pas de stagger en reduceMotion).
      await tester.pump();

      expect(find.text('Technologie'), findsOneWidget);
      expect(find.text('Actus du jour'), findsOneWidget);
      expect(find.text('Mot du jour'), findsOneWidget);
      // CTA remplacé par l'indice « glisse vers le haut ».
      expect(find.text('Glisse vers le haut'), findsOneWidget);
    });

    testWidgets('peuplement : chips arrivant en 2 temps finissent visibles', (
      tester,
    ) async {
      final notifier = ValueNotifier<List<EditionSummaryEntry>>([
        entry('Technologie'),
      ]);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(_wrap(
        ValueListenableBuilder<List<EditionSummaryEntry>>(
          valueListenable: notifier,
          builder: (context, entries, _) => MorningRitualContent(
            dateLabel: 'mercredi 27 mai',
            entries: entries,
            reduceMotion: false,
            onOpen: () {},
            onPersonalize: () {},
          ),
        ),
      ));

      // 1re chip révélée tout de suite (cadence régulière côté pompe). Pas de
      // `pumpAndSettle` ici : l'indice « glisse vers le haut » boucle son nudge.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Technologie'), findsOneWidget);

      // 2e temps : de nouvelles sections arrivent → elles se peuplent une à une
      // au rythme de la pompe (~500 ms/chip), pas en salve.
      notifier.value = [
        entry('Technologie'),
        entry('Actus du jour'),
        entry('Bonnes Nouvelles'),
      ];
      await tester.pump(); // applique le didUpdateWidget
      await tester.pump(const Duration(milliseconds: 600)); // Actus
      await tester.pump(const Duration(milliseconds: 600)); // Bonnes Nouvelles

      expect(find.text('Technologie'), findsOneWidget);
      expect(find.text('Actus du jour'), findsOneWidget);
      expect(find.text('Bonnes Nouvelles'), findsOneWidget);

      // Laisse la pompe révéler l'engrenage et se mettre au repos (aucun timer
      // en attente à la fin du test).
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
