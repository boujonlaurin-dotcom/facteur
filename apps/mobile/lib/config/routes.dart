import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/widgets/navigation/swipe_back_page.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/onboarding/screens/conclusion_animation_screen.dart';
import '../features/feed/models/content_model.dart';
import '../features/feed/screens/flaner_screen.dart';
import '../features/flux_continu/screens/digest_section_screen.dart';
import '../features/flux_continu/screens/flux_continu_screen.dart';
import '../features/flux_continu/screens/theme_section_screen.dart';
import '../features/flux_continu/models/flux_continu_models.dart';
import '../features/flux_continu/services/tournee_progress_service.dart';
import '../features/auth/screens/email_confirmation_screen.dart';
import '../features/detail/screens/content_detail_screen.dart';

import '../features/sources/screens/sources_screen.dart';
import '../features/sources/screens/add_source_screen.dart';
import '../features/sources/screens/theme_sources_screen.dart';
import '../features/settings/screens/profile_screen.dart';
import '../features/settings/screens/account_screen.dart';
import '../features/settings/screens/notifications_screen.dart';
import '../features/settings/screens/about_screen.dart';
import '../features/settings/widgets/settings_sheet.dart';
import '../features/my_interests/screens/my_interests_screen.dart';
import '../features/custom_topics/screens/topic_explorer_screen.dart';
import '../features/subscription/screens/paywall_screen.dart';
import '../features/veille/screens/veille_config_screen.dart';
import '../features/lettres/screens/courrier_screen.dart';
import '../features/lettres/screens/open_letter_screen.dart';
import '../features/grille/screens/grille_screen.dart';
import '../features/grille/screens/grille_leaderboard_screen.dart';
import '../features/grille/screens/grille_share_screen.dart';
import '../features/saved/screens/saved_screen.dart';
import '../features/saved/screens/saved_all_screen.dart';
import '../features/saved/screens/collection_detail_screen.dart';
import '../core/auth/auth_state.dart';
import '../core/nudges/widgets/nudge_host.dart';
import '../core/services/deep_link_service.dart';
import '../core/ui/notification_service.dart';
import '../shared/widgets/navigation/modal_bottom_sheet_page.dart';

/// Onglet de bottom-nav affiché en dernier (Essentiel = 0, Flâner = 1).
///
/// Suivi au niveau module pour que la transition directionnelle entre onglets
/// reste correcte quel que soit le chemin de navigation (tap footer, closing
/// card, redirect, resume), et pas seulement sur un tap explicite du footer.
int _lastMainTabIndex = 0;

/// Construit la page d'un onglet principal avec une transition latérale
/// directionnelle : l'onglet cible glisse depuis la gauche quand on avance vers
/// la droite (Essentiel → Flâner) et depuis la droite quand on recule vers la
/// gauche (Flâner → Essentiel). Sur le même onglet (delta nul) → simple fondu.
CustomTransitionPage<void> _mainTabPage({
  required LocalKey key,
  required int tabIndex,
  required Widget child,
}) {
  final delta = tabIndex - _lastMainTabIndex;
  _lastMainTabIndex = tabIndex;
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, page) {
      if (delta == 0) {
        return FadeTransition(opacity: animation, child: page);
      }
      final begin = delta > 0 ? const Offset(-1, 0) : const Offset(1, 0);
      return SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: page,
      );
    },
    child: child,
  );
}

/// Noms des routes
class RouteNames {
  RouteNames._();

  static const String splash = 'splash';
  static const String login = 'login';
  static const String onboarding = 'onboarding';
  static const String onboardingConclusion = 'onboarding-conclusion';
  static const String digest = 'digest';
  static const String feed = 'feed';
  static const String flaner = 'flaner';
  static const String fluxContinu = 'flux-continu';
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
  static const String profile = 'profile';
  static const String progress = 'progress';
  static const String quiz = 'quiz';
  static const String paywall = 'paywall';
  static const String emailConfirmation = 'email-confirmation';
  static const String myInterests = 'my-interests';
  static const String topicExplorer = 'topic-explorer';
  static const String themeSources = 'theme-sources';
  static const String veilleConfig = 'veille-config';
  static const String lettres = 'lettres';
  static const String openLetter = 'open-letter';
  static const String grille = 'grille';
  static const String grilleLeaderboard = 'grille-leaderboard';
  static const String grilleShare = 'grille-share';
}

