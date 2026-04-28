import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/api/notification_preferences_api_service.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/services/push_notification_service.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import 'preset_selector.dart';
import 'time_slot_selector.dart';

/// Trigger d'affichage de la modal — utilisé pour l'event tracking.
enum ActivationTrigger { onboarding, update, renudge }

/// Affiche la modal d'activation full-screen.
Future<void> showNotificationActivationModal(
  BuildContext context,
  WidgetRef ref, {
  required ActivationTrigger trigger,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => NotificationActivationModal(trigger: trigger),
    ),
  );
}

class NotificationActivationModal extends ConsumerStatefulWidget {
  final ActivationTrigger trigger;

  const NotificationActivationModal({super.key, required this.trigger});

  @override
  ConsumerState<NotificationActivationModal> createState() =>
      _NotificationActivationModalState();
}

class _NotificationActivationModalState
    extends ConsumerState<NotificationActivationModal> {
  late NotifPreset _preset;
  late NotifTimeSlot _timeSlot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(notificationsSettingsProvider);
    _preset = current.preset;
    _timeSlot = current.timeSlot;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsServiceProvider).trackModalNotifShown(
            trigger: widget.trigger,
          );
    });
  }

  Future<void> _onConfirm() async {
    if (_busy) return;
    setState(() => _busy = true);

    final analytics = ref.read(analyticsServiceProvider);
    final notifier = ref.read(notificationsSettingsProvider.notifier);

    final granted = await PushNotificationService().requestPermission();
    if (granted) {
      await PushNotificationService().requestExactAlarmPermission();
    }

    await notifier.confirmActivation(
      preset: _preset,
      timeSlot: _timeSlot,
      osGranted: granted,
    );

    analytics.trackModalNotifConfirmed(
      preset: _preset,
      timeSlot: _timeSlot,
      osPermissionGranted: granted,
    );

    if (!mounted) return;
    Navigator.of(context).pop();

    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Tu peux changer d'avis dans les paramètres de ton téléphone.",
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);

    await ref.read(notificationsSettingsProvider.notifier).recordRefusal();
    ref.read(analyticsServiceProvider).trackModalNotifDismissed();

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                'Choisis ton rythme',
                style: theme.textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                "Tu veux éviter le trop-plein d'informations ?\n"
                "Voici comment Facteur t'y aide quotidiennement, en douceur.",
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space6),
              Text(
                "Un message par jour, à l'heure que tu préfères.\n"
                "Zéro breaking news. Pas de tactique pour te faire scroller.\n"
                "On filtre l'essentiel pour toi, au moment où tu es prêt·e à le recevoir.",
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space6),
              _NotificationPreview(timeSlot: _timeSlot),
              const SizedBox(height: FacteurSpacing.space6),
              PresetSelector(
                value: _preset,
                onChanged: (p) {
                  setState(() => _preset = p);
                  ref
                      .read(analyticsServiceProvider)
                      .trackModalNotifPresetChanged(preset: p);
                },
              ),
              const SizedBox(height: FacteurSpacing.space6),
              TimeSlotSelector(
                value: _timeSlot,
                onChanged: (s) {
                  setState(() => _timeSlot = s);
                  ref
                      .read(analyticsServiceProvider)
                      .trackModalNotifTimeChanged(timeSlot: s);
                },
              ),
              const SizedBox(height: FacteurSpacing.space6),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _busy ? null : _onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.large),
                    ),
                  ),
                  child: const Text(
                    'Activer mon Facteur journalier',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              TextButton(
                onPressed: _busy ? null : _onSkip,
                child: Text(
                  'Plus tard',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preview live de la notification (placeholder visuel — l'icône Facteur
/// sera fournie par le design ; en attendant on utilise l'emoji 🧑‍✈️).
class _NotificationPreview extends StatelessWidget {
  final NotifTimeSlot timeSlot;

  const _NotificationPreview({required this.timeSlot});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);
    final timeLabel =
        timeSlot == NotifTimeSlot.morning ? '07:30' : '19:00';

    return Semantics(
      label:
          "Aperçu de la notification : Facteur, $timeLabel, Facteur passé ! Ton récap du jour t'attend.",
      child: Container(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.surfaceElevated),
          borderRadius: BorderRadius.circular(FacteurRadius.large),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🧑‍✈️', style: TextStyle(fontSize: 26)),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Facteur',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· $timeLabel',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text("Facteur passé ! Ton récap du jour t'attend."),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
