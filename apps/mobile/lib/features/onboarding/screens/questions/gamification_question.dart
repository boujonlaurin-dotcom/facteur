import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q8 : "Activer les objectifs ?"
/// Gamification oui/non
class GamificationQuestion extends ConsumerWidget {
  const GamificationQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final gamificationEnabled = state.answers.gamificationEnabled;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '🎮',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Activer les objectifs ?',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Pour te motiver à apprendre régulièrement',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Features gamification
          Container(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
            ),
            child: Column(
              children: [
                _FeatureRow(
                  emoji: '🔥',
                  title: 'Streak quotidien',
                  description: 'Garde ta flamme allumée chaque jour',
                ),
                const SizedBox(height: FacteurSpacing.space3),
                _FeatureRow(
                  emoji: '📊',
                  title: 'Progression hebdo',
                  description: 'Visualise tes objectifs de la semaine',
                ),
              ],
            ),
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Options
          SelectionCard(
            emoji: '✅',
            label: 'Oui, j\'aime me fixer des objectifs',
            isSelected: gamificationEnabled == true,
            onTap: () {
              ref.read(onboardingProvider.notifier).selectGamification(true);
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '🙅',
            label: 'Non, je préfère sans',
            subtitle: 'Tu pourras activer ça plus tard',
            isSelected: gamificationEnabled == false,
            onTap: () {
              ref.read(onboardingProvider.notifier).selectGamification(false);
            },
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;

  const _FeatureRow({
    required this.emoji,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          emoji,
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.facteurColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
