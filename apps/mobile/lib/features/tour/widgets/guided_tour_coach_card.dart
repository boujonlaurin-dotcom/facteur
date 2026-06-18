import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../models/tour_step.dart';
import '../tour_strings.dart';

/// Coach card du tour guidé (cf. proto `Tour guidé Facteur.dc.html`).
///
/// Avatar Facteur rond + pastille « N / 5 », titre Fraunces, corps DM Sans,
/// puces de progression et boutons Passer / Suivant (Terminer sur la dernière
/// étape). La carte de conclusion ([TourStep.done]) masque puces et boutons.
class GuidedTourCoachCard extends StatelessWidget {
  final TourStep step;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const GuidedTourCoachCard({
    super.key,
    required this.step,
    required this.onSkip,
    required this.onNext,
  });

  /// Contour orange du spotlight, repris pour la pastille et l'accent de carte.
  static const Color _spotlight = Color(0xFFE8943F);

  bool get _isDone => step == TourStep.done;
  bool get _isLast => step == TourStep.courrier;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(color: colors.border, width: 0.6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Avatar(badge: _isDone ? null : step.displayIndex),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Text(
                    TourStrings.title(step),
                    style: FacteurTypography.serifTitle(colors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              TourStrings.body(step),
              style: FacteurTypography.bodyMedium(colors.textSecondary),
            ),
            if (!_isDone) ...[
              const SizedBox(height: FacteurSpacing.space4),
              _ProgressDots(active: step.displayIndex),
              const SizedBox(height: FacteurSpacing.space3),
              Row(
                children: [
                  TextButton(
                    onPressed: onSkip,
                    child: Text(
                      TourStrings.skip,
                      style: FacteurTypography.labelLarge(colors.textSecondary),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.pill),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space6,
                        vertical: FacteurSpacing.space3,
                      ),
                    ),
                    child: Text(_isLast ? TourStrings.finish : TourStrings.next),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  /// Numéro de la pastille « N / 5 », ou `null` (carte de conclusion).
  final int? badge;

  const _Avatar({this.badge});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.backgroundSecondary,
              border: Border.all(
                color: GuidedTourCoachCard._spotlight,
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/notifications/facteur_avatar.png',
              fit: BoxFit.cover,
            ),
          ),
          if (badge != null)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: GuidedTourCoachCard._spotlight,
                  borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  border: Border.all(color: colors.surface, width: 1.5),
                ),
                child: Text(
                  '$badge / ${TourStepDisplay.totalSteps}',
                  style: FacteurTypography.labelSmall(Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  /// Index 1-based de la puce active.
  final int active;

  const _ProgressDots({required this.active});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      children: [
        for (var i = 1; i <= TourStepDisplay.totalSteps; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == active ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FacteurRadius.pill),
              color: i == active
                  ? colors.primary
                  : colors.textSecondary.withValues(alpha: 0.3),
            ),
          ),
          if (i < TourStepDisplay.totalSteps) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
