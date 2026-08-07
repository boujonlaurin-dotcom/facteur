import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/web/web_perf.dart';
import '../services/onboarding_push_priming.dart';

/// Écran d'amorce interne affiché ~quelques secondes après l'étape 3/4.
///
/// Volontairement plus léger que `NotificationActivationModal` (pas de créneau,
/// pas de bonnes nouvelles, pas d'aperçu) : un seul but, capter tôt la
/// permission pour pouvoir relancer un abandon. Seul « Activer » déclenche la
/// vraie pop-up système ; « Plus tard » ne consomme rien.
Future<void> showOnboardingNotifPriming(
  BuildContext context,
  WidgetRef ref, {
  required int step,
}) async {
  // Push local indispo sur Web — no-op (comme showNotificationActivationModal).
  if (!kSupportsPushNotifications) return;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: context.facteurColors.scrim,
    useRootNavigator: true,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space6,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: _OnboardingNotifPriming(step: step),
    ),
  );
}

class _OnboardingNotifPriming extends ConsumerStatefulWidget {
  final int step;

  const _OnboardingNotifPriming({required this.step});

  @override
  ConsumerState<_OnboardingNotifPriming> createState() =>
      _OnboardingNotifPrimingState();
}

class _OnboardingNotifPrimingState
    extends ConsumerState<_OnboardingNotifPriming> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Garde anti-« ref après dispose » (cf. NotificationActivationModal).
      if (!mounted) return;
      ref
          .read(analyticsServiceProvider)
          .trackOnboardingNotifPrimingShown(step: widget.step);
    });
  }

  Future<void> _onAccept() async {
    if (_busy) return;
    setState(() => _busy = true);

    final priming = ref.read(onboardingPushPrimingProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final registered = await priming.acceptAndRegister();
    await analytics.trackOnboardingNotifPrimingAccepted(registered: registered);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);

    await ref.read(onboardingPushPrimingProvider).refuse();
    await ref.read(analyticsServiceProvider).trackOnboardingNotifPrimingRefused();

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
      child: Padding(
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
            // TODO(PO): valider copy — FR sobre, pas d'em-dash, pas de fausse
            // métaphore facteur/lettre.
            Text(
              'Activer les rappels ?',
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              'Reçois un rappel pour reprendre ta configuration et la '
              'terminer en une minute.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space6),
            FilledButton(
              onPressed: _busy ? null : _onAccept,
              child: const Text('Activer les rappels'),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            TextButton(
              onPressed: _busy ? null : _onSkip,
              child: const Text('Plus tard'),
            ),
          ],
        ),
      ),
    );
  }
}
