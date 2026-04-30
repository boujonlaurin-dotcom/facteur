import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../../features/auth/utils/auth_error_messages.dart';
import '../services/posthog_service.dart';
import '../services/widget_service.dart';
import 'session_refresher.dart';

/// État d'authentification
class AuthState {
  final User? user;
  final bool isLoading;
  final bool needsOnboarding;
  final String? error;

  /// Email en attente de confirmation après signup
  final String? pendingEmailConfirmation;

  /// Backend a explicitement rejeté l'accès (403) car email non confirmé
  final bool forceUnconfirmed;

  /// Le refresh token a expiré — l'utilisateur doit se reconnecter
  final bool sessionExpired;

  /// Timestamp du dernier event `tokenRefreshed` reçu depuis Supabase.
  ///
  /// Utilisé comme signal d'invalidation pour les data providers (ex.
  /// `feedProvider`) : à chaque rotation de JWT, ce champ change et tous les
  /// listeners de `authStateProvider` rebuildent avec un access token frais.
  /// Cf. docs/bugs/bug-feed-403-auth-recovery.md.
  final DateTime? lastTokenRefreshAt;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.needsOnboarding = false,
    this.error,
    this.pendingEmailConfirmation,
    this.forceUnconfirmed = false,
    this.sessionExpired = false,
    this.lastTokenRefreshAt,
  });

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
    bool? sessionExpired,
    DateTime? lastTokenRefreshAt,
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
      sessionExpired: sessionExpired ?? this.sessionExpired,
      lastTokenRefreshAt: lastTokenRefreshAt ?? this.lastTokenRefreshAt,
    );
  }
}

