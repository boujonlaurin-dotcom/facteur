import 'package:facteur/features/app_update/providers/app_update_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateInfo.isNewer', () {
    test('remote plus récent (même canal) -> true', () {
      expect(
        AppUpdateInfo.isNewer('beta-20260221-1430', 'beta-20260220-0900'),
        isTrue,
      );
      // même jour, heure plus tardive
      expect(
        AppUpdateInfo.isNewer('beta-20260221-1430', 'beta-20260221-0900'),
        isTrue,
      );
    });

    test('remote == local -> false', () {
      expect(
        AppUpdateInfo.isNewer('release-20260221-1430', 'release-20260221-1430'),
        isFalse,
      );
    });

    test('remote plus ancien -> false', () {
      expect(
        AppUpdateInfo.isNewer('beta-20260220-0900', 'beta-20260221-1430'),
        isFalse,
      );
    });

    test('canaux différents (incomparables) -> false', () {
      expect(
        AppUpdateInfo.isNewer('release-20260221-1430', 'beta-20260220-0900'),
        isFalse,
      );
      expect(
        AppUpdateInfo.isNewer('beta-20260221-1430', 'release-20260220-0900'),
        isFalse,
      );
    });

    test('format non conforme -> false', () {
      // semver
      expect(AppUpdateInfo.isNewer('1.0.3', '1.0.2'), isFalse);
      // remote malformé
      expect(AppUpdateInfo.isNewer('beta-2026-1430', 'beta-20260221-1430'),
          isFalse);
      // préfixe inconnu
      expect(
        AppUpdateInfo.isNewer('ios-beta-20260221-1430', 'beta-20260220-0900'),
        isFalse,
      );
    });

    test('local vide (dev build) -> false', () {
      expect(AppUpdateInfo.isNewer('beta-20260221-1430', ''), isFalse);
    });
  });
}
