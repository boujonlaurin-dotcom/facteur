import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/flux_continu/services/triage_preview_nudge_scheduler.dart';

/// Ce que ces tests gardent : un nudge d'apprentissage ne doit se faire
/// remarquer qu'une fois. Une fois par jour au plus, et plus jamais dès que
/// l'utilisateur a fait le geste — sinon l'indice devient du bruit sur une
/// carte qu'on regarde tous les matins.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  TriagePreviewNudgeScheduler build() => TriagePreviewNudgeScheduler(
        clock: () => now,
        prefs: SharedPreferences.getInstance,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Midi à Paris, bien après la bascule 07h30 : dayKey == ce jour-là.
    now = DateTime.utc(2026, 7, 18, 10);
  });

  test('autorise le nudge dans l\'état initial', () async {
    expect(await build().canTriggerNow(), isTrue);
  });

  test('une seule fois par jour', () async {
    final s = build();
    await s.recordTriggered();

    expect(await s.canTriggerNow(), isFalse);
    // Même plus tard dans la journée.
    now = now.add(const Duration(hours: 6));
    expect(await s.canTriggerNow(), isFalse);
  });

  test('reprend le lendemain', () async {
    final s = build();
    await s.recordTriggered();

    now = now.add(const Duration(days: 1));
    expect(await s.canTriggerNow(), isTrue);
  });

  test('le long-press réel éteint le nudge définitivement', () async {
    final s = build();
    await s.markDiscovered();

    expect(await s.canTriggerNow(), isFalse);
    // Le lendemain non plus : la découverte n'a pas de date d'expiration.
    now = now.add(const Duration(days: 1));
    expect(await s.canTriggerNow(), isFalse);
  });

  test('purge les clés des jours précédents', () async {
    final s = build();
    await s.recordTriggered();

    now = now.add(const Duration(days: 1));
    await s.recordTriggered();

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(kTriagePreviewNudgeShownPrefix))
        .toList();
    expect(keys, hasLength(1));
  });
}
