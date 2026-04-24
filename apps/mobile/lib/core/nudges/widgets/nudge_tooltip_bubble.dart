import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Bulle coachmark pour les feature nudges — DM Sans uniquement (contrairement
/// à [TourBubble] qui utilise Fraunces + Courier Prime pour le welcome tour).
///
/// Pensée pour être posée par un `TutorialCoachMark` spotlight ou en
/// overlay manuel (Stack + Positioned). Rendue par un parent qui sait où la
/// positionner.
class NudgeTooltipBubble extends StatelessWidget {
  const NudgeTooltipBubble({
    super.key,
    required this.body,
    required this.onDismiss,
    this.title,
    this.dismissLabel = 'Compris',
  });

  final String body;
  final String? title;
  final VoidCallback onDismiss;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(FacteurSpacing.space4),
          decoration: BoxDecoration(
            color: colors.surfacePaper,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: FacteurTypography.bodyLarge(colors.textPrimary)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: FacteurSpacing.space2),
              ],
              Text(
                body,
                style: FacteurTypography.bodyMedium(colors.textSecondary),
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textTertiary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space3,
                      vertical: FacteurSpacing.space2,
                    ),
                  ),
                  child: Text(
                    dismissLabel,
                    style: FacteurTypography.labelLarge(colors.textTertiary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
