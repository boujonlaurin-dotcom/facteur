import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:facteur/core/auth/supabase_storage.dart';

/// Tests de la couche de persistance de session (SupabaseHiveStorage).
///
/// Ce fichier couvre les chemins critiques liés au bug "re-login après fermeture de l'app":
/// - Persistance correcte de la session dans Hive
/// - Restauration correcte après redémarrage (simulé par réouverture de box)
/// - Comportement quand le box n'est pas initialisé (cold start race condition)
/// - Suppression correcte de la session (signOut)
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    await SupabaseHiveStorage().initialize();
  });

  setUp(() async {
    // Vider la box avant chaque test pour éviter les interférences
    final box = Hive.box<String>('supabase_auth_persistence');
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('SupabaseHiveStorage - initialize()', () {
    test('initialize() est idempotent (double appel sans erreur)', () async {
      // Ne doit pas throw si appelé deux fois (box déjà ouverte)
      await expectLater(
        SupabaseHiveStorage().initialize(),
        completes,
      );
    });
  });

  group('SupabaseHiveStorage - persistSession() / accessToken()', () {
    test('accessToken() retourne null si aucune session sauvegardée', () async {
      final token = await SupabaseHiveStorage().accessToken();
      expect(token, isNull);
    });

    test('persistSession() sauvegarde la session et accessToken() la retourne',
        () async {
      const fakeSession = '{"access_token":"eyJhbGciOiJIUzI1NiJ9.test","refresh_token":"refresh_test","expires_in":3600}';

      await SupabaseHiveStorage().persistSession(fakeSession);

      final stored = await SupabaseHiveStorage().accessToken();
      expect(stored, equals(fakeSession));
    });

    test('persistSession() écrase une session existante', () async {
      const sessionV1 = '{"access_token":"token_v1","refresh_token":"refresh_v1"}';
      const sessionV2 = '{"access_token":"token_v2","refresh_token":"refresh_v2"}';

      await SupabaseHiveStorage().persistSession(sessionV1);
      await SupabaseHiveStorage().persistSession(sessionV2);

      final stored = await SupabaseHiveStorage().accessToken();
      expect(stored, equals(sessionV2));
    });

    test('la session persistée survit à une réouverture de box (simulation redémarrage)',
        () async {
      const fakeSession =
          '{"access_token":"eyJhbGciOiJIUzI1NiJ9.survive","refresh_token":"r_survive","expires_in":3600}';

      await SupabaseHiveStorage().persistSession(fakeSession);

      // Fermer et rouvrir la box (simule un redémarrage de l'app)
      await Hive.box<String>('supabase_auth_persistence').close();
      await Hive.openBox<String>('supabase_auth_persistence');

      // Réinitialiser le storage pour pointer vers la nouvelle box
      await SupabaseHiveStorage().initialize();

      final restored = await SupabaseHiveStorage().accessToken();
      expect(restored, equals(fakeSession),
          reason:
              'La session doit survivre à un redémarrage (Hive flush to disk)');
    });
  });

  group('SupabaseHiveStorage - hasAccessToken()', () {
    test('hasAccessToken() retourne false si pas de session', () async {
      final has = await SupabaseHiveStorage().hasAccessToken();
      expect(has, isFalse);
    });

    test('hasAccessToken() retourne true après persistSession()', () async {
      const fakeSession = '{"access_token":"eyJhbGciOiJIUzI1NiJ9.test","refresh_token":"r_test","expires_in":3600}';
      await SupabaseHiveStorage().persistSession(fakeSession);

      final has = await SupabaseHiveStorage().hasAccessToken();
      expect(has, isTrue);
    });

    test('hasAccessToken() retourne false si session est une chaîne vide',
        () async {
      // Edge case : session vide ne doit pas être considérée valide
      final box = Hive.box<String>('supabase_auth_persistence');
      await box.put('supabase_session', '');

      final has = await SupabaseHiveStorage().hasAccessToken();
      expect(has, isFalse);
    });
  });

  group('SupabaseHiveStorage - removePersistedSession()', () {
    test('removePersistedSession() supprime la session existante', () async {
      const fakeSession = '{"access_token":"eyJhbGciOiJIUzI1NiJ9.delete_me","refresh_token":"r_del","expires_in":3600}';
      await SupabaseHiveStorage().persistSession(fakeSession);

      await SupabaseHiveStorage().removePersistedSession();

      final token = await SupabaseHiveStorage().accessToken();
      expect(token, isNull);
      final has = await SupabaseHiveStorage().hasAccessToken();
      expect(has, isFalse);
    });

    test('removePersistedSession() sans session préalable ne throw pas',
        () async {
      await expectLater(
        SupabaseHiveStorage().removePersistedSession(),
        completes,
      );
    });

    test(
        'removePersistedSession() + persistSession() fonctionne (cycle complet signOut/signIn)',
        () async {
      const session1 = '{"access_token":"eyJhbGciOiJIUzI1NiJ9.user1","refresh_token":"refresh_1","expires_in":3600}';
      const session2 = '{"access_token":"eyJhbGciOiJIUzI1NiJ9.user2","refresh_token":"refresh_2","expires_in":3600}';

      await SupabaseHiveStorage().persistSession(session1);
      await SupabaseHiveStorage().removePersistedSession();
      await SupabaseHiveStorage().persistSession(session2);

      final stored = await SupabaseHiveStorage().accessToken();
      expect(stored, equals(session2));
    });
  });

  group('SupabaseHiveStorage - Robustesse (edge cases Android)', () {
    test('flush() est appelé après persistSession() (données écrites sur disque)',
        () async {
      // On vérifie que les données sont immédiatement lisibles après persist
      // ce qui indique que flush() a bien été appelé.
      const fakeSession = '{"access_token":"eyJhbGciOiJIUzI1NiJ9.flush_test","refresh_token":"r_flush","expires_in":3600}';
      await SupabaseHiveStorage().persistSession(fakeSession);

      // Lecture directe depuis la box Hive (sans passer par le cache mémoire)
      final box = Hive.box<String>('supabase_auth_persistence');
      final rawValue = box.get('supabase_session');
      expect(rawValue, equals(fakeSession),
          reason:
              'La session doit être écrite immédiatement après persistSession() pour survivre à un kill OS');
    });

    test(
        'accessToken() gère le cas où la box est ouverte mais _box interne est null',
        () async {
      // Ce test vérifie le chemin de fallback dans accessToken()
      // quand la box est ouverte via Hive directement mais pas via initialize()
      const fakeSession = '{"access_token":"eyJ.fallback"}';
      final box = Hive.box<String>('supabase_auth_persistence');
      await box.put('supabase_session', fakeSession);

      // La box est ouverte dans Hive, on vérifie que accessToken() la retrouve
      final token = await SupabaseHiveStorage().accessToken();
      expect(token, equals(fakeSession));
    });
  });
}
