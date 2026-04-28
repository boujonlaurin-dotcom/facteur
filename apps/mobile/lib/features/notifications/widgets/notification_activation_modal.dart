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

/// Affiche la modal d'activation comme dialogue flottant translucide
/// (pattern aligné sur `digest_welcome_modal.dart`).
Future<void> showNotificationActivationModal(
  BuildContext context,
  WidgetRef ref, {
  required ActivationTrigger trigger,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    useRootNavigator: true,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space6,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: NotificationActivationModal(trigger: trigger),
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

    return Material(
      color: colors.backgroundPrimary,
      borderRadius: BorderRadius.circular(FacteurRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            FacteurSpacing.space4,
            FacteurSpacing.space6,
            FacteurSpacing.space4,
            FacteurSpacing.space4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Mieux s'informer, à son rythme",
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Center(
                child: Image.asset(
                  'assets/notifications/facteur_avatar.png',
                  height: 96,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                "Fatigué·e d'avoir trop d'infos ?",
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space4),
              _BulletPoint(
                text: "Un message par jour, à l'heure que tu préfères.",
              ),
              const SizedBox(height: FacteurSpacing.space2),
              _BulletPoint(
                text:
                    "Pas de breaking news, zéro tactique pour te faire scroller.",
              ),
              const SizedBox(height: FacteurSpacing.space2),
              _BulletPoint(
                text:
                    "L'essentiel filtré pour toi, quand tu es prêt·e à le recevoir.",
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                "Un exemple de ce que Facteur peut t'envoyer :",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space2),
              _NotificationPreview(timeSlot: _timeSlot),
              const SizedBox(height: FacteurSpacing.space6),
              const _SectionHeader(label: 'Définis ton rythme'),
              const SizedBox(height: FacteurSpacing.space3),
              PresetSelector(
                value: _preset,
                onChanged: (p) {
                  setState(() => _preset = p);
                  ref
                      .read(analyticsServiceProvider)
                      .trackModalNotifPresetChanged(preset: p);
                },
              ),
              const SizedBox(height: FacteurSpacing.space4),
              const _SectionHeader(label: 'À quel moment ?'),
              const SizedBox(height: FacteurSpacing.space3),
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
                      borderRadius: BorderRadius.circular(FacteurRadius.large),
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

/// Bullet line "✓ texte" — alternative légère à un paragraphe bloc pour
/// rendre lisible le pitch de la modal.
class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_rounded, size: 18, color: colors.primary),
        const SizedBox(width: FacteurSpacing.space2),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// Mini-titre de section (bodySmall bold, secondaire) pour introduire le
/// `PresetSelector` et le `TimeSlotSelector`.
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
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
    final timeLabel = timeSlot == NotifTimeSlot.morning ? '07:30' : '19:00';

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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/notifications/facteur_avatar.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
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
