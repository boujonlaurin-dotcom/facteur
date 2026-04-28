import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'config/routes.dart';
import 'core/auth/auth_state.dart';
import 'core/providers/analytics_provider.dart';
import 'core/services/deep_link_service.dart';
import 'features/feed/providers/feed_preload_provider.dart';
import 'features/onboarding/providers/onboarding_sync_provider.dart';
import 'features/settings/providers/theme_provider.dart';

import 'core/ui/notification_service.dart';

/// Application principale Facteur
class FacteurApp extends ConsumerStatefulWidget {
  const FacteurApp({super.key});

  @override
  ConsumerState<FacteurApp> createState() => _FacteurAppState();
}

class _FacteurAppState extends ConsumerState<FacteurApp> {
  bool _deepLinksStarted = false;

  @override
  Widget build(BuildContext context) {
    debugPrint('FacteurApp: build() called');
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeNotifierProvider);

    // Keep feed preloader alive for the entire authenticated session: it
    // watches auth state and kicks off `feedProvider.future` in the
    // background so the Feed tab renders instantly on first tap.
    ref.watch(feedPreloadProvider);

    // Active la re-sync automatique de l'onboarding quand la session devient
    // authentifiée (best-effort, silencieux) — voir onboarding_sync_provider.dart.
    ref.watch(onboardingSyncProvider);

    // Bind the DeepLinkService once the router is built. Idempotent.
    final analytics = ref.read(analyticsServiceProvider);
    DeepLinkService.instance.bind(router: router, analytics: analytics);

    if (!_deepLinksStarted) {
      _deepLinksStarted = true;
      // Defer until after first frame so the router is fully wired.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        DeepLinkService.instance.start();
      });
    }

    // Mirror auth state into the deep link service so a widget tap that lands
    // pre-auth waits for sign-in before navigating.
    ref.listen<AuthState>(authStateProvider, (prev, next) {
      DeepLinkService.instance.setAuthenticated(next.isAuthenticated);
    });
    // Initial sync (the listen above only fires on changes).
    DeepLinkService.instance.setAuthenticated(
      ref.read(authStateProvider).isAuthenticated,
    );

    return MaterialApp.router(
      title: 'Facteur',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: NotificationService.messengerKey,

      // Thème
      theme: FacteurTheme.lightTheme,
      darkTheme: FacteurTheme.darkTheme,
      themeMode: themeMode,

      // Router
      routerConfig: router,
    );
  }
}
