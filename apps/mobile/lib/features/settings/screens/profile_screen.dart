import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/auth/auth_state.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../providers/theme_provider.dart';

/// Page « Profil » regroupant les réglages applicatifs accessibles depuis
/// la sheet Réglages : compte, notifications, thème, refonte du
/// questionnaire, présentation.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final themeMode = ref.watch(themeNotifierProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space4),
        child: Column(
          children: [
            _Section(
              title: 'COMPTE',
              children: [
                _Tile(
                  icon: Icons.person_outline,
                  title: kIsWeb ? 'Compte' : 'Compte & Widget',
                  subtitle: 'Gérer vos informations',
                  onTap: () => context.pushNamed(RouteNames.account),
                ),
                _Tile(
                  icon: Icons.notifications_none,
                  title: 'Notifications',
                  onTap: () => context.pushNamed(RouteNames.notifications),
                ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space6),
            _Section(
              title: 'PRÉFÉRENCES',
              children: [
                _Tile(
                  icon: Icons.palette_outlined,
                  title: 'Thème',
                  subtitle: _themeName(themeMode),
                  onTap: () {
                    final next = themeMode == ThemeMode.light
                        ? ThemeMode.dark
                        : ThemeMode.light;
                    ref
                        .read(themeNotifierProvider.notifier)
                        .setThemeMode(next);
                  },
                ),
                _Tile(
                  icon: Icons.settings_suggest_outlined,
                  title: 'Refaire le questionnaire',
                  subtitle: 'Ajuster mon profil et mes préférences',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .restartOnboarding();
                    ref
                        .read(authStateProvider.notifier)
                        .setNeedsOnboarding(true);
                  },
                ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space6),
            _Section(
              title: 'À PROPOS',
              children: [
                _Tile(
                  icon: Icons.info_outline,
                  title: 'Présentation Facteur',
                  subtitle: 'Version Beta 1.2',
                  onTap: () => context.pushNamed(RouteNames.about),
                ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space8),
          ],
        ),
      ),
    );
  }

  String _themeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Papier Dessin';
      case ThemeMode.dark:
        return 'Encre & Nuit';
      case ThemeMode.system:
        return 'Système';
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space6,
            vertical: FacteurSpacing.space2,
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  letterSpacing: 1.5,
                ),
          ),
        ),
        Container(
          margin:
              const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.surfaceElevated),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 24),
            const SizedBox(width: FacteurSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
              color: colors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
