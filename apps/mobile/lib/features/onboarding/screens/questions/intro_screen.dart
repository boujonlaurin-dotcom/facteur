import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';

/// Intro screen 1: "L'info est aujourd'hui un champ de bataille."
/// First part of the mission statement.
class IntroScreen1 extends ConsumerWidget {
  const IntroScreen1({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Headline
          Text(
            OnboardingStrings.intro1Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Subtext
          Text(
            OnboardingStrings.intro1Subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),

          // CTA Button
          ElevatedButton(
            onPressed: () {
              ref.read(onboardingProvider.notifier).continueToIntro2();
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: colors.primary,
            ),
            child: const Text(
              OnboardingStrings.continueButton,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}

/// Intro screen 2: Facteur's mission
/// Second part of the mission statement.
class IntroScreen2 extends ConsumerWidget {
  const IntroScreen2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Headline
          Text(
            OnboardingStrings.intro2Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Subtext
          Text(
            OnboardingStrings.intro2Subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),

          // CTA Button
          ElevatedButton(
            onPressed: () {
              ref.read(onboardingProvider.notifier).continueAfterIntro();
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: colors.primary,
            ),
            child: const Text(
              OnboardingStrings.intro2Button,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
