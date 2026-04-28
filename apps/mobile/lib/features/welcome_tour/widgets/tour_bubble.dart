import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Bulle coachmark affichée au-dessus ou en-dessous de la cible, selon le
/// positionnement calculé par `TutorialCoachMark`.
///
/// Style : titre Fraunces 20pt (serif premium), body DM Sans 15pt, petit
/// stamp Courier Prime "ÉTAPE N/3" en ocre rouge pour le rythme postal.
class TourBubble extends StatelessWidget {
  const TourBubble({
    super.key,
    required this.stamp,
    required this.title,
    required this.body,
    required this.isLast,
    required this.onSkip,
    required this.onNext,
  });

  final String stamp;
  final String title;
  final String body;
  final bool isLast;
  final VoidCallback onSkip;
  final VoidCallback onNext;

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
              Text(
                stamp,
                style: FacteurTypography.stamp(colors.textStamp),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                title,
                style: FacteurTypography.serifTitle(colors.textPrimary),
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                body,
                style: FacteurTypography.bodyMedium(colors.textSecondary),
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textTertiary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space3,
                        vertical: FacteurSpacing.space2,
                      ),
                    ),
                    child: const Text(
                      'Passer',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space4,
                        vertical: FacteurSpacing.space3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.medium),
                      ),
                    ),
                    child: Text(
                      isLast ? 'Commencer' : 'Suivant',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
