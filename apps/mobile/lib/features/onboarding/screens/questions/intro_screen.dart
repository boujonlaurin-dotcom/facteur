import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';

/// Intro screen: "L'info ressemble à un champ de bataille."
/// Sets the stage for the onboarding with the mission statement.
class IntroScreen extends ConsumerWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '⚔️',
            style: TextStyle(fontSize: 80),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Headline
          Text(
            "L'info ressemble à un champ de bataille.",
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space4),

          // Subtext
          Text(
            "Entre les médias détenus par des milliardaires et les réseaux qui contrôlent l'information, votre attention et vos opinions se vendent aujourd'hui. Facteur vise à être un outil de résistance à ces mécanismes délétères.",
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
              'Reprendre le contrôle',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
