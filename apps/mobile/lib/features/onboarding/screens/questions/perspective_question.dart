import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q5 : "Tu préfères avoir..."
/// Big-picture vs details
class PerspectiveQuestion extends ConsumerWidget {
  const PerspectiveQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedPerspective = state.answers.perspective;
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
            'Tu préfères avoir...',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Comment aimes-tu appréhender l\'info ?',
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
                  emoji: '🔭',
                  label: 'La vue d\'ensemble',
                  subtitle: 'Comprendre les grandes lignes',
                  isSelected: selectedPerspective == 'big_picture',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectPerspective('big_picture');
                  },
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: BinarySelectionCard(
                  emoji: '🔬',
                  label: 'Dans le détail',
                  subtitle: 'Aller en profondeur',
                  isSelected: selectedPerspective == 'details',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectPerspective('details');
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
