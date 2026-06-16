import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../providers/language_preference_provider.dart';
import '../providers/paid_content_provider.dart';

class SourceSettingsScreen extends ConsumerWidget {
  const SourceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final hidePaid = ref.watch(hidePaidContentProvider);
    final language = ref.watch(languagePreferenceProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Paramètres des sources'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: ListView(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border: Border.all(color: colors.surfaceElevated),
            ),
            child: Column(
              children: [
                _NavigationTile(
                  icon: PhosphorIcons.link(PhosphorIconsStyle.regular),
                  title: 'Mes abonnements',
                  subtitle: 'Gérer mes médias payants connectés',
                  onTap: () => context.pushNamed(RouteNames.subscriptions),
                ),
                _Divider(colors: colors),
                _SourceSwitchTile(
                  icon: PhosphorIcons.lock(PhosphorIconsStyle.regular),
                  title: 'Masquer les articles payants',
                  subtitle: 'Sauf pour les abonnements connectés.',
                  value: hidePaid,
                  onChanged: (value) =>
                      ref.read(hidePaidContentProvider.notifier).toggle(value),
                ),
                _Divider(colors: colors),
                _SourceSwitchTile(
                  icon: PhosphorIcons.translate(PhosphorIconsStyle.regular),
                  title: 'Masquer les sources non françaises',
                  subtitle: 'Les sources suivies restent toujours visibles.',
                  value: language.hideNonFr,
                  onChanged: (value) async {
                    final ok = await ref
                        .read(languagePreferenceProvider.notifier)
                        .toggle(value);
                    if (!ok) {
                      NotificationService.showError(
                        'Impossible de mettre à jour ce réglage. Réessaye dans un instant.',
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
      onTap: onTap,
      child: _TileContent(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Icon(
          PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
          color: colors.textTertiary,
          size: 18,
        ),
      ),
    );
  }
}

class _SourceSwitchTile extends StatelessWidget {
  const _SourceSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: _TileContent(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Switch.adaptive(
          value: value,
          activeThumbColor: context.facteurColors.primary,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TileContent extends StatelessWidget {
  const _TileContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space3,
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 22),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          trailing,
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.colors});

  final FacteurColors colors;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: FacteurSpacing.space4,
      endIndent: FacteurSpacing.space4,
      color: colors.border.withValues(alpha: 0.5),
    );
  }
}
