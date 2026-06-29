import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Un mardi à midi (Europe/Paris ≈ UTC+2 en été), bien après la bascule 7h30 :
  // dayKey == ce jour-là.
  final today = DateTime.utc(2026, 6, 23, 12);
  final yesterday = DateTime.utc(2026, 6, 22, 12);

  Future<TourneeProgressService> service(Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    return TourneeProgressService(prefs: prefs);
  }

  group('TourneeProgressService — rituel matinal', () {
    test('isMorningRitualShownTodaySync : faux par défaut', () async {
      final svc = await service({});
      expect(svc.isMorningRitualShownTodaySync(now: today), isFalse);
    });

    test('vrai après setMorningRitualShownToday', () async {
      final svc = await service({});
      await svc.setMorningRitualShownToday(now: today);
      expect(svc.isMorningRitualShownTodaySync(now: today), isTrue);
      expect(await svc.loadMorningRitualShownForToday(now: today), isTrue);
    });

    test('clé jumelée au dayKey : un autre jour reste non-vu', () async {
      final svc = await service({});
      await svc.setMorningRitualShownToday(now: yesterday);
      expect(svc.isMorningRitualShownTodaySync(now: yesterday), isTrue);
      expect(svc.isMorningRitualShownTodaySync(now: today), isFalse);
    });

    test('purgeOldPrefsKeys retire les clés des jours passés, garde celle du jour',
        () async {
      final todayKey = TourneeProgressService.morningRitualPrefsKey(today);
      final oldKey = TourneeProgressService.morningRitualPrefsKey(yesterday);
      final svc = await service({todayKey: true, oldKey: true});

      await svc.purgeOldPrefsKeys(now: today);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(todayKey), isTrue, reason: 'la clé du jour survit');
      expect(prefs.getBool(oldKey), isNull, reason: 'la clé d\'hier est purgée');
    });

    test('isMorningRitualShownTodaySync sans prefs injecté → false (anti-flicker)',
        () {
      const svc = TourneeProgressService();
      expect(svc.isMorningRitualShownTodaySync(now: today), isFalse);
    });

    test('resetMorningRitualShown (QA) oublie toutes les clés, jour courant inclus',
        () async {
      final todayKey = TourneeProgressService.morningRitualPrefsKey(today);
      final oldKey = TourneeProgressService.morningRitualPrefsKey(yesterday);
      final svc = await service({todayKey: true, oldKey: true});

      await svc.resetMorningRitualShown();

      expect(svc.isMorningRitualShownTodaySync(now: today), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(todayKey), isNull);
      expect(prefs.getBool(oldKey), isNull);
    });
  });
}
