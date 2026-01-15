import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/utils/auth_error_messages.dart';

/// État d'authentification
class AuthState {
  final User? user;
  final bool isLoading;
  final bool needsOnboarding;
  final String? error;

  /// Email en attente de confirmation après signup
  final String? pendingEmailConfirmation;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.needsOnboarding = false,
    this.error,
    this.pendingEmailConfirmation,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    User? user,
    bool? isLoading,
    bool? needsOnboarding,
    String? error,
    String? pendingEmailConfirmation,
    bool clearPendingEmail = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      error: error,
      pendingEmailConfirmation: clearPendingEmail
          ? null
          : (pendingEmailConfirmation ?? this.pendingEmailConfirmation),
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

      // 1. Charger la préférence de persistence
      final box = await Hive.openBox<dynamic>('auth_prefs');
      final rememberMe = box.get('remember_me', defaultValue: true) as bool;
      debugPrint('AuthStateNotifier: rememberMe preference is $rememberMe');

      // 2. Récupérer la session actuelle (restaurée par Supabase.initialize)
      Session? session = _supabase.auth.currentSession;

      // 3. Appliquer la règle remember_me si une session est restaurée
      if (!rememberMe && session != null) {
        debugPrint('AuthStateNotifier: rememberMe is false, signing out...');
        await _supabase.auth.signOut();
        await box.delete('remember_me');
        session = null;
      }

      // 4. Mettre à jour l'état initial
      state = state.copyWith(
        user: session?.user,
        isLoading: false,
      );

      debugPrint(
        'AuthStateNotifier: Initial state set. Authenticated: ${state.isAuthenticated}',
      );

      if (session != null) {
        await _checkOnboardingStatus();
      }

      // 5. Écouter les changements futurs
      _supabase.auth.onAuthStateChange.listen((data) {
        final user = data.session?.user;
        debugPrint(
          'AuthStateNotifier: Auth event: ${data.event}, User: ${user?.email ?? "None"}',
        );

        // Éviter les mises à jour inutiles si l'user n'a pas changé
        if (state.user?.id == user?.id &&
            !state.isLoading &&
            state.user != null) {
          return;
        }
        if (state.user == null && user == null && !state.isLoading) return;

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
      debugPrint(
          'AUTH_DEBUG signIn AuthException: ${e.message} | statusCode: ${e.statusCode}');
      state = state.copyWith(
        isLoading: false,
        // DEBUG: Afficher l'erreur brute pour identifier le problème
        error:
            '${AuthErrorMessages.translate(e.message)} [DEBUG: ${e.message}]',
      );
    } catch (e) {
      debugPrint('AUTH_DEBUG signIn Unknown Error: $e');
      state = state.copyWith(
        isLoading: false,
        // DEBUG: Afficher l'erreur brute
        error: 'Une erreur est survenue [DEBUG: $e]',
      );
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabase.auth.signUp(email: email, password: password);
      // Signaler que l'email de confirmation a été envoyé
      state = state.copyWith(
        isLoading: false,
        pendingEmailConfirmation: email,
      );
    } on AuthException catch (e) {
      debugPrint(
          'AUTH_DEBUG signUp AuthException: ${e.message} | statusCode: ${e.statusCode}');
      state = state.copyWith(
        isLoading: false,
        // DEBUG: Afficher l'erreur brute pour identifier le problème
        error:
            '${AuthErrorMessages.translate(e.message)} [DEBUG: ${e.message}]',
      );
    } catch (e) {
      debugPrint('AUTH_DEBUG signUp Unknown Error: $e');
      state = state.copyWith(
        isLoading: false,
        // DEBUG: Afficher l'erreur brute
        error: 'Une erreur est survenue [DEBUG: $e]',
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      state = state.copyWith(isLoading: false);
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: AuthErrorMessages.translate(e.message),
      );
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
      state = state.copyWith(
        isLoading: false,
        error: AuthErrorMessages.translate(e.message),
      );
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
      state = state.copyWith(
        isLoading: false,
        error: AuthErrorMessages.translate(e.message),
      );
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

  /// Efface l'état de pending email confirmation (après navigation vers l'écran de confirmation)
  void clearPendingEmailConfirmation() {
    state = state.copyWith(clearPendingEmail: true);
  }
}

/// Provider de l'état d'authentification
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier();
});
