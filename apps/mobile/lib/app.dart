import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'config/routes.dart';
import 'features/feed/providers/feed_preload_provider.dart';
import 'features/onboarding/providers/onboarding_sync_provider.dart';
import 'features/settings/providers/theme_provider.dart';

import 'core/ui/notification_service.dart';

/// Application principale Facteur
class FacteurApp extends ConsumerWidget {
  const FacteurApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
