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

  group('TourneeProgressService — rituel matinal (clés héritées)', () {
    test(
        'purgeOldPrefsKeys retire TOUTES les clés « rituel vu », jour courant '
        'inclus', () async {
      // Depuis que la Lettre ne gate plus L'Essentiel (décision PO 02/08/2026),
      // plus personne n'écrit ni ne lit ce flag : la purge est le seul chemin
      // qui reste, et elle doit vider le sac au lieu d'y laisser la clé du jour.
      final todayKey = TourneeProgressService.morningRitualPrefsKey(today);
      final oldKey = TourneeProgressService.morningRitualPrefsKey(yesterday);
      final svc = await service({todayKey: true, oldKey: true});

      await svc.purgeOldPrefsKeys(now: today);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(todayKey), isNull);
      expect(prefs.getBool(oldKey), isNull);
    });
  });

  group('TourneeProgressService — essentiel viewed', () {
    test('isEssentielViewedTodaySync defaults to false', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = TourneeProgressService(prefs: prefs);

      expect(service.isEssentielViewedTodaySync(), isFalse);
    });

    test('markEssentielViewedToday flips the sync flag for today', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = TourneeProgressService(prefs: prefs);

      await service.markEssentielViewedToday();

      expect(service.isEssentielViewedTodaySync(), isTrue);
    });

    test('hasBrowsedEssentielTodaySync reflects either flag', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = TourneeProgressService(prefs: prefs);

      expect(service.hasBrowsedEssentielTodaySync(), isFalse);

      await service.markEssentielViewedToday();

      expect(service.hasBrowsedEssentielTodaySync(), isTrue);
    });

    test('essentiel-viewed and closing-dismissed flags are independent',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = TourneeProgressService(prefs: prefs);

      await service.markEssentielViewedToday();

      expect(service.isEssentielViewedTodaySync(), isTrue);
      expect(service.isClosingDismissedTodaySync(), isFalse);

      await service.setClosingDismissedToday(true);

      expect(service.isClosingDismissedTodaySync(), isTrue);
      expect(service.isEssentielViewedTodaySync(), isTrue);
    });

    test('purgeOldPrefsKeys removes a previous day\'s key, keeps today\'s',
        () async {
      const oldKey = 'flux_continu_essentiel_viewed_2020-01-01';
      final today = TourneeProgressService.essentielViewedPrefsKey(
        DateTime.now(),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        oldKey: true,
        today: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final service = TourneeProgressService(prefs: prefs);

      await service.purgeOldPrefsKeys();

      final keys = prefs.getKeys();
      expect(keys, isNot(contains(oldKey)));
      expect(keys, contains(today));
    });
  });
}