/// Chemins des routes
class RoutePaths {
  RoutePaths._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String onboarding = '/onboarding';
  static const String onboardingConclusion = '/onboarding/conclusion';
  static const String digest = '/digest';
  static const String feed = '/feed';
  static const String flaner = '/flaner';
  static const String fluxContinu = '/flux-continu';
  static const String contentDetail = '/content/:id';
  static const String saved = '/saved';
  static const String sources = '/settings/sources'; // Moved to settings
  // static const String addSource = '/sources/add'; // Removed for V0
  static const String settings = '/settings';
  static const String account = '/settings/account';
  static const String notifications = '/settings/notifications';
  static const String about = '/settings/about';
  static const String profile = '/settings/profile';
  static const String myInterests = '/settings/interests';
  static const String topicExplorer = '/topic-explorer';
  static const String progress = '/progress';
  static const String quiz = '/quiz';
  static const String paywall = '/paywall';
  static const String emailConfirmation = '/email-confirmation';
  static const String veilleConfig = '/veille/config';
  static const String lettres = '/lettres';
  static const String openLetter = '/lettres/:id';
  static const String grille = '/grille';
  static const String grilleLeaderboard = '/grille/leaderboard';
  static const String grilleShare = '/grille/share';
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
      // Intercept widget deep links pushed by PlatformRouteInformationProvider.
      // Without this, a raw `io.supabase.facteur://digest/<id>` URI lands in
      // GoRouter and falls through to errorBuilder ("Page non trouvée") before
      // DeepLinkService (app_links) can route. Idempotent with DeepLinkService:
      // both ultimately call router.go on the same in-app path.
      if (state.uri.scheme == 'io.supabase.facteur') {
        final action = DeepLinkService.parse(state.uri);
        return action.route ?? RoutePaths.fluxContinu;
      }

