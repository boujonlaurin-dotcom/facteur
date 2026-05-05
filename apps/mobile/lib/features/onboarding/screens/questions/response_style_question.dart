import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/delayed_continue_button.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Q6 : "Quand tu lis, tu aimes..."
/// Réponses tranchées vs nuancées
class ResponseStyleQuestion extends ConsumerWidget {
  const ResponseStyleQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedStyle = state.answers.responseStyle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: FacteurSpacing.space8),

                  Text(
                    OnboardingStrings.q6Title,
                    style: Theme.of(context).textTheme.displayLarge,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: FacteurSpacing.space8),

                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: BinarySelectionCard(
                            emoji: '⚔️',
                            label: OnboardingStrings.q6DecisiveLabel,
                            subtitle: OnboardingStrings.q6DecisiveSubtitle,
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
                            emoji: '⚖️',
                            label: OnboardingStrings.q6NuancedLabel,
                            subtitle: OnboardingStrings.q6NuancedSubtitle,
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
                  ),

                  const SizedBox(height: FacteurSpacing.space6),
                ],
              ),
            ),
          ),

          DelayedContinueButton(
            visible: selectedStyle != null,
            onPressed: () {
              ref
                  .read(onboardingProvider.notifier)
                  .selectResponseStyle(selectedStyle!);
            },
          ),
        ],
      ),
    );
  }
}
