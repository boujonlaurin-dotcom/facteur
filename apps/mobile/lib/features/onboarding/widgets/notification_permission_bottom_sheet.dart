import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/services/push_notification_service.dart';

/// Shows a bottom sheet to let the user enable or skip notification permission
/// after onboarding completion.
Future<void> showNotificationPermissionBottomSheet(
    BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: const _NotificationPermissionContent(),
    ),
  );
}

class _NotificationPermissionContent extends StatelessWidget {
  const _NotificationPermissionContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FacteurRadius.large),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Icon
          Icon(
            Icons.notifications_active_outlined,
            size: 48,
            color: colors.primary,
          ),

          const SizedBox(height: FacteurSpacing.space4),

          Text(
            'Rester informé chaque matin ?',
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Recevez une notification à 8h quand votre '
            'Essentiel du Jour est prêt.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Activer button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _onEnable(context),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: FacteurSpacing.space4),
                backgroundColor: colors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(FacteurRadius.large),
                ),
              ),
              child: const Text(
                'Activer les notifications',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // Plus tard button
          TextButton(
            onPressed: () => _onSkip(context),
            child: Text(
              'Plus tard',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space2),
        ],
      ),
    );
  }

  Future<void> _onEnable(BuildContext context) async {
    final pushService = PushNotificationService();
    await pushService.requestPermission();
    await pushService.requestExactAlarmPermission();
    await pushService.scheduleDailyDigestNotification();

    // Persister le choix
    final box = Hive.box<dynamic>('settings');
    await box.put('push_notifications_enabled', true);

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onSkip(BuildContext context) async {
    // Persister le refus
    final box = Hive.box<dynamic>('settings');
    await box.put('push_notifications_enabled', false);

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