/// Notifier pour l'état d'authentification
class AuthStateNotifier extends StateNotifier<AuthState>
    with WidgetsBindingObserver {
  AuthStateNotifier() : super(const AuthState(isLoading: true)) {
    _init();
  }

  final _supabase = Supabase.instance.client;

  /// Timestamp of the last forceUnconfirmed set. Used to debounce
  /// repeated 403s and avoid redirect loops.
  DateTime? _lastForceUnconfirmedAt;

  /// Version minimale de l'onboarding requise.
  /// Incrémentée lors de changements majeurs pour forcer les users existants
  /// à repasser par l'onboarding (skip vers Section 3 uniquement).
  static const int _requiredOnboardingVersion = 3;

  Future<void> _init() async {
    try {
      WidgetsBinding.instance.addObserver(this);
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
        await _supabase.auth.signOut().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('AuthStateNotifier: signOut timed out, continuing...');
          },
        );
        await box.delete('remember_me');
        session = null;
      }

      // 4. Refresh bloquant : rafraîchir le token AVANT de set l'état authentifié.
      // Le token d'accès Supabase expire après 1h. Si l'app est relancée après,
      // le token stocké est mort. On le rafraîchit ici pour éviter des 401 immédiats.
      // Single-flight via SessionRefresher pour éviter la race "double-refresh"
      // (cf. docs/bugs/bug-android-disconnect-race.md).
      if (session != null) {
        debugPrint(
            'AuthStateNotifier: Session found, attempting blocking refresh...');
        try {
          final refreshed = await SessionRefresher.instance.refresh();
          if (refreshed != null) {
            session = refreshed;
            debugPrint('AuthStateNotifier: ✅ Session refreshed successfully.');
          }
        } on AuthException catch (e) {
          debugPrint(
              'AuthStateNotifier: Refresh failed (AuthException): ${e.message}');
          // Si SessionRefresher a propagé une AuthException, c'est qu'il a déjà
          // vérifié que `currentSession` est null/expirée. La session est morte.
          unawaited(PostHogService().capture(
            event: 'auth_session_expired',
            properties: {'reason': 'init_refresh_failed'},
          ));
          unawaited(Sentry.captureException(
            e,
            withScope: (scope) =>
                scope.setTag('auth_event', 'init_refresh_failed'),
          ));
          session = null;
          await _supabase.auth.signOut().timeout(
            const Duration(seconds: 3),
            onTimeout: () {},
          );
          state = state.copyWith(isLoading: false, sessionExpired: true);
          _setupAuthListener();
          return;
        } on TimeoutException {
          debugPrint(
              'AuthStateNotifier: Refresh timed out. Using existing session.');
          // Réseau lent → garder session existante, SDK auto-refresh prendra le relais
        } catch (e) {
          debugPrint(
              'AuthStateNotifier: Refresh failed (unknown): $e. Using existing session.');
          // Erreur réseau → garder session existante
        }
      }

      // 5. Verification stricte de l'email confirmé (Fix mismatch 403)
      if (session != null) {
        final user = session.user;
        final isConfirmed = user.emailConfirmedAt != null ||
            (user.appMetadata['providers'] as List<dynamic>?)
                    ?.any((p) => p != 'email') ==
                true;

        if (!isConfirmed) {
          debugPrint(
              'AuthStateNotifier: ⚠️ User email NOT confirmed. Router should redirect to Confirmation Screen.');
        } else {
          debugPrint('AuthStateNotifier: ✅ User email confirmed.');
        }
      }

      // 6. Mettre à jour l'état initial (avec session fraîche).
      // forceUnconfirmed est reset systématiquement : flag volatile qui ne doit
      // pas survivre à un restart (si l'email est réellement non-confirmé, le
      // prochain appel API renverra 403 et le flag sera re-set proprement).
      state = state.copyWith(
        user: session?.user,
        isLoading: false,
        forceUnconfirmed: false,
      );

      debugPrint(
        'AuthStateNotifier: Initial state set. Authenticated: ${state.isAuthenticated}',
      );

      if (session != null) {
        await _checkOnboardingStatus();
      }

      // 7. Écouter les changements futurs
      _setupAuthListener();
    } catch (e) {
      debugPrint('AuthStateNotifier ERROR: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _setupAuthListener() {
    _supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      debugPrint(
        'AuthStateNotifier: Auth event: ${data.event}, User: ${user?.email ?? "None"}',
      );

      // Event tokenRefreshed : on ne short-circuite JAMAIS, on propage un
      // nouveau `lastTokenRefreshAt` dans le state pour signaler aux data
      // providers (feedProvider, etc.) qu'ils peuvent re-fetcher avec un
      // access token frais. Cf. docs/bugs/bug-feed-403-auth-recovery.md.
      final bool isTokenRefresh =
          data.event == AuthChangeEvent.tokenRefreshed;

      // Éviter les mises à jour inutiles si l'user n'a pas changé.
      // IMPORTANT: si `forceUnconfirmed` est true, on NE court-circuite PAS —
      // tout event Supabase (notamment TOKEN_REFRESHED avec un JWT à jour)
      // doit pouvoir reset le flag (sinon l'user reste bloqué sur l'écran
      // de confirmation email même après que le backend a validé son email).
      final bool sameUser = state.user?.id == user?.id &&
          !state.isLoading &&
          state.user != null;
      if (sameUser && !state.forceUnconfirmed && !isTokenRefresh) {
        final bool emailStatusChanged =
            state.user?.emailConfirmedAt != user?.emailConfirmedAt;
        if (!emailStatusChanged) {
          return;
        }
      }
      if (state.user == null && user == null && !state.isLoading) return;

      // Vérifier si l'email est maintenant confirmé pour reset forceUnconfirmed
      final isNowConfirmed = user?.emailConfirmedAt != null ||
          (user?.appMetadata['providers'] as List<dynamic>?)
                  ?.any((p) => p != 'email') ==
              true;

      // Capturer AVANT la mise à jour du state pour détecter les transitions
      final bool isNewSignIn = state.user == null && user != null;

      state = state.copyWith(
        user: user,
        isLoading: false,
        forceUnconfirmed: isNowConfirmed ? false : state.forceUnconfirmed,
        lastTokenRefreshAt: isTokenRefresh ? DateTime.now() : null,
      );

      if (user != null && isNewSignIn) {
        // Check onboarding on first sign-in (new user appearing).
        _loadSessionProfile();
      }
    });
  }

  /// Gère l'expiration de session (refresh token expiré ou 401 irrécupérable).
  /// Déconnecte proprement et affiche un message friendly sur l'écran de login.
  ///
  /// `reason` : tag d'instrumentation pour identifier dans PostHog/Sentry quel
  /// chemin a déclenché la déconnexion (refresh_failed, 401_after_refresh,
  /// init_refresh_failed, etc.). Cf. docs/bugs/bug-android-disconnect-race.md.
  Future<void> handleSessionExpired({String reason = 'unknown'}) async {
    debugPrint(
        'AuthStateNotifier: handleSessionExpired (reason=$reason). TRACE:');
    debugPrint(StackTrace.current.toString());
    unawaited(PostHogService().capture(
      event: 'auth_session_expired',
      properties: {'reason': reason},
    ));
    unawaited(Sentry.captureMessage(
      'auth_session_expired',
      level: SentryLevel.warning,
      withScope: (scope) => scope.setTag('reason', reason),
    ));
    await _supabase.auth.signOut().timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    state = const AuthState(sessionExpired: true);
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

    // Drop the locally cached feed so a subsequent login never briefly flashes
    // another user's content. The feed cache is a pure optimization; its
    // absence is silently tolerated by FeedNotifier.
    if (Hive.isBoxOpen('feed_cache')) {
      await Hive.box<String>('feed_cache').clear();
    }

    // Wipe the home-screen widget so the next account on the same device
    // never briefly sees the previous user's digest.
    await WidgetService.clear();

    state = const AuthState();
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState != AppLifecycleState.resumed) return;
    // Reset loading state in case user cancelled an OAuth flow
    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
    if (!state.isAuthenticated) return;

    // Au resume après background prolongé (typique : nuit complète sur Android),
    // l'access token JWT (TTL 1h) est expiré. On refresh AVANT que l'UI
    // déclenche des requêtes pour éviter une cascade de 401 → refresh
    // concurrents (cf. docs/bugs/bug-android-disconnect-race.md).
    //
    // SessionRefresher garantit le single-flight : si l'ApiClient interceptor
    // (sur 401) tape entre-temps, il piggyback sur cette future au lieu de
    // déclencher un 2ème refresh.
    debugPrint(
        'AuthStateNotifier: App resumed. Refreshing session (single-flight)...');
    SessionRefresher.instance
        .refresh()
        .then((_) => debugPrint('AuthStateNotifier: Resume refresh done.'))
        .catchError((Object e) {
      debugPrint('AuthStateNotifier: Resume refresh failed: $e');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadSessionProfile() async {
    await _checkOnboardingStatus();
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

      var needsOnboarding =
          response == null || response['onboarding_completed'] == false;

      // 3. Si onboarding déjà fait, vérifier la version
      // Les users avec une version obsolète repassent par Section 3
      if (!needsOnboarding) {
        final savedVersion =
            box.get('onboarding_app_version') as int? ?? 0;
        if (savedVersion < _requiredOnboardingVersion) {
          needsOnboarding = true;
          // Pré-configurer le restart vers Section 3 directement
          // Guard: only write once to avoid resetting user progress on every app resume
          if (!state.needsOnboarding) {
            final onboardingBox = await Hive.openBox('onboarding');
            await onboardingBox.put('section', 2); // sourcePreferences index
            await onboardingBox.put('question', 0);
          }
          debugPrint(
            'AuthState: onboarding version $savedVersion < $_requiredOnboardingVersion, '
            're-triggering onboarding (Section 3 only)',
          );
        }
      }

      // 4. Mettre à jour le cache avec la valeur de la DB
      await box.put('onboarding_completed', !needsOnboarding);

      // 5. Mettre à jour l'état si différent du cache
      if (state.needsOnboarding != needsOnboarding) {
        state = state.copyWith(needsOnboarding: needsOnboarding);
      }
    } catch (e) {
      debugPrint('AuthState: _checkOnboardingStatus error: $e');
      // Don't override existing state on error — keep whatever was cached
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
    state = state.copyWith(
        isLoading: true, clearError: true, sessionExpired: false);

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
        error: AuthErrorMessages.translate(e.message),
      );
    } on FormatException catch (e) {
      // Erreur de parsing - souvent liée à une mauvaise configuration
      debugPrint('AUTH_DEBUG signIn FormatException (likely config error): $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Erreur de configuration. Veuillez contacter le support.',
      );
    } catch (e) {
      debugPrint('AUTH_DEBUG signIn Unknown Error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Une erreur est survenue',
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
      // Deep link pour native, URL web pour Flutter web
      final redirectUrl = kIsWeb
          ? Uri(scheme: Uri.base.scheme, host: Uri.base.host, path: Uri.base.path).toString()
          : 'io.supabase.facteur://login-callback';

      await _supabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: redirectUrl,
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
        error: AuthErrorMessages.translate(e.message),
      );
    } catch (e) {
      debugPrint('AUTH_DEBUG signUp Unknown Error: $e');
      state = state.copyWith(
        isLoading: false,
        // DEBUG: Afficher l'erreur brute
        error: 'Une erreur est survenue',
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
    state = state.copyWith(
        isLoading: true, clearError: true, sessionExpired: false);

    try {
      final redirectUrl = kIsWeb
          ? Uri.base.resolve('auth/callback').toString()
          : 'io.supabase.facteur://login-callback';
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: redirectUrl,
      );
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
    state = state.copyWith(
        isLoading: true, clearError: true, sessionExpired: false);

    try {
      final redirectUrl = kIsWeb
          ? Uri(scheme: Uri.base.scheme, host: Uri.base.host, path: Uri.base.path).toString()
          : 'io.supabase.facteur://login-callback';
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
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

  Future<void> setOnboardingCompleted() async {
    state = state.copyWith(needsOnboarding: false);
    // Persister la version pour éviter un re-trigger au prochain login
    final box = await Hive.openBox<dynamic>('user_profile');
    await box.put('onboarding_app_version', _requiredOnboardingVersion);
    await box.put('onboarding_completed', true);
  }

  /// Change le statut d'onboarding (utilisé pour reset/refaire)
  Future<void> setNeedsOnboarding(bool value) async {
    state = state.copyWith(needsOnboarding: value);

    // Mettre à jour le cache local
    final box = await Hive.openBox<dynamic>('user_profile');
    await box.put('onboarding_completed', !value);

    if (!value) {
      await box.put('onboarding_app_version', _requiredOnboardingVersion);
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Efface l'état de pending email confirmation (après navigation vers l'écran de confirmation)
  void clearPendingEmailConfirmation() {
    state = state.copyWith(clearPendingEmail: true);
  }

  /// Force le reset du flag `forceUnconfirmed` (utilisé par l'ApiClient quand
  /// une requête réussit — prouvant que le backend considère l'user comme
  /// confirmé, indépendamment du contenu du JWT côté mobile).
  void clearForceUnconfirmed() {
    if (state.forceUnconfirmed) {
      debugPrint(
          'AuthStateNotifier: ✅ Clearing forceUnconfirmed (backend accepted request).');
      state = state.copyWith(forceUnconfirmed: false);
    }
  }

  /// Rafraîchit les informations de l'utilisateur depuis Supabase via le
  /// `SessionRefresher` (single-flight). Sur AuthException, recheck
  /// `currentSession` avant de déconnecter — un refresh concurrent a peut-être
  /// déjà obtenu une session valide. Cf. docs/bugs/bug-android-disconnect-race.md.
  Future<void> refreshUser() async {
    try {
      debugPrint('AuthStateNotifier: Refreshing user session...');
      final session = await SessionRefresher.instance.refresh();
      final user = session?.user;

      if (user != null) {
        final isNowConfirmed = user.emailConfirmedAt != null ||
            (user.appMetadata['providers'] as List<dynamic>?)
                    ?.any((p) => p != 'email') ==
                true;

        debugPrint(
          'AuthStateNotifier: User refreshed. Confirmed: $isNowConfirmed',
        );
        state = state.copyWith(
          user: user,
          forceUnconfirmed: isNowConfirmed ? false : state.forceUnconfirmed,
        );
        // Onboarding is checked on init and auth change only, not on resume
      }
    } on AuthException catch (e) {
      debugPrint(
          'AuthStateNotifier: Refresh failed (AuthException): ${e.message}');
      // Recheck via le SDK : un refresh concurrent (le SDK lui-même ou un
      // autre call site via SessionRefresher) a peut-être déjà obtenu une
      // session valide pendant que cet appel échouait.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final currentSession = _supabase.auth.currentSession;
      if (currentSession != null && !currentSession.isExpired) {
        debugPrint(
            'AuthStateNotifier: Concurrent refresh recovered session — not signing out.');
        return;
      }

      // Détecter si le refresh token est vraiment expiré/invalide.
      // IMPORTANT: Ne matcher que des messages spécifiques à l'expiration
      // de session. "invalid" seul est trop large et cause des déconnexions
      // intempestives sur des erreurs transitoires.
      final msg = e.message.toLowerCase();
      if (msg.contains('refresh_token') ||
          msg.contains('token has expired') ||
          msg.contains('invalid refresh token') ||
          msg.contains('invalid claim') ||
          msg.contains('session_not_found') ||
          msg.contains('session not found') ||
          msg.contains('user not found')) {
        debugPrint(
            'AuthStateNotifier: Refresh token expired. Ending session.');
        await handleSessionExpired(reason: 'refresh_token_expired');
      }
    } catch (e) {
      // Erreur réseau ou autre — ne rien faire, le SDK auto-refresh réessaiera
      debugPrint('AuthStateNotifier ERROR: Failed to refresh user: $e');
    }
  }


  /// Marque l'utilisateur comme non confirmé (suite à un 403 Backend).
  ///
  /// N'est appelé que par `ApiClient.onAuthError(403)` APRÈS que l'ApiClient
  /// ait lui-même tenté un `refreshSession()` + retry de la requête. Donc à
  /// ce stade, on sait que le user est réellement non-confirmé côté DB et on
  /// n'essaie pas un 2e refresh (éviterait rate-limit Supabase + double
  /// logout si refresh token expiré).
  ///
  /// Debounce de 30s : si on vient de reset forceUnconfirmed (user a confirmé
  /// son email et refreshUser() a détecté la confirmation), on ignore les 403
  /// pendant 30s pour laisser le temps au backend de propager la confirmation.
  ///
  /// Le recovery éventuel (user qui confirme ensuite) passe par le callback
  /// `onAuthRecovered` déclenché dès qu'une requête aboutit → `clearForceUnconfirmed`.
  void setForceUnconfirmed() {
    if (state.forceUnconfirmed) return;

    // Cooldown: ignore 403 si on a récemment été marqué comme non-confirmé
    // puis re-confirmé (évite les boucles confirmation→403→confirmation)
    if (_lastForceUnconfirmedAt != null) {
      final elapsed = DateTime.now().difference(_lastForceUnconfirmedAt!);
      if (elapsed.inSeconds < 30) {
        debugPrint(
            'AuthStateNotifier: Ignoring 403 — cooldown active (${elapsed.inSeconds}s < 30s).');
        return;
      }
    }

    debugPrint(
        'AuthStateNotifier: ⛔️ Backend returned 403 email_not_confirmed.');
    _lastForceUnconfirmedAt = DateTime.now();
    state = state.copyWith(forceUnconfirmed: true);
  }
}

/// Provider de l'état d'authentification
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier();
});

/// Listenable that GoRouter can use to re-evaluate redirects
/// without recreating the entire router instance.
class AuthChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
