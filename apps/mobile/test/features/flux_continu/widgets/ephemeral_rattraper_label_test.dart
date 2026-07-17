import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/ephemeral_rattraper_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const dayKey = '2026-07-17';

  /// Monte le nudge dans un MaterialApp minimal. [disableAnimations] simule le
  /// réglage d'accessibilité « réduire les animations ».
  Future<void> pumpLabel(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: const Scaffold(
            body: Center(child: EphemeralRattraperLabel(dayKey: dayKey)),
          ),
        ),
      ),
    );
  }

  /// Opacité courante du FadeTransition du nudge (0 = masqué, 1 = révélé).
  double fadeOpacity(WidgetTester tester) {
    final ft = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(EphemeralRattraperLabel),
        matching: find.byType(FadeTransition),
      ),
    );
    return ft.opacity.value;
  }

  testWidgets(
      'séquence : masqué au montage → fondu-in après ~1 s → fondu-out après 2 s',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpLabel(tester);
    await tester.pump(); // résout la lecture prefs async

    // Masqué juste après le montage (le Timer d'entrée n'a pas encore fait feu).
    expect(fadeOpacity(tester), 0.0);

    // t ≈ 1 s : le fondu-in démarre ; +300 ms le termine (durée 250 ms).
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fadeOpacity(tester), 1.0);
    expect(find.text('Rattraper ?'), findsOneWidget);

    // Tient 2 s puis fondu-out : +2 s (déclenche reverse) puis +300 ms.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fadeOpacity(tester), 0.0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('gate 1×/jour : prefs déjà à dayKey → jamais révélé',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{kRattraperNudgeLastShownPrefsKey: dayKey},
    );
    await pumpLabel(tester);
    await tester.pump(); // résout la lecture prefs → early-return

    // Même après la fenêtre où le nudge se serait joué, l'opacité reste à 0.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fadeOpacity(tester), 0.0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('reduce-motion → aucune animation (le point rouge porte le signal)',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpLabel(tester, disableAnimations: true);
    await tester.pump();

    // Rien n'est rendu (SizedBox.shrink) : ni FadeTransition propre au nudge,
    // ni le texte. (On scope aux descendants : les transitions de route
    // MaterialPageRoot ne comptent pas.)
    expect(
      find.descendant(
        of: find.byType(EphemeralRattraperLabel),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(find.text('Rattraper ?'), findsNothing);

    // Même en avançant le temps, aucune révélation.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Rattraper ?'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
