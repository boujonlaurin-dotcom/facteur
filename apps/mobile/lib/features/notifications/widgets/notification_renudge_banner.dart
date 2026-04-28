import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import '../providers/notification_renudge_provider.dart';
import 'notification_activation_modal.dart';

/// Banner *re-nudge* affiché en haut/bas du DigestScreen pour les utilisateurs
/// qui ont refusé l'activation initiale (cf brief §5).
class NotificationRenudgeBanner extends ConsumerStatefulWidget {
  const NotificationRenudgeBanner({super.key});

  @override
  ConsumerState<NotificationRenudgeBanner> createState() =>
      _NotificationRenudgeBannerState();
}

class _NotificationRenudgeBannerState
    extends ConsumerState<NotificationRenudgeBanner> {
  bool _trackedShown = false;

  @override
  Widget build(BuildContext context) {
    final shouldShow = ref.watch(notificationRenudgeShouldShowProvider);
    if (!shouldShow) return const SizedBox.shrink();

    if (!_trackedShown) {
      _trackedShown = true;
      final count =
          ref.read(notificationsSettingsProvider).renudgeShownCount + 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(notificationsSettingsProvider.notifier).recordRenudgeShown();
        ref
            .read(analyticsServiceProvider)
            .trackRenudgeShown(displayCount: count);
      });
    }

    final colors = context.facteurColors;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space3,
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.08),
        border: Border.all(color: colors.primary.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(FacteurRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Facteur prend tout son sens avec une routine quotidienne.",
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            "Donne-lui une chance pendant 7 jours — désactive en 1 clic si ça te dérange.",
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    ref
                        .read(analyticsServiceProvider)
                        .trackRenudgeConfirmed();
                    await showNotificationActivationModal(
                      context,
                      ref,
                      trigger: ActivationTrigger.renudge,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.medium),
                    ),
                  ),
                  child: const Text('Activer mon Facteur journalier'),
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              TextButton(
                onPressed: () {
                  ref.read(analyticsServiceProvider).trackRenudgeDismissed();
                  setState(() {}); // banner se ferme via le compteur déjà MAJ
                },
                child: Text(
                  'Pas maintenant',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
