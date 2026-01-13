import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

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

          // Question (larger without emoji)
          Text(
            OnboardingStrings.q4Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.q4Subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options avec présentation binaire
          Row(
            children: [
              Expanded(
                child: BinarySelectionCard(
                  emoji: '⚡',
                  label: OnboardingStrings.q4DirectLabel,
                  subtitle: OnboardingStrings.q4DirectSubtitle,
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
                  label: OnboardingStrings.q4DetailedLabel,
                  subtitle: OnboardingStrings.q4DetailedSubtitle,
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
