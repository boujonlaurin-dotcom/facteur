import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/delayed_continue_button.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Q4 : "Tu préfères..."
/// Approche directe vs détaillée
class ApproachQuestion extends ConsumerWidget {
  const ApproachQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedApproach = state.answers.approach;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Question
          Text(
            OnboardingStrings.q4Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options binaires
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: BinarySelectionCard(
                    emoji: '⚡', // Direct
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
                    emoji: '🔍', // Détaillé
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
          ),

          const Spacer(flex: 3),

          DelayedContinueButton(
            visible: selectedApproach != null,
            onPressed: () {
              ref
                  .read(onboardingProvider.notifier)
                  .selectApproach(selectedApproach!);
            },
          ),
        ],
      ),
    );
  }
}
