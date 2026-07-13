import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
