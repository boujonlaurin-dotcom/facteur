import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q13 : "Pourquoi veux-tu consommer + de contenu ?" (Conditionnel)
/// Question motivationnelle, affichée uniquement si gamificationEnabled = true
class PersonalGoalQuestion extends ConsumerWidget {
  const PersonalGoalQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedGoal = state.answers.personalGoal;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '💪',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Pourquoi veux-tu consommer\n+ de contenu ?',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Pour te motiver avec des messages personnalisés',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            emoji: '🧠',
            label: 'Devenir plus cultivé',
            subtitle: 'Enrichir mes connaissances générales',
            isSelected: selectedGoal == 'culture',
            onTap: () {
              ref
                  .read(onboardingProvider.notifier)
                  .selectPersonalGoal('culture');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '💼',
            label: 'Progresser dans mon travail',
            subtitle: 'Améliorer mes compétences professionnelles',
            isSelected: selectedGoal == 'work',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectPersonalGoal('work');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '💬',
            label: 'Avoir des conversations intéressantes',
            subtitle: 'Enrichir mes échanges sociaux',
            isSelected: selectedGoal == 'conversations',
            onTap: () {
              ref
                  .read(onboardingProvider.notifier)
                  .selectPersonalGoal('conversations');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '🎯',
            label: 'Atteindre un objectif d\'apprentissage',
            subtitle: 'Me former sur un sujet précis',
            isSelected: selectedGoal == 'learning',
            onTap: () {
              ref
                  .read(onboardingProvider.notifier)
                  .selectPersonalGoal('learning');
            },
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
