import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/widgets/navigation/swipe_back_page.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/onboarding/screens/conclusion_animation_screen.dart';
import '../features/welcome_tour/screens/welcome_tour_screen.dart';
import '../features/feed/screens/feed_screen.dart';
import '../features/feed/models/content_model.dart';
import '../features/auth/screens/email_confirmation_screen.dart';
import '../features/detail/screens/content_detail_screen.dart';

import '../features/sources/screens/sources_screen.dart';
import '../features/sources/screens/add_source_screen.dart';
import '../features/sources/screens/theme_sources_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/settings/screens/account_screen.dart';
import '../features/settings/screens/notifications_screen.dart';
import '../features/settings/screens/about_screen.dart';
import '../features/custom_topics/screens/my_interests_screen.dart';
import '../features/custom_topics/screens/topic_explorer_screen.dart';
import '../features/progress/screens/progressions_screen.dart';
import '../features/progress/screens/quiz_screen.dart';
import '../features/subscription/screens/paywall_screen.dart';
import '../features/digest/screens/digest_screen.dart';
import '../features/digest/screens/closure_screen.dart';
import '../features/saved/screens/saved_screen.dart';
import '../features/saved/screens/saved_all_screen.dart';
import '../features/saved/screens/collection_detail_screen.dart';
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
  static const String welcomeTour = 'welcome-tour';
  static const String digest = 'digest';
  static const String digestClosure = 'digest-closure';
  static const String feed = 'feed';
  static const String contentDetail = 'content-detail';
  static const String saved = 'saved';
  static const String savedAll = 'saved-all';
  static const String collectionDetail = 'collection-detail';
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
  static const String myInterests = 'my-interests';
  static const String topicExplorer = 'topic-explorer';
  static const String themeSources = 'theme-sources';
}

/// Chemins des routes
class RoutePaths {
  RoutePaths._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String onboarding = '/onboarding';
  static const String onboardingConclusion = '/onboarding/conclusion';
  static const String welcomeTour = '/welcome-tour';
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
  static const String myInterests = '/settings/interests';
  static const String topicExplorer = '/topic-explorer';
  static const String progress = '/progress';
  static const String quiz = '/quiz';
  static const String paywall = '/paywall';
  static const String emailConfirmation = '/email-confirmation';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Use ref.listen() (not ref.watch()) so auth state changes trigger
  // GoRouter's refreshListenable WITHOUT recreating the entire router.
  // ref.watch() would invalidate this provider and create a new GoRouter
  // with initialLocation: /splash, losing the user's current route.
  final refreshNotifier = AuthChangeNotifier();
  ref.listen(authStateProvider, (_, __) {
    refreshNotifier.notify();
  });
  ref.onDispose(() => refreshNotifier.dispose());

  return GoRouter(
    navigatorKey: NotificationService.navigatorKey,
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: true,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);

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
      // Escape hatch: the onboarding "Personnaliser mon mode serein" CTA pushes
      // the interests screen with ?serein=1. Let that through so the user can
      // configure their exclusions before completing onboarding.
      final isOnInterestsFromOnboarding =
          matchedLocation == RoutePaths.myInterests &&
              state.uri.queryParameters['serein'] == '1';
      final isOnDigest = matchedLocation == RoutePaths.digest;
      final isOnWelcomeTour = matchedLocation == RoutePaths.welcomeTour;

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
      if (authState.needsOnboarding &&
          !isOnOnboarding &&
          !isOnInterestsFromOnboarding) {
        return RoutePaths.onboarding;
      }

      // 5. Onboarding : empêcher d'y retourner si fini
      if (!authState.needsOnboarding && isOnOnboarding) {
        // After onboarding completion, hand off to the welcome tour gate below.
        return authState.welcomeTourSeen
            ? RoutePaths.digest
            : RoutePaths.welcomeTour;
      }

      // 6. Welcome Tour gate : intercepte tout user authentifié + onboardé qui
      // n'a pas encore vu le tour. Couvre le flow nouveau user (post-onboarding
      // → /digest → redirect) ET existant (1ʳᵉ relance post-deploy → /digest →
      // redirect). Laisse passer si déjà sur /welcome-tour.
      if (!authState.needsOnboarding &&
          !authState.welcomeTourSeen &&
          !isOnWelcomeTour) {
        return RoutePaths.welcomeTour;
      }

      // 7. Bloquer /welcome-tour si déjà vu (deep link, back nav, etc.).
      if (authState.welcomeTourSeen && isOnWelcomeTour) {
        return RoutePaths.digest;
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

      // Welcome Tour (3 animated pages, outside ShellRoute → no bottom nav)
      GoRoute(
        path: RoutePaths.welcomeTour,
        name: RouteNames.welcomeTour,
        builder: (context, state) => const WelcomeTourScreen(),
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
                  return FullSwipeCupertinoPage(
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
            routes: [
              GoRoute(
                path: 'all',
                name: RouteNames.savedAll,
                pageBuilder: (context, state) => const FullSwipeCupertinoPage(
                  child: SavedAllScreen(),
                ),
              ),
              GoRoute(
                path: 'collection/:id',
                name: RouteNames.collectionDetail,
                pageBuilder: (context, state) => FullSwipeCupertinoPage(
                  child: CollectionDetailScreen(
                    collectionId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
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
                pageBuilder: (context, state) => const FullSwipeCupertinoPage(
                  child: SourcesScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'add', // /settings/sources/add
                    name: RouteNames.addSource,
                    pageBuilder: (context, state) => const FullSwipeCupertinoPage(
                      child: AddSourceScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'theme/:slug', // /settings/sources/theme/:slug
                    name: RouteNames.themeSources,
                    pageBuilder: (context, state) {
                      final slug = state.pathParameters['slug']!;
                      final themeName = state.extra as String?;
                      return FullSwipeCupertinoPage(
                        child: ThemeSourcesScreen(
                          themeSlug: slug,
                          themeName: themeName,
                        ),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'account', // /settings/account
                name: RouteNames.account,
                pageBuilder: (context, state) => const FullSwipeCupertinoPage(
                  child: AccountScreen(),
                ),
              ),
              GoRoute(
                path: 'notifications', // /settings/notifications
                name: RouteNames.notifications,
                pageBuilder: (context, state) => const FullSwipeCupertinoPage(
                  child: NotificationsScreen(),
                ),
              ),
              GoRoute(
                path: 'about', // /settings/about
                name: RouteNames.about,
                pageBuilder: (context, state) => const FullSwipeCupertinoPage(
                  child: AboutScreen(),
                ),
              ),
              GoRoute(
                path: 'interests', // /settings/interests
                name: RouteNames.myInterests,
                pageBuilder: (context, state) {
                  final forceSereinOn =
                      state.uri.queryParameters['serein'] == '1';
                  return FullSwipeCupertinoPage(
                    child:
                        MyInterestsScreen(forceSereinOn: forceSereinOn),
                  );
                },
              ),
            ],
          ),
        ],
      ),

      // Topic Explorer (outside ShellRoute to hide bottom nav)
      GoRoute(
        path: RoutePaths.topicExplorer,
        name: RouteNames.topicExplorer,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return FullSwipeCupertinoPage(
            child: TopicExplorerScreen(
              topicSlug: extra['topicSlug'] as String? ?? '',
              topicName: extra['topicName'] as String?,
              initialArticles: extra['articles'] as List<Content>?,
            ),
          );
        },
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
