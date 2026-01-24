import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';

import 'package:go_router/go_router.dart';
import '../../../../config/routes.dart';
import '../../../../widgets/design/facteur_logo.dart';

/// Welcome Screen: "Bienvenue sur Facteur !"
/// Replaces the old IntroScreen1.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  void _openManifesto(BuildContext context) {
    context.pushNamed(RouteNames.about);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Logo
          const Center(child: FacteurLogo(size: 42)),

          const SizedBox(height: FacteurSpacing.space6),

          // Headline
          Text(
            OnboardingStrings.welcomeTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Subtext
          Text(
            OnboardingStrings.welcomeSubtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.textSecondary,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),

          // Manifesto Button
          TextButton(
            onPressed: () => _openManifesto(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: colors.textSecondary,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  OnboardingStrings.welcomeManifestoButton,
                  style: const TextStyle(
                    fontSize: 15,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_outward_rounded, size: 16),
              ],
            ),
          ),

          const SizedBox(height: 12),

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
              OnboardingStrings.welcomeStartButton,
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
