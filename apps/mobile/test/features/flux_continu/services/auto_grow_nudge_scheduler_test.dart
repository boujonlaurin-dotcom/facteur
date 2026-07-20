import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/flux_continu/services/auto_grow_nudge_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  AutoGrowNudgeScheduler build() => AutoGrowNudgeScheduler(
        clock: () => now,
        prefs: SharedPreferences.getInstance,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 7, 18, 9);
  });

  test('autorise un pulse dans l\'état initial', () async {
    expect(await build().canTriggerNow(), isTrue);
  });

  test('refuse tant que l\'espacement minimum n\'est pas écoulé', () async {
    final s = build();
    await s.recordTriggered();

    // Juste après → bloqué par l'espacement.
    expect(await s.canTriggerNow(), isFalse);

    // +89 min → toujours bloqué ; +90 min → autorisé de nouveau.
    now = now.add(const Duration(minutes: 89));
    expect(await s.canTriggerNow(), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(await s.canTriggerNow(), isTrue);
  });

  test('plafonne à $kAutoGrowDailyBudget pulses par jour', () async {
    final s = build();
    for (var i = 0; i < kAutoGrowDailyBudget; i++) {
      expect(await s.canTriggerNow(), isTrue, reason: 'pulse #$i doit passer');
      await s.recordTriggered();
      // Avance au-delà de l'espacement pour isoler la limite de budget.
      now = now.add(kAutoGrowMinSpacing + const Duration(minutes: 1));
    }
    // Budget épuisé pour le reste de la journée, même espacement respecté.
    expect(await s.canTriggerNow(), isFalse);
  });

  test('le compteur repart à zéro au changement de jour', () async {
    final s = build();
    for (var i = 0; i < kAutoGrowDailyBudget; i++) {
      await s.recordTriggered();
      now = now.add(kAutoGrowMinSpacing + const Duration(minutes: 1));
    }
    expect(await s.canTriggerNow(), isFalse);

    // Lendemain, même heure → nouvelle clé datée = budget frais.
    now = DateTime(2026, 7, 19, 9);
    expect(await s.canTriggerNow(), isTrue);
  });

  test('markDiscovered coupe définitivement le nudge', () async {
    final s = build();
    expect(await s.canTriggerNow(), isTrue);

    await s.markDiscovered();
    expect(await s.canTriggerNow(), isFalse);

    // Même le lendemain, une fois découvert, plus aucun pulse.
    now = DateTime(2026, 7, 20, 9);
    expect(await s.canTriggerNow(), isFalse);
  });
}
