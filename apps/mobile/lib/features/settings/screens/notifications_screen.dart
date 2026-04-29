import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/api/notification_preferences_api_service.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../notifications/widgets/preset_selector.dart';
import '../../notifications/widgets/time_slot_selector.dart';
import '../providers/notifications_settings_provider.dart';

/// Écran de gestion des préférences de notifications.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final settings = ref.watch(notificationsSettingsProvider);
    final notifier = ref.read(notificationsSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PushToggle(
              value: settings.pushEnabled,
              onChanged: (value) {
                final wasEnabled = settings.pushEnabled;
                unawaited(notifier.setPushEnabled(value));
                if (wasEnabled && !value) {
                  unawaited(
                    ref
                        .read(analyticsServiceProvider)
                        .trackNotifDisabled(source: 'in_app'),
                  );
                }
              },
            ),
            const SizedBox(height: FacteurSpacing.space4),
            if (settings.pushEnabled) ...[
              _SectionHeader(title: 'Rythme'),
              const SizedBox(height: FacteurSpacing.space3),
              PresetSelector(
                value: settings.preset,
                onChanged: (preset) {
                  final from = settings.preset;
                  unawaited(notifier.setPreset(preset));
                  if (from != preset) {
                    unawaited(
                      ref
                          .read(analyticsServiceProvider)
                          .trackNotifSettingsChanged(
                            fromPreset: from,
                            toPreset: preset,
                          ),
                    );
                  }
                },
              ),
              const SizedBox(height: FacteurSpacing.space6),
              _SectionHeader(title: 'Horaire'),
              const SizedBox(height: FacteurSpacing.space3),
              TimeSlotSelector(
                value: settings.timeSlot,
                onChanged: (slot) => unawaited(notifier.setTimeSlot(slot)),
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                _scheduleDescription(settings.preset, settings.timeSlot),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _scheduleDescription(NotifPreset preset, NotifTimeSlot slot) {
    final hour = slot == NotifTimeSlot.morning ? '07:30' : '19:00';
    if (preset == NotifPreset.curieux) {
      return "Tu reçois ton récap chaque jour à $hour, "
          "et la pépite des Fact·eur·isses le vendredi à 18:00.";
    }
    return "Tu reçois ton récap chaque jour à $hour. Rien d'autre.";
  }
}

class _PushToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PushToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.surfaceElevated),
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined,
              color: colors.primary, size: 24),
          const SizedBox(width: FacteurSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications push',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  "Le Facteur passe sur ton téléphone à l'heure choisie.",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
