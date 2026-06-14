import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/delayed_continue_button.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Q5b : axe "Indépendance" (nouvelle question v6).
/// Références établies vs médias indépendants. Cadré comme un GOÛT de sourcing,
/// pas un jugement de fiabilité. Valeurs : established / independent.
class IndependenceQuestion extends ConsumerWidget {
  const IndependenceQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selected = state.answers.independencePref;
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
                    OnboardingStrings.qIndependenceTitle,
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
                            emoji: '🏛️',
                            label: OnboardingStrings
                                .qIndependenceEstablishedLabel,
                            subtitle: OnboardingStrings
                                .qIndependenceEstablishedSubtitle,
                            isSelected: selected == 'established',
                            onTap: () {
                              ref
                                  .read(onboardingProvider.notifier)
                                  .selectIndependence('established');
                            },
                          ),
                        ),
                        const SizedBox(width: FacteurSpacing.space3),
                        Expanded(
                          child: BinarySelectionCard(
                            emoji: '🌱',
                            label: OnboardingStrings
                                .qIndependenceIndependentLabel,
                            subtitle: OnboardingStrings
                                .qIndependenceIndependentSubtitle,
                            isSelected: selected == 'independent',
                            onTap: () {
                              ref
                                  .read(onboardingProvider.notifier)
                                  .selectIndependence('independent');
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
            visible: selected != null,
            onPressed: () {
              ref
                  .read(onboardingProvider.notifier)
                  .selectIndependence(selected!);
            },
          ),
        ],
      ),
    );
  }
}
