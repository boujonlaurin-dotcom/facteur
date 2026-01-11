import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';

/// Q3 : "Tu es..." (optionnel)
class GenderQuestion extends ConsumerWidget {
  const GenderQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedGender = state.answers.gender;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Illustration
          const Text(
            '👤',
            style: TextStyle(fontSize: 64),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Question
          Text(
            'Tu es...',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // Indicateur optionnel
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FacteurSpacing.space3,
              vertical: FacteurSpacing.space1,
            ),
            decoration: BoxDecoration(
              color: context.facteurColors.surfaceElevated,
              borderRadius: BorderRadius.circular(FacteurRadius.pill),
            ),
            child: Text(
              'Optionnel',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.facteurColors.textTertiary,
                  ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            label: 'Un homme',
            isSelected: selectedGender == 'male',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectGender('male');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            label: 'Une femme',
            isSelected: selectedGender == 'female',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectGender('female');
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            label: 'Autre',
            isSelected: selectedGender == 'other',
            onTap: () {
              ref.read(onboardingProvider.notifier).selectGender('other');
            },
          ),

          const Spacer(flex: 2),

          // Bouton pour passer la question
          TextButton(
            onPressed: () {
              ref.read(onboardingProvider.notifier).skipGender();
            },
            child: Text(
              'Passer cette question',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: context.facteurColors.textTertiary,
                  ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
