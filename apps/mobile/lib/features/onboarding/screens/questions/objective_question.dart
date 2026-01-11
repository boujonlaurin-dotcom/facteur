import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q1 : "Pourquoi es-tu là ?"
/// Permet à l'utilisateur de définir son objectif principal
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

          // Illustration
          const Text(
            '👋',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Pourquoi es-tu là ?',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Dis-nous ce qui t\'amène',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            emoji: '📚',
            label: 'Apprendre de nouvelles choses',
            subtitle: 'Élargir mes connaissances au quotidien',
            isSelected: selectedObjective == 'learn',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectObjective('learn');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '🌍',
            label: 'Me cultiver et comprendre le monde',
            subtitle: 'Avoir une vision plus large',
            isSelected: selectedObjective == 'culture',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectObjective('culture');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '💼',
            label: 'Faire ma veille professionnelle',
            subtitle: 'Rester pertinent dans mon domaine',
            isSelected: selectedObjective == 'work',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectObjective('work');
            },
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
