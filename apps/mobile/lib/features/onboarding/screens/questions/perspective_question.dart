import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Q5 : "Tu préfères avoir..."
/// Vue d'ensemble vs Détails
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

          // Question
          Text(
            OnboardingStrings.q5Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.q5Subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: BinarySelectionCard(
                    emoji: '🔭', // Vue d'ensemble
                    label: OnboardingStrings.q5BigPictureLabel,
                    subtitle: OnboardingStrings.q5BigPictureSubtitle,
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
                    emoji: '🔬', // Détails
                    label: OnboardingStrings.q5DetailsLabel,
                    subtitle: OnboardingStrings.q5DetailsSubtitle,
                    isSelected: selectedPerspective == 'detail_oriented',
                    onTap: () {
                      ref
                          .read(onboardingProvider.notifier)
                          .selectPerspective('detail_oriented');
                    },
                  ),
                ),
              ],
            ),
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
