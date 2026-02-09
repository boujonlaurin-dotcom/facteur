import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/onboarding/screens/conclusion_animation_screen.dart';
import '../features/feed/screens/feed_screen.dart';
import '../features/feed/models/content_model.dart';
import '../features/auth/screens/email_confirmation_screen.dart';
import '../features/detail/screens/content_detail_screen.dart';

import '../features/sources/screens/sources_screen.dart';
import '../features/sources/screens/add_source_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/settings/screens/account_screen.dart';
import '../features/settings/screens/notifications_screen.dart';
import '../features/settings/screens/about_screen.dart';
import '../features/progress/screens/progressions_screen.dart';
import '../features/progress/screens/quiz_screen.dart';
import '../features/subscription/screens/paywall_screen.dart';
import '../features/digest/screens/digest_screen.dart';
import '../features/digest/screens/closure_screen.dart';
import '../features/saved/screens/saved_screen.dart';
import '../core/auth/auth_state.dart';
import '../core/ui/notification_service.dart';
import '../shared/widgets/navigation/shell_scaffold.dart';

/// Noms des routes
class RouteNames {
  RouteNames._();

  static const String splash = 'splash';
  static const String login = 'login';
  static const String onboarding = 'onboarding';
  static const String onboardingConclusion = 'onboarding-conclusion';
  static const String digest = 'digest';
  static const String digestClosure = 'digest-closure';
  static const String feed = 'feed';
  static const String contentDetail = 'content-detail';
  static const String saved = 'saved';
  static const String sources = 'sources';
  static const String addSource = 'add-source';
  static const String settings = 'settings';
  static const String account = 'account';
  static const String notifications = 'notifications';
  static const String about = 'about';
  static const String progress = 'progress';
  static const String quiz = 'quiz';
  static const String paywall = 'paywall';
  static const String emailConfirmation = 'email-confirmation';
}

/// Chemins des routes
class RoutePaths {
  RoutePaths._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String onboarding = '/onboarding';
  static const String onboardingConclusion = '/onboarding/conclusion';
  static const String digest = '/digest';
  static const String digestClosure = '/digest/closure';
  static const String feed = '/feed';
  static const String contentDetail = '/content/:id';
  static const String saved = '/saved';
  static const String sources = '/settings/sources'; // Moved to settings
  // static const String addSource = '/sources/add'; // Removed for V0
  static const String settings = '/settings';
  static const String account = '/settings/account';
  static const String notifications = '/settings/notifications';
  static const String about = '/settings/about';
  static const String progress = '/progress';
  static const String quiz = '/quiz';
  static const String paywall = '/paywall';
  static const String emailConfirmation = '/email-confirmation';
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    navigatorKey: NotificationService.navigatorKey,
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // Attendre que l'auth state soit initialisé
      if (authState.isLoading) {
        return RoutePaths.splash;
      }

      final isLoggedIn = authState.isAuthenticated;
      final isEmailConfirmed = authState.isEmailConfirmed;

      final matchedLocation = state.matchedLocation;

      final isOnSplash = matchedLocation == RoutePaths.splash;
      final isOnLoginPage = matchedLocation == RoutePaths.login;
      final isOnEmailConfirmation =
          matchedLocation == RoutePaths.emailConfirmation;
      final isOnOnboarding = matchedLocation == RoutePaths.onboarding ||
          matchedLocation == RoutePaths.onboardingConclusion;
      final isOnDigest = matchedLocation == RoutePaths.digest;

      // 1. Les utilisateurs non connectés
      if (!isLoggedIn) {
        // Exception : si on vient de s'inscrire, on a un pending email
        if (authState.pendingEmailConfirmation != null) {
          if (isOnEmailConfirmation) return null;
          return RoutePaths.emailConfirmation;
        }

        if (isOnLoginPage) return null;
        return RoutePaths.login;
      }

      // À partir d'ici, l'utilisateur est connecté

      // 2. Les utilisateurs non confirmés doivent aller sur l'écran de confirmation
      if (!isEmailConfirmed) {
        if (isOnEmailConfirmation) return null;
        return RoutePaths.emailConfirmation;
      }

      // 3. Les utilisateurs confirmés ne doivent pas être sur login, confirmation ou splash
      if (isOnLoginPage || isOnEmailConfirmation || isOnSplash) {
        return authState.needsOnboarding
            ? RoutePaths.onboarding
            : RoutePaths
                .digest; // Digest is now the default authenticated route
      }

      // 4. Onboarding : forcer si nécessaire
      if (authState.needsOnboarding && !isOnOnboarding) {
        return RoutePaths.onboarding;
      }

