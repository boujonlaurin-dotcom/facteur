import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'config/routes.dart';
import 'core/auth/auth_state.dart';
import 'core/providers/analytics_provider.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/widget_service.dart';
import 'features/feed/providers/feed_preload_provider.dart';
import 'features/feed/providers/feed_provider.dart';
import 'features/my_interests/services/interests_sync_service.dart';
import 'features/onboarding/providers/onboarding_sync_provider.dart';
import 'features/settings/providers/theme_provider.dart';

import 'core/ui/notification_service.dart';

/// Application principale Facteur
class FacteurApp extends ConsumerStatefulWidget {
  const FacteurApp({super.key});

  @override
  ConsumerState<FacteurApp> createState() => _FacteurAppState();
}

class _FacteurAppState extends ConsumerState<FacteurApp>
    with WidgetsBindingObserver {
  bool _deepLinksStarted = false;
  bool _wasBackgrounded = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cold-start flush: any Flux scroll session that ended while the app was
    // killed gets logged on the next launch. Deferred so the ProviderScope
    // is fully built and analyticsServiceProvider is readable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushFluxScrollMetricIfAny();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.paused) {
      _wasBackgrounded = true;
      _backgroundedAt = DateTime.now();
    } else if (appState == AppLifecycleState.resumed) {
      _flushFluxScrollMetricIfAny();
      if (_wasBackgrounded) {
        _wasBackgrounded = false;
        final elapsed = _backgroundedAt != null
            ? DateTime.now().difference(_backgroundedAt!)
            : null;
        if (ref.read(authStateProvider).isAuthenticated &&
            (elapsed == null || elapsed.inSeconds >= 60)) {
          ref.read(feedProvider.notifier).refresh();
        }
      }
    }
  }

  Future<void> _flushFluxScrollMetricIfAny() async {
    try {
      final metric = await WidgetService.readAndClearFluxScrollMetric();
      if (metric == null) return;
      final analytics = ref.read(analyticsServiceProvider);
      await analytics.trackWidgetFluxScrollSession(
        maxPosition: metric.maxPosition,
        totalCount: metric.totalCount,
        at: metric.at,
      );
    } catch (e) {
      debugPrint('FacteurApp: flush widget scroll metric failed: $e');
    }
  }

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

    // Story 22.1 PR 3/3 — sync one-shot des préférences héritées du slider
    // 1→3 (SharedPreferences `theme_priority_*`) vers les nouveaux favoris
    // backend. Idempotent via flag, fire-and-forget, silencieux sur erreur.
    ref.watch(interestsSyncProvider);

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
