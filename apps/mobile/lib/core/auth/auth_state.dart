import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// État d'authentification
class AuthState {
  final User? user;
  final bool isLoading;
  final bool needsOnboarding;
  final String? error;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.needsOnboarding = false,
    this.error,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    User? user,
    bool? isLoading,
    bool? needsOnboarding,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      error: error,
    );
  }
}

/// Notifier pour l'état d'authentification
class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier() : super(const AuthState(isLoading: true)) {
    _init();
  }

  final _supabase = Supabase.instance.client;

  Future<void> _init() async {
    try {
      debugPrint('AuthStateNotifier: Starting initialization...');
      // 1. Charger la préférence de persistence en premier
      final box = await Hive.openBox<dynamic>('auth_prefs');
      final rememberMe = box.get('remember_me', defaultValue: true) as bool;
      debugPrint('AuthStateNotifier: rememberMe preference is $rememberMe');

      // 2. Attendre que Supabase soit prêt et récupère la session
      debugPrint('AuthStateNotifier: Waiting for initial session recovery...');

      Session? session = _supabase.auth.currentSession;

      if (session == null) {
        // OPTIMIZATION: Check if we even HAVE a stored session before waiting.
        // If no session is stored locally, we are definitely logged out.
        // This prevents the 3s delay for first-time users.
        final persistenceBox = Hive.box<String>('supabase_auth_persistence');
        if (!persistenceBox.containsKey('supabase_session')) {
          debugPrint(
            'AuthStateNotifier: No persisted session found in Hive. Skipping wait.',
          );
        } else {
          final sessionCompleter = Completer<Session?>();
          final subscription = _supabase.auth.onAuthStateChange.listen((data) {
            debugPrint(
              'AuthStateNotifier: INITIAL STREAM EVENT: ${data.event} - Session: ${data.session != null} - User: ${data.session?.user.email ?? "None"}',
            );

            if (data.session != null) {
              if (!sessionCompleter.isCompleted) {
                debugPrint('AuthStateNotifier: Session acquired via stream.');
                sessionCompleter.complete(data.session);
              }
            } else if (data.event == AuthChangeEvent.initialSession) {
              debugPrint(
                'AuthStateNotifier: initialSession is null, waiting up to 3s for potential delayed signedIn...',
              );
              // On attend un peu plus pour un éventuel signedIn différé
              Future<void>.delayed(const Duration(milliseconds: 3000)).then((
                _,
              ) {
                if (!sessionCompleter.isCompleted) {
                  debugPrint(
                    'AuthStateNotifier: Timeout after initialSession null.',
                  );
                  sessionCompleter.complete(null);
                }
              });
            }
          });

          try {
            // Timeout global de sécurité (8s car macOS peut être lent)
            session = await sessionCompleter.future.timeout(
              const Duration(milliseconds: 8000),
            );
          } catch (_) {
            debugPrint('AuthStateNotifier: Global 8s timeout reached.');
            session = _supabase.auth.currentSession;
          } finally {
            await subscription.cancel();
          }
        }
      }

      debugPrint(
        'AuthStateNotifier: Resolved session for final state: ${session?.user.email ?? "None"}',
      );

      // 3. Si on ne doit pas rester connecté, on force la déconnexion
      if (!rememberMe && session != null) {
        debugPrint(
          'AuthStateNotifier: rememberMe is false, signing out... TRACE:',
        );
        debugPrint(StackTrace.current.toString());
        await _supabase.auth.signOut();
        await box.delete('remember_me');
        session = null;
      }

      // 4. Mettre à jour l'état initial
      state = state.copyWith(user: session?.user, isLoading: false);
      debugPrint(
        'AuthStateNotifier: Initial state set. Authenticated: ${state.isAuthenticated}',
      );

      if (session != null) {
        await _checkOnboardingStatus();
      }

      // 5. Écouter les changements futurs pour les mises à jour en temps réel
      _supabase.auth.onAuthStateChange.listen((data) {
        final user = data.session?.user;
        debugPrint(
          'AuthStateNotifier: Auth listener event: ${data.event}, User: ${user?.email ?? "None"}',
        );

        // Éviter les mises à jour inutiles si l'user n'a pas changé
        if (state.user?.id == user?.id && !state.isLoading) return;

        state = state.copyWith(user: user, isLoading: false);

        if (user != null) {
          _checkOnboardingStatus();
        }
      });
    } catch (e) {
      debugPrint('AuthStateNotifier ERROR: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> signOut() async {
    debugPrint('AuthStateNotifier: signOut() explicitly called. TRACE:');
    debugPrint(StackTrace.current.toString());
    await _supabase.auth.signOut();
    final box = await Hive.openBox<dynamic>('auth_prefs');
    await box.delete('remember_me'); // Reset preference on sign out
    state = const AuthState();
  }

  Future<void> _checkOnboardingStatus() async {
    if (state.user == null) return;

    try {
      // 1. Vérifier le cache local d'abord pour décision rapide
      final box = await Hive.openBox<dynamic>('user_profile');
      final cachedCompleted = box.get('onboarding_completed') as bool?;

      if (cachedCompleted != null) {
        // Utiliser le cache pour une décision instantanée
        state = state.copyWith(needsOnboarding: !cachedCompleted);
      }

      // 2. Vérifier avec la base de données (source de vérité)
      final response = await _supabase
          .from('user_profiles')
          .select('onboarding_completed')
          .eq('user_id', state.user!.id)
          .maybeSingle();

      final needsOnboarding =
          response == null || response['onboarding_completed'] == false;

      // 3. Mettre à jour le cache avec la valeur de la DB
      await box.put('onboarding_completed', !needsOnboarding);

      // 4. Mettre à jour l'état si différent du cache
      if (state.needsOnboarding != needsOnboarding) {
        state = state.copyWith(needsOnboarding: needsOnboarding);
      }
    } catch (e) {
      // Si erreur et pas de cache, assumer onboarding nécessaire (safe fallback)
      state = state.copyWith(needsOnboarding: true);
    }
  }

  /// Force le rafraîchissement du statut onboarding depuis la DB
  Future<void> refreshOnboardingStatus() async {
    await _checkOnboardingStatus();
  }

  Future<void> signInWithEmail(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Sauvegarder la préférence de persistence
      final box = await Hive.openBox<dynamic>('auth_prefs');
      await box.put('remember_me', rememberMe);

      await _supabase.auth.signInWithPassword(email: email, password: password);
      state = state.copyWith(isLoading: false);
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Une erreur est survenue',
      );
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabase.auth.signUp(email: email, password: password);
      state = state.copyWith(isLoading: false, needsOnboarding: true);
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Une erreur est survenue',
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      state = state.copyWith(isLoading: false);
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Une erreur est survenue lors de l\'envoi de l\'email',
      );
      rethrow;
    }
  }

  Future<void> signInWithApple() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabase.auth.signInWithOAuth(OAuthProvider.apple);
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Une erreur est survenue',
      );
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabase.auth.signInWithOAuth(OAuthProvider.google);
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Une erreur est survenue',
      );
    }
  }

  void setOnboardingCompleted() {
    state = state.copyWith(needsOnboarding: false);
  }

  /// Change le statut d'onboarding (utilisé pour reset/refaire)
  Future<void> setNeedsOnboarding(bool value) async {
    state = state.copyWith(needsOnboarding: value);

    // Mettre à jour le cache local
    final box = await Hive.openBox<dynamic>('user_profile');
    await box.put('onboarding_completed', !value);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Provider de l'état d'authentification
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier();
});
