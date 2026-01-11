import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q6 : "Quand tu lis, tu aimes..."
/// Réponses tranchées vs nuancées
class ResponseStyleQuestion extends ConsumerWidget {
  const ResponseStyleQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedStyle = state.answers.responseStyle;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '💭',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Quand tu lis, tu aimes...',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Quel ton te parle le plus ?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options binaires
          Row(
            children: [
              Expanded(
                child: BinarySelectionCard(
                  emoji: '⚔️',
                  label: 'Des avis tranchés',
                  subtitle: 'Des opinions claires',
                  isSelected: selectedStyle == 'decisive',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectResponseStyle('decisive');
                  },
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: BinarySelectionCard(
                  emoji: '🤔',
                  label: 'Toutes les perspectives',
                  subtitle: 'Voir tous les angles',
                  isSelected: selectedStyle == 'nuanced',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectResponseStyle('nuanced');
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
