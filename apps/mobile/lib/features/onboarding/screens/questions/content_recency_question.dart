import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q7 : "Tu préfères..."
/// Actu récente vs analyses intemporelles
class ContentRecencyQuestion extends ConsumerWidget {
  const ContentRecencyQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedRecency = state.answers.contentRecency;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '📅',
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
            'Quel type de contenu t\'attire ?',
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
                  emoji: '📰',
                  label: 'L\'actu du moment',
                  subtitle: 'Ce qui se passe maintenant',
                  isSelected: selectedRecency == 'recent',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectContentRecency('recent');
                  },
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: BinarySelectionCard(
                  emoji: '📚',
                  label: 'Des analyses intemporelles',
                  subtitle: 'Des contenus qui durent',
                  isSelected: selectedRecency == 'timeless',
                  onTap: () {
                    ref
                        .read(onboardingProvider.notifier)
                        .selectContentRecency('timeless');
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
