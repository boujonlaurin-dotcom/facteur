import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Q1 : "Faisons le constat."
/// Sélection des problèmes principaux avec l'info
class ObjectiveQuestion extends ConsumerWidget {
  const ObjectiveQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedObjective = state.answers.objective;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Question
          Text(
            OnboardingStrings.q1Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            OnboardingStrings.q1Subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.start,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            emoji: '🔊', // Bruit
            label: OnboardingStrings.q1NoiseLabel,
            subtitle: OnboardingStrings.q1NoiseSubtitle,
            isSelected: selectedObjective == 'noise',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectObjective('noise');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '⚖️', // Biais
            label: OnboardingStrings.q1BiasLabel,
            subtitle: OnboardingStrings.q1BiasSubtitle,
            isSelected: selectedObjective == 'bias',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectObjective('bias');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '👎', // Négativité
            label: OnboardingStrings.q1AnxietyLabel,
            subtitle: OnboardingStrings.q1AnxietySubtitle,
            isSelected: selectedObjective == 'anxiety',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectObjective('anxiety');
            },
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
