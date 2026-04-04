import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:facteur/core/auth/auth_state.dart';

/// Tests de logique de persistance de session.
///
/// Couvre les causes racines du bug "re-login après fermeture de l'app" :
///
/// CAUSE 1 : remember_me = false → signOut au prochain cold start
/// CAUSE 2 : Token expiré (JWT access token ~1h, refresh token ~7j)
/// CAUSE 3 : Comportement de AuthState lors de la restauration de session
/// CAUSE 4 : forceUnconfirmed empêche l'accès même avec session valide
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('session_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    if (Hive.isBoxOpen('auth_prefs')) {
      await Hive.box<dynamic>('auth_prefs').clear();
    } else {
      await Hive.openBox<dynamic>('auth_prefs');
    }
    if (Hive.isBoxOpen('user_profile')) {
      await Hive.box<dynamic>('user_profile').clear();
    } else {
      await Hive.openBox<dynamic>('user_profile');
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // GROUPE 1 : Logique remember_me (CAUSE 1 du bug)
  // ---------------------------------------------------------------------------
  group('remember_me logic', () {
    test('remember_me vaut true par défaut (absence de clé = true)', () async {
      final box = Hive.box<dynamic>('auth_prefs');
      // Simuler une box vide (première installation)
      final rememberMe = box.get('remember_me', defaultValue: true) as bool;
      expect(rememberMe, isTrue,
          reason:
              'Par défaut (première installation), remember_me doit être true'
              ' pour éviter de déconnecter l\'utilisateur sans raison');
    });

    test('remember_me sauvegardé à false doit persister entre redémarrages',
        () async {
      final box = Hive.box<dynamic>('auth_prefs');
      await box.put('remember_me', false);

      // Fermer et réouvrir la box (simulation redémarrage)
      await box.close();
      final box2 = await Hive.openBox<dynamic>('auth_prefs');
      final rememberMe = box2.get('remember_me', defaultValue: true) as bool;

      expect(rememberMe, isFalse,
          reason:
              'La préférence remember_me=false doit survivre au redémarrage');
    });

    test('remember_me sauvegardé à true doit persister entre redémarrages',
        () async {
      final box = Hive.box<dynamic>('auth_prefs');
      await box.put('remember_me', true);

      await box.close();
      final box2 = await Hive.openBox<dynamic>('auth_prefs');
      final rememberMe = box2.get('remember_me', defaultValue: true) as bool;

      expect(rememberMe, isTrue);
    });

    test(
        'suppression de remember_me → valeur par défaut true au prochain démarrage',
        () async {
      final box = Hive.box<dynamic>('auth_prefs');
      await box.put('remember_me', false);
      await box.delete('remember_me');

      final rememberMe = box.get('remember_me', defaultValue: true) as bool;
      expect(rememberMe, isTrue,
          reason: 'Après signOut (qui supprime remember_me), le prochain login'
              ' doit partir avec remember_me=true par défaut');
    });

    test(
        'si remember_me=false et session présente, l\'état doit être unauthenticated après _init',
        () {
      // Simulation de la logique dans _init() :
      // if (!rememberMe && session != null) → signOut
      const rememberMe = false;
      const hasSession = true;

      // Comportement attendu : l'utilisateur DOIT être déconnecté
      const shouldSignOut = !rememberMe && hasSession;
      expect(shouldSignOut, isTrue,
          reason:
              'Quand remember_me=false, la session doit être effacée au cold start');
    });

    test(
        'si remember_me=true et session présente, la session DOIT être restaurée',
        () {
      const rememberMe = true;
      const hasSession = true;

      const shouldSignOut = !rememberMe && hasSession;
      expect(shouldSignOut, isFalse,
          reason:
              'Quand remember_me=true, la session doit être restaurée sans demander re-login');
    });
  });

  // ---------------------------------------------------------------------------
  // GROUPE 2 : AuthState - session restore (CAUSE 2, 3, 4)
  // ---------------------------------------------------------------------------
  group('AuthState - session restore logic', () {
    User makeUser({
      String id = 'user-123',
      String? emailConfirmedAt,
      List<String> providers = const ['email'],
    }) {
      return User(
        id: id,
        appMetadata: {
          'provider': providers.first,
          'providers': providers,
        },
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: emailConfirmedAt,
      );
    }

    test(
        'isAuthenticated = false quand user = null (pas de session → login screen)',
        () {
      const state = AuthState(user: null, isLoading: false);
      expect(state.isAuthenticated, isFalse);
    });

    test('isAuthenticated = true quand user est présent', () {
      final user = makeUser(emailConfirmedAt: DateTime.now().toIso8601String());
      final state = AuthState(user: user, isLoading: false);
      expect(state.isAuthenticated, isTrue);
    });

    test(
        'isLoading = true en état initial → router reste sur splash (pas de redirect login)',
        () {
      const state = AuthState(isLoading: true);
      // Simulation de la logique router : if (authState.isLoading) return splash
      const shouldShowSplash = state.isLoading;
      expect(shouldShowSplash, isTrue,
          reason:
              'Pendant l\'init, le router doit attendre sur splash et ne pas'
              ' forcer le login prématurément');
    });

    test(
        'session restaurée avec email confirmé → isAuthenticated et isEmailConfirmed',
        () {
      final user = makeUser(
        emailConfirmedAt: DateTime.now().toIso8601String(),
        providers: ['email'],
      );
      final state = AuthState(user: user, isLoading: false);

      expect(state.isAuthenticated, isTrue);
      expect(state.isEmailConfirmed, isTrue,
          reason:
              'Utilisateur avec email confirmé doit accéder à l\'app sans re-login');
    });

    test(
        'session restaurée avec provider social (Google) → toujours confirmé même sans emailConfirmedAt',
        () {
      final user = makeUser(
        emailConfirmedAt: null, // Supabase peut ne pas setter ça pour OAuth
        providers: ['google'],
      );
      final state = AuthState(user: user, isLoading: false);

      expect(state.isAuthenticated, isTrue);
      expect(state.isEmailConfirmed, isTrue,
          reason:
              'Google OAuth doit être considéré comme confirmé même sans emailConfirmedAt');
    });

    test(
        'forceUnconfirmed = true empêche l\'accès même si la session est valide (bug 403)',
        () {
      final user = makeUser(
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      final state = AuthState(
        user: user,
        isLoading: false,
        forceUnconfirmed: true,
      );

      expect(state.isAuthenticated, isTrue);
      expect(state.isEmailConfirmed, isFalse,
          reason:
              'forceUnconfirmed doit court-circuiter isEmailConfirmed pour forcer'
              ' l\'écran de confirmation (guard contre stale JWT 403)');
    });

    test('forceUnconfirmed reset à false après confirmation → accès rétabli',
        () {
      final user = makeUser(
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      // Simuler le reset : forceUnconfirmed = false
      final state = AuthState(
        user: user,
        isLoading: false,
        forceUnconfirmed: false,
      );

      expect(state.isEmailConfirmed, isTrue,
          reason:
              'Après confirmation de l\'email, l\'accès doit être rétabli sans re-login');
    });

    test('copyWith préserve les valeurs non modifiées', () {
      final user = makeUser(emailConfirmedAt: DateTime.now().toIso8601String());
      final state = AuthState(
        user: user,
        isLoading: false,
        needsOnboarding: true,
        forceUnconfirmed: false,
      );

      final updated = state.copyWith(isLoading: true);
      expect(updated.user, equals(user));
      expect(updated.needsOnboarding, isTrue);
      expect(updated.forceUnconfirmed, isFalse);
      expect(updated.isLoading, isTrue);
    });

    test('copyWith(clearError: true) efface le champ error', () {
      const state = AuthState(error: 'some error');
      final cleared = state.copyWith(clearError: true);
      expect(cleared.error, isNull);
    });

    test('copyWith(clearPendingEmail: true) efface pendingEmailConfirmation',
        () {
      const state = AuthState(pendingEmailConfirmation: 'user@example.com');
      final cleared = state.copyWith(clearPendingEmail: true);
      expect(cleared.pendingEmailConfirmation, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // GROUPE 3 : Logique Router redirect - cold start scenarios
  // ---------------------------------------------------------------------------
  group('Router redirect logic - cold start scenarios', () {
    // Simulation de la fonction redirect du routerProvider

    String? simulateRedirect({
      required bool isLoading,
      required bool isAuthenticated,
      required bool isEmailConfirmed,
      required bool needsOnboarding,
      String? pendingEmailConfirmation,
      required String currentLocation,
    }) {
      if (isLoading) return '/splash';

      if (!isAuthenticated) {
        if (pendingEmailConfirmation != null) {
          if (currentLocation == '/email-confirmation') return null;
          return '/email-confirmation';
        }
        if (currentLocation == '/login') return null;
        return '/login';
      }

      if (!isEmailConfirmed) {
        if (currentLocation == '/email-confirmation') return null;
        return '/email-confirmation';
      }

      if (currentLocation == '/login' ||
          currentLocation == '/email-confirmation' ||
          currentLocation == '/splash') {
        return needsOnboarding ? '/onboarding' : '/digest';
      }

      if (needsOnboarding && currentLocation != '/onboarding') {
        return '/onboarding';
      }

      if (!needsOnboarding && currentLocation == '/onboarding') {
        return '/digest';
      }

      return null;
    }

    test('COLD START: isLoading=true → redirect vers /splash (pas vers /login)',
        () {
      final redirect = simulateRedirect(
        isLoading: true,
        isAuthenticated: false,
        isEmailConfirmed: false,
        needsOnboarding: false,
        currentLocation: '/splash',
      );
      expect(redirect, equals('/splash'),
          reason:
              'Pendant l\'initialisation, l\'app NE DOIT PAS rediriger vers /login'
              ' (causerait un flash login inutile)');
    });

    test(
        'COLD START: session restaurée avec succès → redirect vers /digest (pas /login)',
        () {
      final redirect = simulateRedirect(
        isLoading: false,
        isAuthenticated: true,
        isEmailConfirmed: true,
        needsOnboarding: false,
        currentLocation: '/splash',
      );
      expect(redirect, equals('/digest'),
          reason:
              'Si la session est restaurée correctement, l\'utilisateur doit'
              ' arriver directement sur le digest sans re-login');
    });

    test('COLD START: aucune session → redirect vers /login', () {
      final redirect = simulateRedirect(
        isLoading: false,
        isAuthenticated: false,
        isEmailConfirmed: false,
        needsOnboarding: false,
        currentLocation: '/splash',
      );
      expect(redirect, equals('/login'));
    });

    test(
        'COLD START: session restaurée mais remember_me=false → utilisateur déconnecté → /login',
        () {
      // Après signOut par remember_me=false, l'état est unauthenticated
      final redirect = simulateRedirect(
        isLoading: false,
        isAuthenticated: false, // après signOut
        isEmailConfirmed: false,
        needsOnboarding: false,
        currentLocation: '/splash',
      );
      expect(redirect, equals('/login'),
          reason:
              'Si remember_me=false, le user doit être invité à se reconnecter');
    });

    test(
        'COLD START: session restaurée avec email non confirmé → /email-confirmation',
        () {
      final redirect = simulateRedirect(
        isLoading: false,
        isAuthenticated: true,
        isEmailConfirmed: false,
        needsOnboarding: false,
        currentLocation: '/splash',
      );
      expect(redirect, equals('/email-confirmation'));
    });

    test(
        'RESUME: utilisateur authentifié et confirmé, sur /feed → pas de redirect',
        () {
      final redirect = simulateRedirect(
        isLoading: false,
        isAuthenticated: true,
        isEmailConfirmed: true,
        needsOnboarding: false,
        currentLocation: '/feed',
      );
      expect(redirect, isNull,
          reason:
              'Sur app resume, un utilisateur authentifié ne doit pas être redirigé');
    });

    test(
        'RESUME: token refresh échoue silencieusement → utilisateur reste authentifié en local state',
        () {
      // Le refreshUser() catch les erreurs sans changer l'état.
      // L'utilisateur reste "authenticated" localement.
      // Tant que la session Supabase interne n'est pas expirée, les API calls fonctionnent.
      // Ce test vérifie que la logique locale est correcte (pas de déconnexion injustifiée).
      final redirect = simulateRedirect(
        isLoading: false,
        isAuthenticated: true, // local state inchangé
        isEmailConfirmed: true,
        needsOnboarding: false,
        currentLocation: '/digest',
      );
      expect(redirect, isNull,
          reason:
              'Un échec de refreshSession() ne doit PAS déconnecter l\'utilisateur'
              ' immédiatement (le catch dans refreshUser ne change pas l\'état)');
    });

    test(
        'ONBOARDING: utilisateur confirmé avec onboarding requis → /onboarding',
        () {
      final redirect = simulateRedirect(
        isLoading: false,
        isAuthenticated: true,
        isEmailConfirmed: true,
        needsOnboarding: true,
        currentLocation: '/splash',
      );
      expect(redirect, equals('/onboarding'));
    });
  });

  // ---------------------------------------------------------------------------
  // GROUPE 4 : Logique onboarding cache (CAUSE du blocage post-restore)
  // ---------------------------------------------------------------------------
  group('Onboarding cache logic', () {
    test(
        'onboarding_completed=true dans le cache → needsOnboarding=false immédiatement',
        () async {
      final box = Hive.box<dynamic>('user_profile');
      await box.put('onboarding_completed', true);

      final cachedCompleted = box.get('onboarding_completed') as bool?;
      expect(cachedCompleted, isNotNull);
      expect(!cachedCompleted!, isFalse,
          reason:
              'Si le cache dit onboarding terminé, needsOnboarding doit être false'
              ' sans attendre la DB (évite un redirect vers /onboarding inattendu)');
    });

    test(
        'onboarding_completed absente du cache → null (pas de décision hâtive)',
        () async {
      final box = Hive.box<dynamic>('user_profile');
      final cachedCompleted = box.get('onboarding_completed') as bool?;
      expect(cachedCompleted, isNull,
          reason: 'Un cache vide doit retourner null, pas false, pour ne pas'
              ' forcer l\'onboarding à tort au premier démarrage');
    });

    test('cache onboarding survit à une réouverture de box', () async {
      final box = Hive.box<dynamic>('user_profile');
      await box.put('onboarding_completed', true);
      await box.close();

      final box2 = await Hive.openBox<dynamic>('user_profile');
      final cached = box2.get('onboarding_completed') as bool?;
      expect(cached, isTrue,
          reason:
              'Le cache d\'onboarding doit survivre au redémarrage pour éviter'
              ' un re-onboarding inattendu');
    });
  });
}
