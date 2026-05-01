import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/nudge_service.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/widget_service.dart';

/// Bottom sheet nudging the user to pin the Facteur widget on their home
/// screen, then guiding them to disable Google Discover so the widget
/// actually replaces the doomscroll habit.
///
/// Two steps in a single sheet (Android only, shown once after onboarding):
///   1. "Why the widget" — friendly pitch + pin CTA
///   2. "Disable Discover" — generic instructions across launchers
class WidgetPinNudge {
  static Future<bool> shouldShow() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    return NudgeService().canShow(NudgeIds.widgetPinAndroid);
  }

  static Future<void> markShown() =>
      NudgeService().markSeen(NudgeIds.widgetPinAndroid);

  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final shouldDisplay = await shouldShow();
    if (!shouldDisplay || !context.mounted) return;

    await markShown();

    if (!context.mounted) return;

    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.trackWidgetPinNudgeShown());

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _WidgetPinSheet(analytics: analytics),
      ),
    );
  }
}

class _WidgetPinSheet extends StatefulWidget {
  const _WidgetPinSheet({required this.analytics});

  final AnalyticsService analytics;

  @override
  State<_WidgetPinSheet> createState() => _WidgetPinSheetState();
}

class _WidgetPinSheetState extends State<_WidgetPinSheet> {
  int _step = 0;

  Future<void> _onPinPressed() async {
    unawaited(widget.analytics.trackWidgetPinRequested());
    await WidgetService.requestPinWidget();
    if (!mounted) return;
    unawaited(widget.analytics.trackDiscoverDisableStepShown());
    setState(() => _step = 1);
  }

  void _onLater() {
    unawaited(widget.analytics.trackWidgetPinDismissed());
    Navigator.pop(context);
  }

  void _onDiscoverDone() {
    unawaited(widget.analytics.trackDiscoverDisableConfirmed());
    Navigator.pop(context);
  }

  void _onDiscoverSkip() {
    unawaited(widget.analytics.trackDiscoverDisableSkipped());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FacteurRadius.large),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _step == 0
              ? _StepWhy(
                  onPin: _onPinPressed,
                  onLater: _onLater,
                )
              : _StepDisableDiscover(
                  onDone: _onDiscoverDone,
                  onSkip: _onDiscoverSkip,
                ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: colors.textTertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _StepWhy extends StatelessWidget {
  const _StepWhy({required this.onPin, required this.onLater});

  final VoidCallback onPin;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('step_why'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _DragHandle(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            PhosphorIcons.squaresFour(PhosphorIconsStyle.fill),
            color: colors.primary,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Et si tu remplaçais ton scroll Google News ?',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Pose le widget Facteur sur ton écran d\'accueil — tes 5 essentiels du jour, à portée de pouce.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _Bullet(
          icon: PhosphorIcons.heart(PhosphorIconsStyle.fill),
          title: "Tes sources, pas l'algo",
          subtitle: "Tu choisis qui tu lis. Personne d'autre.",
        ),
        const SizedBox(height: 12),
        _Bullet(
          icon: PhosphorIcons.shieldCheck(PhosphorIconsStyle.fill),
          title: 'Zéro putaclic',
          subtitle: "On filtre, tu lis l'essentiel.",
        ),
        const SizedBox(height: 12),
        _Bullet(
          icon: PhosphorIcons.clock(PhosphorIconsStyle.fill),
          title: "Un coup d'œil suffit",
          subtitle: '5 articles par jour, puis tu refermes.',
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onPin,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: colors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FacteurRadius.large),
              ),
            ),
            child: const Text(
              'Ajouter le widget',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onLater,
          child: Text(
            'Plus tard',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepDisableDiscover extends StatelessWidget {
  const _StepDisableDiscover({required this.onDone, required this.onSkip});

  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('step_discover'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DragHandle(),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
              color: colors.primary,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Dernière étape : libère ton écran d\'accueil',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Le feed Google Discover (à droite de ton écran d\'accueil) pousse à scroller sans fin. Désactive-le pour laisser ton widget Facteur faire le job.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _NumberedStep(
          n: 1,
          text: 'Appui long sur ton écran d\'accueil.',
        ),
        const SizedBox(height: 10),
        _NumberedStep(
          n: 2,
          text: 'Touche "Paramètres" (ou "Préférences").',
        ),
        const SizedBox(height: 10),
        _NumberedStep(
          n: 3,
          text: 'Désactive "Afficher Google" / "Discover" / "Swipe pour Google".',
        ),
        const SizedBox(height: 16),
        Text(
          'Le nom change un peu selon ton téléphone (Pixel, Samsung, Xiaomi…). Cherche l\'option Google ou Discover.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textTertiary,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onDone,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: colors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FacteurRadius.large),
              ),
            ),
            child: const Text(
              'C\'est fait !',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onSkip,
          child: Text(
            'Passer cette étape',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: colors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$n',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
