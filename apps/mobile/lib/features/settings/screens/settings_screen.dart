import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/constants.dart';
import '../../../config/routes.dart';

import '../../../config/theme.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/providers/navigation_providers.dart';
import '../providers/theme_provider.dart';
import '../providers/paid_content_provider.dart';
import '../../digest/providers/digest_mode_provider.dart';
import '../../onboarding/providers/onboarding_provider.dart';

/// Écran des paramètres
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    // Listen to scroll to top trigger
    ref.listen(settingsScrollTriggerProvider, (_, __) => _scrollToTop());

    return Material(
      color: colors.backgroundPrimary,
      child: Column(
        children: [
          AppBar(
            title: const Text('Paramètres'),
            backgroundColor: colors.backgroundPrimary,
            elevation: 0,
            titleTextStyle: Theme.of(context).textTheme.displaySmall,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  const SizedBox(height: FacteurSpacing.space4),
                  // Feedback CTA — prominent, top of settings
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4,
                    ),
                    child: Material(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.large),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.large),
                        onTap: () async {
                          final uri =
                              Uri.parse(ExternalLinks.feedbackFormUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.all(FacteurSpacing.space4),
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIcons.chatCircleDots(
                                    PhosphorIconsStyle.regular),
                                color: colors.primary,
                                size: 24,
                              ),
                              const SizedBox(width: FacteurSpacing.space4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Donner mon avis',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: colors.primary,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Aidez-nous à améliorer Facteur',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colors.primary
                                                .withValues(alpha: 0.7),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                PhosphorIcons.arrowSquareOut(
                                    PhosphorIconsStyle.regular),
                                color: colors.primary.withValues(alpha: 0.6),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: FacteurSpacing.space6),
                  // Profil Section
                  _buildSection(
                    context,
                    title: 'CONTENU',
                    children: [
                      Builder(builder: (context) {
                        final modeState = ref.watch(digestModeProvider);
                        return _buildTile(
                          context,
                          icon: PhosphorIcons.sliders(PhosphorIconsStyle.regular),
                          title: 'Mon Essentiel',
                          subtitle: 'Mode : ${modeState.mode.label}',
                          onTap: () {
                            context.pushNamed(RouteNames.digestSettings);
                          },
                        );
                      }),
                      _buildTile(
                        context,
                        icon: Icons.bookmark_outline,
                        title: 'Mes sauvegardes',
                        subtitle: 'Articles sauvegardés et notes',
                        onTap: () {
                          context.push(RoutePaths.saved);
                        },
                      ),
                      _buildTile(
                        context,
                        icon: Icons.star_outline,
                        title: 'Sources de confiance',
                        subtitle: 'Gérer vos préférences',
                        onTap: () {
                          context.pushNamed(RouteNames.sources);
                        },
                      ),
                      _buildToggleTile(
                        context,
                        icon: PhosphorIcons.lock(PhosphorIconsStyle.regular),
                        title: 'Masquer les articles payants',
                        subtitle: 'Filtrer les contenus réservés aux abonnés',
                        value: ref.watch(hidePaidContentProvider),
                        onChanged: (value) {
                          ref
                              .read(hidePaidContentProvider.notifier)
                              .toggle(value);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: FacteurSpacing.space6),

                  // Profil Section
                  _buildSection(
                    context,
                    title: 'PROFIL',
                    children: [
                      _buildTile(
                        context,
                        icon: Icons.person_outline,
                        title: 'Compte',
                        subtitle: 'Gérer vos informations',
                        onTap: () {
                          context.pushNamed(RouteNames.account);
                        },
                      ),
                      _buildTile(
                        context,
                        icon: Icons.notifications_none,
                        title: 'Notifications',
                        onTap: () {
                          context.pushNamed(RouteNames.notifications);
                        },
                      ),
                      _buildTile(
                        context,
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

                  // App Section
                  _buildSection(
                    context,
                    title: 'APPLICATION',
                    children: [
                      _buildTile(
                        context,
                        icon: Icons.palette_outlined,
                        title: 'Thème',
                        subtitle:
                            _getThemeName(ref.watch(themeNotifierProvider)),
                        onTap: () {
                          final current = ref.read(themeNotifierProvider);
                          final next = current == ThemeMode.light
                              ? ThemeMode.dark
                              : ThemeMode.light;
                          ref
                              .read(themeNotifierProvider.notifier)
                              .setThemeMode(next);
                        },
                      ),
                      _buildTile(
                        context,
                        icon: Icons.info_outline,
                        title: 'Présentation Facteur',
                        subtitle: 'Version Alpha #105',
                        onTap: () {
                          context.pushNamed(RouteNames.about);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: FacteurSpacing.space8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
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
          margin: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
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

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
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
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = context.facteurColors;
    return Padding(
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
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: colors.primary,
          ),
        ],
      ),
    );
  }

  String _getThemeName(ThemeMode mode) {
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
