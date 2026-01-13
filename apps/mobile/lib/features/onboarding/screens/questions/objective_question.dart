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
            '⚡',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            "Qu'est-ce qui vous épuise le plus dans l'information aujourd'hui ?",
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Identifions le problème principal',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            emoji: '📢',
            label: 'Le Bruit',
            subtitle: "Trop d'info, impossible de trier.",
            isSelected: selectedObjective == 'noise',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectObjective('noise');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '⚖️',
            label: 'Les Biais',
            subtitle: 'Doute permanent sur la neutralité.',
            isSelected: selectedObjective == 'bias',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectObjective('bias');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '😰',
            label: "L'Anxiété",
            subtitle: 'Le sentiment que le monde devient fou.',
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