      // 5. Onboarding : empêcher d'y retourner si fini
      if (!authState.needsOnboarding && isOnOnboarding) {
        return RoutePaths.digest; // Go to digest after onboarding completion
      }

      // Allow staying on digest (default authenticated route)
      if (isOnDigest) {
        return null;
      }

      return null;
    },
    routes: [
      // Splash
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // Auth
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),

      // Email Confirmation
      GoRoute(
        path: RoutePaths.emailConfirmation,
        name: RouteNames.emailConfirmation,
        builder: (context, state) {
          final authState = ref.read(authStateProvider);
          return EmailConfirmationScreen(
            email: authState.user?.email ??
                authState.pendingEmailConfirmation ??
                '',
          );
        },
      ),

      // Onboarding
      GoRoute(
        path: RoutePaths.onboarding,
        name: RouteNames.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),

      // Onboarding Conclusion Animation
      GoRoute(
        path: RoutePaths.onboardingConclusion,
        name: RouteNames.onboardingConclusion,
        builder: (context, state) => const ConclusionAnimationScreen(),
      ),

      // Shell avec bottom navigation
      ShellRoute(
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [
          // Digest (Essentiel) - Default authenticated route
          GoRoute(
            path: RoutePaths.digest,
            name: RouteNames.digest,
            builder: (context, state) => const DigestScreen(),
          ),

          // Feed
          GoRoute(
            path: RoutePaths.feed,
            name: RouteNames.feed,
            builder: (context, state) => const FeedScreen(),
            routes: [
              // Détail contenu (nested)
              GoRoute(
                path: 'content/:id',
                name: RouteNames.contentDetail,
                parentNavigatorKey: NotificationService.navigatorKey,
                pageBuilder: (context, state) {
                  final contentId = state.pathParameters['id']!;
                  // Story 5.2: Pass Content via extra for in-app reading
                  final content = state.extra as Content?;
                  return MaterialPage(
                    fullscreenDialog: true,
                    child: ContentDetailScreen(
                      contentId: contentId,
                      content: content,
                    ),
                  );
                },
              ),
            ],
          ),

          // Saved (Sauvegardés)
          GoRoute(
            path: RoutePaths.saved,
            name: RouteNames.saved,
            builder: (context, state) => const SavedScreen(),
          ),

          // MVP: Progressions routes temporarily disabled
          // The tab is removed but we keep route definitions for potential deep links
          // Users will be redirected to feed by shell_scaffold index calculation
          GoRoute(
            path: RoutePaths.progress,
            name: RouteNames.progress,
            // MVP: Redirect to feed with info message
            redirect: (context, state) {
              return RoutePaths.feed;
            },
            builder: (context, state) => const ProgressionsScreen(),
            routes: [
              GoRoute(
                path: 'quiz',
                name: RouteNames.quiz,
                parentNavigatorKey: NotificationService.navigatorKey,
                redirect: (context, state) {
                  return RoutePaths.feed;
                },
                builder: (context, state) {
                  final topic = state.extra as String;
                  return QuizScreen(topic: topic);
                },
              ),
            ],
          ),

          // Settings
          GoRoute(
            path: RoutePaths.settings,
            name: RouteNames.settings,
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'sources', // /settings/sources
                name: RouteNames.sources,
                builder: (context, state) => const SourcesScreen(),
                routes: [
                  GoRoute(
                    path: 'add', // /settings/sources/add
                    name: RouteNames.addSource,
                    builder: (context, state) => const AddSourceScreen(),
                  ),
                ],
              ),
              GoRoute(
                path: 'account', // /settings/account
                name: RouteNames.account,
                builder: (context, state) => const AccountScreen(),
              ),
              GoRoute(
                path: 'notifications', // /settings/notifications
                name: RouteNames.notifications,
                builder: (context, state) => const NotificationsScreen(),
              ),
              GoRoute(
                path: 'about', // /settings/about
                name: RouteNames.about,
                builder: (context, state) => const AboutScreen(),
              ),
            ],
          ),
        ],
      ),

      // Digest Closure (outside ShellRoute to hide bottom nav)
      GoRoute(
        path: RoutePaths.digestClosure,
        name: RouteNames.digestClosure,
        builder: (context, state) {
          final digestId = state.extra as String?;
          return ClosureScreen(digestId: digestId ?? '');
        },
      ),

      // Paywall (modal)
      GoRoute(
        path: RoutePaths.paywall,
        name: RouteNames.paywall,
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const PaywallScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page non trouvée: ${state.uri}'),
      ),
    ),
  );
});
