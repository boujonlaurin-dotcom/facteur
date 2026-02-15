import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/services/push_notification_service.dart';
import '../providers/notifications_settings_provider.dart';

/// Écran de gestion des préférences de notifications
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  Map<String, dynamic>? _diagnostics;
  bool _loadingDiagnostics = true;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() => _loadingDiagnostics = true);
    try {
      final diag = await PushNotificationService().getDiagnostics();
      if (mounted) {
        setState(() {
          _diagnostics = diag;
          _loadingDiagnostics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingDiagnostics = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  // Email Digest (disabled for now - feature not implemented)
                  _buildToggleTile(
                    context,
                    icon: Icons.email_outlined,
                    title: 'Résumé par email',
                    subtitle: 'Newsletter hebdomadaire avec vos highlights',
                    value: settings.emailDigestEnabled,
                    onChanged: null,
                    enabled: false,
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
                'Recevez une notification chaque matin à 8h '
                'quand votre Essentiel du Jour est prêt.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),

            const SizedBox(height: FacteurSpacing.space6),

            // Section Diagnostic
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space2,
              ),
              child: Text(
                'Diagnostic',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ),

            const SizedBox(height: FacteurSpacing.space2),

            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
                border: Border.all(color: colors.surfaceElevated),
              ),
              child: _loadingDiagnostics
                  ? const Padding(
                      padding: EdgeInsets.all(FacteurSpacing.space4),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        _buildDiagnosticRow(
                          context,
                          label: 'Notifications autorisées',
                          value: _diagnostics?['notificationsEnabled'] == true,
                        ),
                        Divider(
                          height: 1,
                          color: colors.surfaceElevated,
                          indent: FacteurSpacing.space4,
                          endIndent: FacteurSpacing.space4,
                        ),
                        _buildDiagnosticRow(
                          context,
                          label: 'Alarmes exactes',
                          value: _diagnostics?['exactAlarmsGranted'] == true,
                        ),
                        Divider(
                          height: 1,
                          color: colors.surfaceElevated,
                          indent: FacteurSpacing.space4,
                          endIndent: FacteurSpacing.space4,
                        ),
                        _buildDiagnosticRow(
                          context,
                          label: 'Notification planifiée',
                          value: _diagnostics?['digestScheduled'] == true,
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: FacteurSpacing.space4),

            // Bouton test notification
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await PushNotificationService().sendTestNotification();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notification test envoyée'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Envoyer une notification test'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary),
                  padding: const EdgeInsets.symmetric(
                    vertical: FacteurSpacing.space3,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FacteurRadius.large),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticRow(
    BuildContext context, {
    required String label,
    required bool value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Icon(
            value ? Icons.check_circle : Icons.cancel,
            color: value ? Colors.green : Colors.red,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool enabled = true,
  }) {
    final colors = context.facteurColors;
    final opacity = enabled ? 1.0 : 0.5;

    return Opacity(
      opacity: opacity,
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
              onChanged: enabled ? onChanged : null,
              activeColor: colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
