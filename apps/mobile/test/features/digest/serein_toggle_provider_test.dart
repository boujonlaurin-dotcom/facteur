import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';

app_auth.AuthState _authState(String? userId) {
  if (userId == null) return const app_auth.AuthState();
  return app_auth.AuthState(
    user: supabase.User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2023-01-01',
    ),
  );
}

/// Controllable fake so tests can flip the signed-in user at will.
class _FakeAuthNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  _FakeAuthNotifier(String? userId) : super(_authState(userId));

  void setUser(String? userId) => state = _authState(userId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeAuthNotifier auth) {
  final container = ProviderContainer(
    overrides: [
      app_auth.authStateProvider.overrideWith((ref) => auth),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

String _key(String userId) => 'serein_enabled:$userId';

void main() {
  // toggle() emits haptic feedback via a platform channel → the binding must
  // be initialised even for these unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  group('SereinToggleNotifier — restauration synchrone depuis Hive', () {
    test('un miroir ON pré-écrit est lu au boot, sans initFromApi', () {
      // Régression du bug : au cold start home (FluxContinuScreen ne construit
      // jamais digestProvider), l'état doit déjà être serein.
      Hive.box<dynamic>('settings').put(_key('userA'), true);

      final container = _container(_FakeAuthNotifier('userA'));
      final state = container.read(sereinToggleProvider);

      expect(state.enabled, isTrue);
      expect(state.isLoading, isFalse);
    });

    test('pas de miroir → legacy loading:true (comportement conservé)', () {
      final container = _container(_FakeAuthNotifier('userA'));
      final state = container.read(sereinToggleProvider);

      expect(state.enabled, isFalse);
      expect(state.isLoading, isTrue);
    });
  });

  group('SereinToggleNotifier.initFromApi idempotency', () {
    test('first call syncs with the server value and clears loading', () {
      final container = _container(_FakeAuthNotifier('userA'));
      expect(container.read(sereinToggleProvider).isLoading, isTrue);

      container.read(sereinToggleProvider.notifier).initFromApi(true);

      final state = container.read(sereinToggleProvider);
      expect(state.enabled, isTrue);
      expect(state.isLoading, isFalse);
    });

    test('subsequent calls never overwrite the stabilised choice', () {
      final container = _container(_FakeAuthNotifier('userA'));
      final notifier = container.read(sereinToggleProvider.notifier);

      notifier.initFromApi(true); // first load → enabled, no longer loading
      // A digest re-fetch returns the (stale) default — must be ignored.
      notifier.initFromApi(false);

      expect(container.read(sereinToggleProvider).enabled, isTrue);
    });

    test('an authoritative sync also persists the local mirror', () {
      final container = _container(_FakeAuthNotifier('userA'));

      container.read(sereinToggleProvider.notifier).initFromApi(true);

      expect(Hive.box<dynamic>('settings').get(_key('userA')), isTrue);
    });

    test('setEnabledLocal keeps isLoading so the first sync still confirms', () {
      final container = _container(_FakeAuthNotifier('userA'));
      final notifier = container.read(sereinToggleProvider.notifier);

      // Pré-réglage post-onboarding avant que /digest/both ait répondu.
      notifier.setEnabledLocal(true);
      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(container.read(sereinToggleProvider).isLoading, isTrue);

      // /digest/both confirme la préférence serveur.
      notifier.initFromApi(true);
      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(container.read(sereinToggleProvider).isLoading, isFalse);
    });

    test('setEnabledLocal ne persiste PAS le miroir local', () {
      final container = _container(_FakeAuthNotifier('userA'));
      container.read(sereinToggleProvider.notifier).setEnabledLocal(true);

      expect(Hive.box<dynamic>('settings').get(_key('userA')), isNull);
    });
  });

  group('SereinToggleNotifier.initFromApi — fallback non autoritatif', () {
    test('ne persiste pas et n\'écrase pas un miroir local ON', () {
      Hive.box<dynamic>('settings').put(_key('userA'), true);
      final container = _container(_FakeAuthNotifier('userA'));

      // Le fallback single-digest (404) ne porte aucun flag serein.
      container
          .read(sereinToggleProvider.notifier)
          .markLoadedFromFallback();

      // Le miroir ON reste ON, la clé Hive n'est pas touchée.
      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(Hive.box<dynamic>('settings').get(_key('userA')), isTrue);
    });

    test('lève juste isLoading si aucune valeur connue, sans persister', () {
      final container = _container(_FakeAuthNotifier('userA'));
      expect(container.read(sereinToggleProvider).isLoading, isTrue);

      container
          .read(sereinToggleProvider.notifier)
          .markLoadedFromFallback();

      expect(container.read(sereinToggleProvider).isLoading, isFalse);
      expect(container.read(sereinToggleProvider).enabled, isFalse);
      // Non autoritatif → pas de persistance.
      expect(Hive.box<dynamic>('settings').get(_key('userA')), isNull);
    });

    test('une vraie sync autoritaire peut encore arriver après le fallback', () {
      final container = _container(_FakeAuthNotifier('userA'));
      final notifier = container.read(sereinToggleProvider.notifier);

      notifier.markLoadedFromFallback(); // fallback
      notifier.initFromApi(true); // vraie sync serveur

      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(Hive.box<dynamic>('settings').get(_key('userA')), isTrue);
    });
  });

  group('SereinToggleNotifier.toggle', () {
    test('persiste le miroir local et survit à un restart', () {
      final container = _container(_FakeAuthNotifier('userA'));
      container.read(sereinToggleProvider.notifier).toggle();

      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(Hive.box<dynamic>('settings').get(_key('userA')), isTrue);

      // Un 2e container (redémarrage) relit la valeur persistée.
      final restarted = _container(_FakeAuthNotifier('userA'));
      final state = restarted.read(sereinToggleProvider);
      expect(state.enabled, isTrue);
      expect(state.isLoading, isFalse);
    });

    test('gèle la réconciliation serveur ultérieure', () {
      final container = _container(_FakeAuthNotifier('userA'));
      final notifier = container.read(sereinToggleProvider.notifier);

      notifier.toggle(); // choix explicite ON
      notifier.initFromApi(false); // sync tardive → ignorée

      expect(container.read(sereinToggleProvider).enabled, isTrue);
    });
  });

  group('SereinToggleNotifier.commitFromOnboarding', () {
    test('persiste le miroir local et lève loading', () {
      final container = _container(_FakeAuthNotifier('userA'));
      container.read(sereinToggleProvider.notifier).commitFromOnboarding(true);

      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(container.read(sereinToggleProvider).isLoading, isFalse);
      expect(Hive.box<dynamic>('settings').get(_key('userA')), isTrue);
    });

    test('gèle la réconciliation → un /digest/both tardif ne l\'écrase pas', () {
      // Régression issue 2 : le 1er /digest/both après l'onboarding peut lire
      // une préférence pas encore commitée durablement (fenêtre purge→réinsert
      // de save_onboarding). Le choix onboarding, explicite, doit tenir.
      final container = _container(_FakeAuthNotifier('userA'));
      final notifier = container.read(sereinToggleProvider.notifier);

      notifier.commitFromOnboarding(true);
      notifier.initFromApi(false); // sync tardive lisant une valeur périmée

      expect(container.read(sereinToggleProvider).enabled, isTrue);
    });
  });

  group('SereinToggleNotifier auth lifecycle', () {
    test('resets to a fresh loading state when the user changes', () {
      final auth = _FakeAuthNotifier('userA');
      final container = _container(auth);

      // User A: serein synced ON, stabilised.
      container.read(sereinToggleProvider.notifier).initFromApi(true);
      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(container.read(sereinToggleProvider).isLoading, isFalse);

      // Logout then a different account on the same device.
      auth.setUser(null);
      auth.setUser('userB');

      // The notifier is rebuilt fresh for userB (whose mirror is absent) → it
      // does not inherit userA's ON preference.
      final fresh = container.read(sereinToggleProvider);
      expect(fresh.isLoading, isTrue);
      expect(fresh.enabled, isFalse);

      container.read(sereinToggleProvider.notifier).initFromApi(false);
      expect(container.read(sereinToggleProvider).enabled, isFalse);
    });

    test('isolation multi-compte : la sync de B ne touche pas la clé de A', () {
      final auth = _FakeAuthNotifier('userA');
      final container = _container(auth);

      container.read(sereinToggleProvider.notifier).toggle(); // A → ON persisté
      expect(Hive.box<dynamic>('settings').get(_key('userA')), isTrue);

      auth.setUser(null);
      auth.setUser('userB');
      // B réconcilie OFF (sa préférence) : sa propre clé est écrite, celle de A
      // reste intacte.
      container.read(sereinToggleProvider.notifier).initFromApi(false);

      expect(container.read(sereinToggleProvider).enabled, isFalse);
      expect(Hive.box<dynamic>('settings').get(_key('userB')), isFalse);
      expect(Hive.box<dynamic>('settings').get(_key('userA')), isTrue);

      // Re-login A → serein ON restauré sans round-trip.
      auth.setUser(null);
      auth.setUser('userA');
      final backToA = container.read(sereinToggleProvider);
      expect(backToA.enabled, isTrue);
      expect(backToA.isLoading, isFalse);
    });
  });
}
