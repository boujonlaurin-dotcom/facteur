import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q2 : "Quelle est ta tranche d'âge ?"
class AgeQuestion extends ConsumerWidget {
  const AgeQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedAge = state.answers.ageRange;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '🎂',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Quelle est ta tranche d\'âge ?',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            'Pour mieux personnaliser ton expérience',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            label: '18 - 24 ans',
            isSelected: selectedAge == '18-24',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectAgeRange('18-24');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            label: '25 - 34 ans',
            isSelected: selectedAge == '25-34',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectAgeRange('25-34');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            label: '35 - 44 ans',
            isSelected: selectedAge == '35-44',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectAgeRange('35-44');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            label: '45 ans et plus',
            isSelected: selectedAge == '45+',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectAgeRange('45+');
            },
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
