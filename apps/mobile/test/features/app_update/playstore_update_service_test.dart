import 'package:facteur/features/app_update/services/playstore_update_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// La suite tourne sur l'hôte (non-Android) sans `--dart-define=PLAYSTORE_BUILD`,
/// donc `checkAndStart()` court-circuite AVANT tout appel au canal natif
/// `in_app_update` (qui lèverait un MissingPluginException). On valide ici la
/// propriété de sûreté cœur du service : ne jamais lever, ne jamais bloquer.
/// Le routage immediate/flexible dépend du canal natif Play et se teste sur un
/// track de test Play Console (cf. maintenance-playstore-in-app-updates.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayStoreUpdateService.checkAndStart', () {
    test('no-op silencieux hors flavor playstore (jamais d\'exception)', () async {
      final service = PlayStoreUpdateService();
      // Hôte non-Android + isPlayStoreBuild=false → retour anticipé, pas de
      // MissingPluginException remontée.
      await expectLater(service.checkAndStart(), completes);
    });

    test('appels répétés restent inoffensifs (garde anti-ré-entrance)', () async {
      final service = PlayStoreUpdateService();
      // Simule cold-start + retour foreground enchaînés.
      await expectLater(
        Future.wait([service.checkAndStart(), service.checkAndStart()]),
        completes,
      );
    });

    test('provider expose un singleton stable', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final a = container.read(playStoreUpdateServiceProvider);
      final b = container.read(playStoreUpdateServiceProvider);
      expect(identical(a, b), isTrue);
    });
  });
}
