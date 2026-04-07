import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../providers/onboarding_provider.dart';

/// Barre de progression pour l'onboarding
/// Affiche 3 segments correspondant aux 3 sections
class OnboardingProgressBar extends StatelessWidget {
  final double sectionProgress;
  final OnboardingSection section;

  const OnboardingProgressBar({
    super.key,
    required this.sectionProgress,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      children: List.generate(OnboardingSection.values.length, (index) {
        final sectionEnum = OnboardingSection.values[index];
        final double segmentProgress;
        if (sectionEnum.number < section.number) {
          segmentProgress = 1.0;
        } else if (sectionEnum.number == section.number) {
          segmentProgress = sectionProgress;
        } else {
          segmentProgress = 0.0;
        }

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 0 : 3,
              right: index == OnboardingSection.values.length - 1 ? 0 : 3,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: segmentProgress),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return LinearProgressIndicator(
                    value: value,
                    backgroundColor: colors.surfaceElevated,
                    valueColor: AlwaysStoppedAnimation(colors.primary),
                    minHeight: 6,
                  );
                },
              ),
            ),
          ),
        );
      }),
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
