import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../providers/notifications_settings_provider.dart';

/// Écran de gestion des préférences de notifications
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final settings = ref.watch(notificationsSettingsProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Toggles
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
                border: Border.all(color: colors.surfaceElevated),
              ),
              child: Column(
                children: [
                  // Push Notifications
                  _buildToggleTile(
                    context,
                    icon: Icons.notifications_active_outlined,
                    title: 'Notifications push',
                    subtitle: 'Recevoir des alertes sur votre appareil',
                    value: settings.pushEnabled,
                    onChanged: (value) {
                      ref
                          .read(notificationsSettingsProvider.notifier)
                          .setPushEnabled(value);
                    },
                  ),
                  Divider(
                    height: 1,
                    color: colors.surfaceElevated,
                    indent: FacteurSpacing.space4,
                    endIndent: FacteurSpacing.space4,
                  ),
                  // Email Digest
                  _buildToggleTile(
                    context,
                    icon: Icons.email_outlined,
                    title: 'Résumé par email',
                    subtitle: 'Newsletter hebdomadaire avec vos highlights',
                    value: settings.emailDigestEnabled,
                    onChanged: (value) {
                      ref
                          .read(notificationsSettingsProvider.notifier)
                          .setEmailDigestEnabled(value);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: FacteurSpacing.space4),

            // Note explicative
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space2,
              ),
              child: Text(
                'Les notifications push ne sont pas encore actives. '
                'Cette fonctionnalité sera disponible prochainement.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = context.facteurColors;

    return Opacity(
      opacity: 0.5, // Grayed out
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
                  Row(
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(width: FacteurSpacing.space2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space2,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withOpacity(0.1),
                          borderRadius:
                              BorderRadius.circular(FacteurRadius.small),
                        ),
                        child: Text(
                          'Arrive bientôt !',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.primary,
                                    fontSize: 10,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: null, // Disabled
              activeColor: colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
