import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q4 : "Tu préfères..."
/// Dernière question de la Section 1
class ApproachQuestion extends ConsumerWidget {
  const ApproachQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedApproach = state.answers.approach;
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
            'Tu préfères...',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Comment aimes-tu consommer l\'information ?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options avec présentation binaire
          Row(
            children: [
              Expanded(
                child: BinarySelectionCard(
                  emoji: '⚡',
                  label: 'Aller droit au but',
                  subtitle: 'L\'essentiel, rapidement',
                  isSelected: selectedApproach == 'direct',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectApproach('direct');
                  },
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: BinarySelectionCard(
                  emoji: '🌿',
                  label: 'Prendre le temps',
                  subtitle: 'Explorer en profondeur',
                  isSelected: selectedApproach == 'detailed',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectApproach('detailed');
                  },
                ),
              ),
            ],
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