      final authState = ref.read(authStateProvider);
      String postAuthHomePath() {
        final tournee = ref.read(tourneeProgressServiceProvider);
        return tournee.isClosingDismissedTodaySync()
            ? RoutePaths.flaner
            : RoutePaths.fluxContinu;
      }

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
            : postAuthHomePath();
      }

      // 4. Onboarding : forcer si nécessaire
      if (authState.needsOnboarding &&
          !isOnOnboarding &&
          !isOnInterestsFromOnboarding) {
        return RoutePaths.onboarding;
      }

      // 5. Onboarding : empêcher d'y retourner si fini → atterrissage flux continu
      if (!authState.needsOnboarding && isOnOnboarding) {
        return postAuthHomePath();
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

      // Flux Continu V1.8 — nouvelle home post-auth (Story 21.1)
      GoRoute(
        path: RoutePaths.fluxContinu,
        name: RouteNames.fluxContinu,
        pageBuilder: (context, state) => _mainTabPage(
          key: state.pageKey,
          tabIndex: 0,
          child: const Stack(children: [FluxContinuScreen(), NudgeHost()]),
        ),
        routes: [
          GoRoute(
            path: 'content/:id',
            // Nom historique conservé pour que `context.pushNamed(contentDetail)`
            // continue de fonctionner après la suppression de la route /feed.
            name: RouteNames.contentDetail,
            parentNavigatorKey: NotificationService.navigatorKey,
            pageBuilder: (context, state) {
              final contentId = state.pathParameters['id']!;
              final content = state.extra as Content?;
              return FullSwipeCupertinoPage(
                child: ContentDetailScreen(
                  contentId: contentId,
                  content: content,
                ),
              );
            },
          ),
          GoRoute(
            path: 'theme/:key',
            parentNavigatorKey: NotificationService.navigatorKey,
            pageBuilder: (context, state) {
              final key = state.pathParameters['key']!;
              final section = state.extra as FeedThemeSection?;
              return FullSwipeCupertinoPage(
                child: ThemeSectionScreen(
                  sectionKeyValue: key,
                  initialSection: section,
                ),
              );
            },
          ),
          GoRoute(
            path: 'section/:key',
            parentNavigatorKey: NotificationService.navigatorKey,
            pageBuilder: (context, state) {
              final key = state.pathParameters['key']!;
              final section = state.extra as DigestTopicSection?;
              return FullSwipeCupertinoPage(
                child: DigestSectionScreen(
                  sectionKeyValue: key,
                  initialSection: section,
                ),
              );
            },
          ),
        ],
      ),

      // Flâner — feed autonome.
      GoRoute(
        path: RoutePaths.flaner,
        name: RouteNames.flaner,
        pageBuilder: (context, state) => _mainTabPage(
          key: state.pageKey,
          tabIndex: 1,
          child: const Stack(children: [FlanerScreen(), NudgeHost()]),
        ),
        routes: [
          GoRoute(
            path: 'content/:id',
            parentNavigatorKey: NotificationService.navigatorKey,
            pageBuilder: (context, state) {
              final contentId = state.pathParameters['id']!;
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

      GoRoute(
        path: '${RoutePaths.feed}/content/:id',
        redirect: (context, state) {
          final id = state.pathParameters['id']!;
          return '${RoutePaths.flaner}/content/$id';
        },
      ),

      // Feed (legacy) — redirige vers Flâner pour préserver les deep
      // links sortants en circulation (push notifs, partages, anciennes
      // versions de l'app). Voir cleanup post-unification du flux.
      GoRoute(
        path: RoutePaths.feed,
        name: RouteNames.feed,
        redirect: (context, state) => RoutePaths.flaner,
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
            pageBuilder: (context, state) =>
                const FullSwipeCupertinoPage(child: SavedAllScreen()),
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

      // Progress / Quiz (legacy) — redirige vers FluxContinu.
      GoRoute(
        path: RoutePaths.progress,
        name: RouteNames.progress,
        redirect: (context, state) => RoutePaths.fluxContinu,
        routes: [
          GoRoute(
            path: 'quiz',
            name: RouteNames.quiz,
            redirect: (context, state) => RoutePaths.fluxContinu,
          ),
        ],
      ),

      // Settings — bottom sheet root + sous-pages full-screen
      GoRoute(
        path: RoutePaths.settings,
        name: RouteNames.settings,
        pageBuilder: (context, state) =>
            const ModalBottomSheetPage(child: SettingsSheet()),
        routes: [
          GoRoute(
            path: 'profile', // /settings/profile
            name: RouteNames.profile,
            pageBuilder: (context, state) =>
                const FullSwipeCupertinoPage(child: ProfileScreen()),
          ),
          GoRoute(
            path: 'sources', // /settings/sources
            name: RouteNames.sources,
            pageBuilder: (context, state) =>
                const FullSwipeCupertinoPage(child: SourcesScreen()),
            routes: [
              GoRoute(
                path: 'add', // /settings/sources/add
                name: RouteNames.addSource,
                pageBuilder: (context, state) =>
                    const FullSwipeCupertinoPage(child: AddSourceScreen()),
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
            pageBuilder: (context, state) =>
                const FullSwipeCupertinoPage(child: AccountScreen()),
          ),
          GoRoute(
            path: 'notifications', // /settings/notifications
            name: RouteNames.notifications,
            pageBuilder: (context, state) =>
                const FullSwipeCupertinoPage(child: NotificationsScreen()),
          ),
          GoRoute(
            path: 'about', // /settings/about
            name: RouteNames.about,
            pageBuilder: (context, state) =>
                const FullSwipeCupertinoPage(child: AboutScreen()),
          ),
          GoRoute(
            path: 'interests', // /settings/interests
            name: RouteNames.myInterests,
            pageBuilder: (context, state) {
              final forceSereinOn = state.uri.queryParameters['serein'] == '1';
              return FullSwipeCupertinoPage(
                child: MyInterestsScreen(forceSereinOn: forceSereinOn),
              );
            },
          ),
        ],
      ),

      // Veille Config — flow de configuration "Ma veille".
      // Hors ShellRoute pour cacher la bottom nav (full-screen modal).
      // Entry point depuis Mes intérêts (CTA ou menu favori veille).
      GoRoute(
        path: RoutePaths.veilleConfig,
        name: RouteNames.veilleConfig,
        pageBuilder: (context, state) {
          final isEdit = state.uri.queryParameters['mode'] == 'edit';
          return FullSwipeCupertinoPage(
            child: VeilleConfigScreen(editMode: isEdit),
          );
        },
      ),

      // Lettres du Facteur — onboarding doux (story 19.1).
      GoRoute(
        path: RoutePaths.lettres,
        name: RouteNames.lettres,
        pageBuilder: (context, state) =>
            const FullSwipeCupertinoPage(child: CourrierScreen()),
        routes: [
          GoRoute(
            path: ':id',
            name: RouteNames.openLetter,
            pageBuilder: (context, state) => FullSwipeCupertinoPage(
              child: OpenLetterScreen(letterId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),

      // Digest (legacy) — redirige vers FluxContinu (le digest a fusionné
      // dans la Tournée du jour lors de l'unification du flux).
      GoRoute(
        path: RoutePaths.digest,
        name: RouteNames.digest,
        redirect: (context, state) => RoutePaths.fluxContinu,
      ),

      // La Grille du jour — route top-level (hors transition main-tab) +
      // sous-routes classement / partage, toutes en FullSwipeCupertinoPage.
      GoRoute(
        path: RoutePaths.grille,
        name: RouteNames.grille,
        pageBuilder: (context, state) =>
            const FullSwipeCupertinoPage(child: GrilleScreen()),
        routes: [
          GoRoute(
            path: 'leaderboard',
            name: RouteNames.grilleLeaderboard,
            pageBuilder: (context, state) =>
                const FullSwipeCupertinoPage(child: GrilleLeaderboardScreen()),
          ),
          GoRoute(
            path: 'share',
            name: RouteNames.grilleShare,
            pageBuilder: (context, state) =>
                const FullSwipeCupertinoPage(child: GrilleShareScreen()),
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

      // Paywall (modal)
      GoRoute(
        path: RoutePaths.paywall,
        name: RouteNames.paywall,
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const PaywallScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page non trouvée: ${state.uri}'))),
  );
});
