import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'config/routes.dart';
import 'features/settings/providers/theme_provider.dart';

/// Application principale Facteur
class FacteurApp extends ConsumerWidget {
  const FacteurApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeNotifierProvider);

    return MaterialApp.router(
      title: 'Facteur',
      debugShowCheckedModeBanner: false,

      // Thème
      theme: FacteurTheme.lightTheme,
      darkTheme: FacteurTheme.darkTheme,
      themeMode: themeMode,

      // Router
      routerConfig: router,
    );
  }
}
