import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q8b : "Ton objectif hebdo ?"
/// Choix du nombre de contenus par semaine
class WeeklyGoalQuestion extends ConsumerWidget {
  const WeeklyGoalQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedGoal = state.answers.weeklyGoal;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '🎯',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Ton objectif hebdo ?',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Combien de contenus veux-tu consommer par semaine ?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            emoji: '🌱',
            label: '5 contenus',
            subtitle: '~20 min par semaine • Tranquille',
            isSelected: selectedGoal == 5,
            onTap: () {
              ref.read(onboardingProvider.notifier).selectWeeklyGoal(5);
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // Option recommandée
          Stack(
            clipBehavior: Clip.none,
            children: [
              SelectionCard(
                emoji: '🌿',
                label: '10 contenus',
                subtitle: '~40 min par semaine • Équilibré',
                isSelected: selectedGoal == 10,
                onTap: () {
                  ref.read(onboardingProvider.notifier).selectWeeklyGoal(10);
                },
              ),
              Positioned(
                top: -8,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space2,
                    vertical: FacteurSpacing.space1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(FacteurRadius.small),
                  ),
                  child: Text(
                    'Recommandé',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '🌳',
            label: '15 contenus',
            subtitle: '~1h par semaine • Ambitieux',
            isSelected: selectedGoal == 15,
            onTap: () {
              ref.read(onboardingProvider.notifier).selectWeeklyGoal(15);
            },
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
