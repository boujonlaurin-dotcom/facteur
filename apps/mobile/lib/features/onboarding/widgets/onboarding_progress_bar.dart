import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../providers/onboarding_provider.dart';
import '../onboarding_strings.dart';

/// Barre de progression pour l'onboarding
/// Affiche la progression globale et l'indicateur de section
class OnboardingProgressBar extends StatelessWidget {
  final double progress;
  final OnboardingSection section;

  const OnboardingProgressBar({
    super.key,
    required this.progress,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: context.facteurColors.surfaceElevated,
                  valueColor: AlwaysStoppedAnimation(
                    context.facteurColors.primary,
                  ),
                  minHeight: 6,
                );
              },
            ),
          ),
        ),
        const SizedBox(width: FacteurSpacing.space3),
        Text(
          OnboardingStrings.sectionCount(section.number, 3),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

/// Indicateur de progression en points
class OnboardingDotsIndicator extends StatelessWidget {
  final int currentIndex;
  final int totalDots;

  const OnboardingDotsIndicator({
    super.key,
    required this.currentIndex,
    required this.totalDots,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalDots, (index) {
        final isActive = index <= currentIndex;
        final isCurrent = index == currentIndex;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isCurrent ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? colors.primary : colors.surfaceElevated,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
