import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/api/notification_preferences_api_service.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../alerts/providers/alerts_provider.dart';
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
              _SectionHeader(title: 'Alertes'),
              const SizedBox(height: FacteurSpacing.space3),
              const _AlertsRow(),
              const SizedBox(height: FacteurSpacing.space6),
              _SectionHeader(title: 'Horaire'),
              const SizedBox(height: FacteurSpacing.space3),
              TimeSlotSelector(
                value: settings.timeSlot,
                onChanged: (slot) => unawaited(notifier.setTimeSlot(slot)),
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                _scheduleDescription(settings.timeSlot),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: FacteurSpacing.space6),
            _GoodNewsToggle(
              enabled: settings.goodNewsEnabled,
              timeSlot: settings.goodNewsTimeSlot,
              onToggle: (value) =>
                  unawaited(notifier.setGoodNewsEnabled(value)),
              onTimeSlotChanged: (slot) =>
                  unawaited(notifier.setGoodNewsTimeSlot(slot)),
            ),
          ],
        ),
      ),
    );
  }

  String _scheduleDescription(NotifTimeSlot slot) {
    final hour = slot == NotifTimeSlot.morning ? '07:30' : '19:00';
    // « Rien d'autre » ne tient plus depuis que les alertes existent : elles
    // partent dans la même passe. Autant le dire, c'est justement l'argument.
    return "Tu reçois ton récap chaque jour à $hour. "
        "Tes alertes arrivent au même moment, sans bruit.";
  }
}

/// Accès à l'écran « Mes alertes » — le réglage qui a remplacé le sélecteur
/// de rythme (le préset ne pilotait plus que la pépite hebdo, supprimée).
///
/// Le compteur « x/5 » est affiché dès que la liste est chargée ; en cours de
/// chargement ou en erreur on n'affiche rien plutôt qu'un compte faux.
class _AlertsRow extends ConsumerWidget {
  const _AlertsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);
    final countLabel = ref.watch(alertsProvider).maybeWhen(
          data: (alerts) => '${alerts.activeCount}/${alerts.cap}',
          orElse: () => '',
        );

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(FacteurRadius.large),
      child: InkWell(
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        onTap: () => context.pushNamed(RouteNames.alerts),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.surfaceElevated),
          ),
          padding: const EdgeInsets.all(FacteurSpacing.space4),
          child: Row(
            children: [
              Icon(Icons.notifications_none, color: colors.primary, size: 24),
              const SizedBox(width: FacteurSpacing.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mes alertes',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Être prévenu quand une source rare publie.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (countLabel.isNotEmpty) ...[
                Text(
                  countLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textTertiary),
                ),
                const SizedBox(width: FacteurSpacing.space2),
              ],
              Icon(Icons.chevron_right, color: colors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
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

/// Toggle indépendant du canal « Bonnes nouvelles du jour ».
///
/// Vit séparément du toggle digest principal pour respecter la règle
/// CRITIQUE : les deux opt-ins ne doivent jamais être couplés. Visible
/// même quand le push principal est OFF, pour que la promesse reste
/// découvrable depuis le profil.
class _GoodNewsToggle extends StatelessWidget {
  final bool enabled;
  final NotifTimeSlot timeSlot;
  final ValueChanged<bool> onToggle;
  final ValueChanged<NotifTimeSlot> onTimeSlotChanged;

  const _GoodNewsToggle({
    required this.enabled,
    required this.timeSlot,
    required this.onToggle,
    required this.onTimeSlotChanged,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🌱 Bonnes nouvelles du jour',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Une dose d'espoir, à un horaire dédié.",
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                onChanged: onToggle,
                activeColor: colors.primary,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: FacteurSpacing.space4),
            TimeSlotSelector(
              value: timeSlot,
              onChanged: onTimeSlotChanged,
            ),
          ],
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
