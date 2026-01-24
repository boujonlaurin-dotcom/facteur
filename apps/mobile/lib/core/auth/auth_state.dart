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
    this.forceUnconfirmed = false,
  });

  /// Backend a explicitement rejeté l'accès (403) car email non confirmé
  final bool forceUnconfirmed;

  bool get isAuthenticated => user != null;

  /// Vérifie si l'email de l'utilisateur est confirmé.
  /// Les connexions via providers sociaux sont considérées comme confirmées d'office.
  bool get isEmailConfirmed {
    if (user == null) return false;
    if (forceUnconfirmed) return false;

    // DEBUG TRACE
    // debugPrint('AuthState: Checking isEmailConfirmed. UserID: ${user?.id}');
    // debugPrint('AuthState: emailConfirmedAt: ${user?.emailConfirmedAt}');
    // debugPrint('AuthState: appMetadata: ${user?.appMetadata}');

    // Si on a des identités et qu'une d'entre elles n'est pas 'email', on considère comme confirmé
    final identities = user?.appMetadata['providers'] as List<dynamic>?;
    if (identities != null && identities.any((p) => p != 'email')) {
      debugPrint('AuthState: ✅ Confirmed via non-email provider: $identities');
      return true;
    }

    final confirmed = user?.emailConfirmedAt != null;
    debugPrint(
        'AuthState: Check emailConfirmedAt: $confirmed (${user?.emailConfirmedAt})');
    return confirmed;
  }

  AuthState copyWith({
    User? user,
    bool? isLoading,
    bool? needsOnboarding,
    String? error,
    bool clearError = false,
    String? pendingEmailConfirmation,
    bool clearPendingEmail = false,
    bool? forceUnconfirmed,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      error: clearError ? null : (error ?? this.error),
      pendingEmailConfirmation: clearPendingEmail
          ? null
          : (pendingEmailConfirmation ?? this.pendingEmailConfirmation),
      forceUnconfirmed: forceUnconfirmed ?? this.forceUnconfirmed,
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

      // Timeout de sécurité: si l'init prend plus de 10s, on force isLoading: false
      // pour éviter un splash infini (fix: bug infinite loader)
      Future<void>.delayed(const Duration(seconds: 10), () {
        if (state.isLoading) {
          debugPrint('AuthStateNotifier: TIMEOUT! Forcing isLoading: false');
          state = state.copyWith(isLoading: false);
        }
      });

      // 1. Charger la préférence de persistence
      final box = await Hive.openBox<dynamic>('auth_prefs');
      final rememberMe = box.get('remember_me', defaultValue: true) as bool;
      debugPrint('AuthStateNotifier: rememberMe preference is $rememberMe');

      // 2. Récupérer la session actuelle (restaurée par Supabase.initialize)
      Session? session = _supabase.auth.currentSession;

      // 3. Appliquer la règle remember_me si une session est restaurée
      if (!rememberMe && session != null) {
        debugPrint('AuthStateNotifier: rememberMe is false, signing out...');
        // Timeout pour éviter blocage sur signOut
        await _supabase.auth.signOut().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('AuthStateNotifier: signOut timed out, continuing...');
          },
        );
        await box.delete('remember_me');
        session = null;
      }

      // 4. Verification stricte de l'email confirmé (Fix mismatch 403)
      // Si l'utilisateur a une session mais que l'email n'est pas confirmé dans le token/user object,
      // on doit le déconnecter pour forcer une nouvelle connexion et éviter les erreurs 403 sur le feed.
      if (session != null) {
        final user = session.user;
        final isConfirmed = user.emailConfirmedAt != null ||
            (user.appMetadata['providers'] as List<dynamic>?)
                    ?.any((p) => p != 'email') ==
                true;

        if (!isConfirmed) {
          debugPrint(
              'AuthStateNotifier: ⚠️ User email NOT confirmed. Router should redirect to Confirmation Screen.');
          // On ne force plus le logout ici (race condition). On laisse le Router rediriger.
        } else {
          debugPrint('AuthStateNotifier: ✅ User email confirmed.');
        }
      }

      // 5. Mettre à jour l'état initial
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

    // Vider le cache du profil utilisateur (pour que le prochain user ne soit pas considéré comme "onboardé" par erreur)
    final profileBox = await Hive.openBox<dynamic>('user_profile');
    await profileBox.clear();

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
    state = state.copyWith(isLoading: true, clearError: true);

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

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
        },
      );
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
    state = state.copyWith(isLoading: true, clearError: true);
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

  Future<void> resendConfirmationEmail(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      debugPrint(
          'AuthStateNotifier: Resending confirmation email to $email...');
      final response =
          await _supabase.auth.resend(type: OtpType.signup, email: email);
      debugPrint(
          'AuthStateNotifier: Resend API call completed. Response ID: ${response.messageId}');
      state = state.copyWith(isLoading: false);
    } on AuthException catch (e) {
      debugPrint(
          'AuthStateNotifier: Resend AuthException: ${e.message} (Code: ${e.statusCode})');
      state = state.copyWith(
        isLoading: false,
        error: AuthErrorMessages.translate(e.message),
      );
      rethrow;
    } catch (e) {
      debugPrint('AuthStateNotifier: Resend Unknown Error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Une erreur est survenue lors de l\'envoi de l\'email',
      );
      rethrow;
    }
  }

  Future<void> signInWithApple() async {
    state = state.copyWith(isLoading: true, clearError: true);

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
    state = state.copyWith(isLoading: true, clearError: true);

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
    state = state.copyWith(clearError: true);
  }

  /// Efface l'état de pending email confirmation (après navigation vers l'écran de confirmation)
  void clearPendingEmailConfirmation() {
    state = state.copyWith(clearPendingEmail: true);
  }

  /// Rafraîchit les informations de l'utilisateur depuis Supabase
  /// Utile pour vérifier si l'email a été confirmé
  Future<void> refreshUser() async {
    try {
      debugPrint('AuthStateNotifier: Refreshing user session...');
      final response = await _supabase.auth.refreshSession();
      final user = response.user;

      if (user != null) {
        // Check if email is now confirmed (either via emailConfirmedAt or social provider)
        final isNowConfirmed = user.emailConfirmedAt != null ||
            (user.appMetadata['providers'] as List<dynamic>?)
                    ?.any((p) => p != 'email') ==
                true;

        debugPrint(
          'AuthStateNotifier: User refreshed. Confirmed: $isNowConfirmed',
        );
        state = state.copyWith(
          user: user,
          // Reset forceUnconfirmed if email is now confirmed (fixes stale JWT 403)
          forceUnconfirmed: isNowConfirmed ? false : state.forceUnconfirmed,
        );
        await _checkOnboardingStatus();
      }
    } catch (e) {
      debugPrint('AuthStateNotifier ERROR: Failed to refresh user: $e');
    }
  }

  /// Marque l'utilisateur comme non confirmé (suite à un 403 Backend)
  void setForceUnconfirmed() {
    if (!state.forceUnconfirmed) {
      debugPrint(
          'AuthStateNotifier: ⛔️ Backend returned 403. Forcing UNCONFIRMED state.');
      state = state.copyWith(forceUnconfirmed: true);
    }
  }
}

/// Provider de l'état d'authentification
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier();
});
