import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/onboarding/screens/conclusion_animation_screen.dart';
import '../features/feed/screens/feed_screen.dart';
import '../features/detail/screens/content_detail_screen.dart';
import '../features/saved/screens/saved_screen.dart';
import '../features/sources/screens/sources_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/settings/screens/account_screen.dart';
import '../features/settings/screens/notifications_screen.dart';
import '../features/progress/screens/progress_screen.dart';
import '../features/subscription/screens/paywall_screen.dart';
import '../core/auth/auth_state.dart';
import '../shared/widgets/navigation/shell_scaffold.dart';

/// Noms des routes
class RouteNames {
  RouteNames._();

  static const String splash = 'splash';
  static const String login = 'login';
  static const String onboarding = 'onboarding';
  static const String onboardingConclusion = 'onboarding-conclusion';
  static const String feed = 'feed';
  static const String contentDetail = 'content-detail';
  static const String saved = 'saved';
  static const String sources = 'sources';
  static const String addSource = 'add-source';
  static const String settings = 'settings';
  static const String account = 'account';
  static const String notifications = 'notifications';
  static const String progress = 'progress';
  static const String paywall = 'paywall';
}

/// Chemins des routes
class RoutePaths {
  RoutePaths._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String onboarding = '/onboarding';
  static const String onboardingConclusion = '/onboarding/conclusion';
  static const String feed = '/feed';
  static const String contentDetail = '/content/:id';
  static const String saved = '/saved';
  static const String sources = '/settings/sources'; // Moved to settings
  // static const String addSource = '/sources/add'; // Removed for V0
  static const String settings = '/settings';
  static const String account = '/settings/account';
  static const String notifications = '/settings/notifications';
  static const String progress = '/progress';
  static const String paywall = '/paywall';
}

/// Provider du router
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // Attendre que l'auth state soit initialisé
      if (authState.isLoading) {
        return RoutePaths.splash;
      }

      final isLoggedIn = authState.isAuthenticated;
      final isOnSplash = state.matchedLocation == RoutePaths.splash;
      final isOnLoginPage = state.matchedLocation == RoutePaths.login;
      final isOnOnboarding = state.matchedLocation == RoutePaths.onboarding;
      final isOnOnboardingConclusion =
          state.matchedLocation == RoutePaths.onboardingConclusion;

      // Si on est sur splash et que le chargement est fini, rediriger vers feed ou login
      if (isOnSplash) {
        if (isLoggedIn) {
          return authState.needsOnboarding
              ? RoutePaths.onboarding
              : RoutePaths.feed;
        }
        return RoutePaths.login;
      }

      // Si non connecté et pas sur login → rediriger vers login
      if (!isLoggedIn && !isOnLoginPage) {
        return RoutePaths.login;
      }

      // Si connecté et sur login → rediriger vers feed ou onboarding
      if (isLoggedIn && isOnLoginPage) {
        if (authState.needsOnboarding) {
          return RoutePaths.onboarding;
        }
        return RoutePaths.feed;
      }

      // Si connecté mais onboarding pas fait -> rediriger vers onboarding
      // On vérifie qu'on n'est pas déjà sur une page d'onboarding pour éviter les boucles
      if (isLoggedIn &&
          !isOnOnboarding &&
          !isOnOnboardingConclusion &&
          authState.needsOnboarding) {
        return RoutePaths.onboarding;
      }

      // Si connecté, onboarding complété, mais sur onboarding → feed
      if (isLoggedIn && isOnOnboarding && !authState.needsOnboarding) {
        return RoutePaths.feed;
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
                builder: (context, state) {
                  final contentId = state.pathParameters['id']!;
                  return ContentDetailScreen(contentId: contentId);
                },
              ),
            ],
          ),

          // Sauvegardés
          GoRoute(
            path: RoutePaths.saved,
            name: RouteNames.saved,
            builder: (context, state) => const SavedScreen(),
          ),

          // Settings
          GoRoute(
            path: RoutePaths.settings,
            name: RouteNames.settings,
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'sources', // /settings/sources
                name: RouteNames
                    .sources, // Reusing existing name for trusted sources
                builder: (context, state) => const SourcesScreen(),
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
            ],
          ),
        ],
      ),

      // Progression (modal/push depuis feed)
      GoRoute(
        path: RoutePaths.progress,
        name: RouteNames.progress,
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const ProgressScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              )),
              child: child,
            );
          },
        ),
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
