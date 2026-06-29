import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/flux_continu/screens/morning_ritual_screen.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Faux notifier serein (pas de Supabase/réseau, contrairement au vrai dont le
/// provider monte `authStateProvider` → `Supabase.instance`) : état contrôlé +
/// compteur de toggles. L'override par défaut de [_wrap] le pose en
/// `isLoading:false` (bouton actif).
class _FakeSereinNotifier extends SereinToggleNotifier {
  _FakeSereinNotifier(super.ref, {bool enabled = false, bool loading = false}) {
    state = SereinToggleState(enabled: enabled, isLoading: loading);
  }

  int toggleCalls = 0;

  @override
  Future<void> toggle() async {
    toggleCalls++;
    state = state.copyWith(enabled: !state.enabled);
  }
}

Widget _wrap(
  Widget child, {
  _FakeSereinNotifier Function(Ref ref)? serein,
}) {
  final create = serein ?? ((Ref ref) => _FakeSereinNotifier(ref));
  return ProviderScope(
    overrides: [sereinToggleProvider.overrideWith(create)],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(body: child),
    ),
  );
}

/// Surface verticale généreuse : le rituel a gagné le bloc « rewind » + le CTA
/// serein → évite un overflow dans la surface test par défaut (800×600).
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
      _useTallSurface(tester);
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
      _useTallSurface(tester);
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

    testWidgets('tap sur l\'enveloppe déclenche l\'ouverture', (tester) async {
      _useTallSurface(tester);
      var opened = 0;
      await tester.pumpWidget(_wrap(
        MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: const [],
          reduceMotion: true,
          onOpen: () => opened++,
          onPersonalize: () {},
        ),
      ));

      // L'enveloppe (unique SvgPicture du corps) est désormais cliquable. Le
      // GestureDetector est un ancêtre du SvgPicture → warnIfMissed superflu.
      await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400)); // laisse le « pop »
      expect(opened, 1);
    });

    testWidgets('peuplement : chips arrivant en 2 temps finissent visibles', (
      tester,
    ) async {
      _useTallSurface(tester);
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

    testWidgets('expose l\'accès « Remonter le temps » (timeline complète)',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(
        MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: const [],
          reduceMotion: true,
          onOpen: () {},
          onPersonalize: () {},
        ),
      ));

      // Repli accessible (clavier/lecteur d'écran) au swipe horizontal du rituel.
      expect(find.text('Remonter le temps'), findsOneWidget);
    });

    testWidgets('_SereinCta : copie exacte + tap → toggle + snackbar',
        (tester) async {
      _useTallSurface(tester);
      _FakeSereinNotifier? captured;
      await tester.pumpWidget(_wrap(
        MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: const [],
          reduceMotion: true,
          onOpen: () {},
          onPersonalize: () {},
        ),
        serein: (ref) => captured = _FakeSereinNotifier(ref),
      ));

      // Copie exacte (sans em-dash, cf. règle PO).
      expect(
        find.text('Pas d\'humeur pour les news difficiles ?'),
        findsOneWidget,
      );
      expect(find.text('Active ton mode serein'), findsOneWidget);

      await tester.tap(find.text('Active ton mode serein'));
      await tester.pump(); // exécute le toggle (await) + planifie le snackbar
      await tester.pump(); // insère le snackbar

      expect(captured, isNotNull);
      expect(captured!.toggleCalls, 1);
      expect(captured!.state.enabled, isTrue);
      expect(find.text('Mode serein activé'), findsOneWidget);

      // Purge le timer d'auto-dismiss du snackbar (sinon « pending timer »).
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('_SereinCta : bouton désactivé tant que la pref charge',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(
        MorningRitualContent(
          dateLabel: 'mercredi 27 mai',
          entries: const [],
          reduceMotion: true,
          onOpen: () {},
          onPersonalize: () {},
        ),
        serein: (ref) => _FakeSereinNotifier(ref, loading: true),
      ));

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Active ton mode serein'),
      );
      expect(button.onPressed, isNull);
    });
  });
}
