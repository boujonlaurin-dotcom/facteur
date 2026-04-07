import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/delayed_continue_button.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Q8 : "Activer les objectifs ?"
/// Gamification oui/non
class GamificationQuestion extends ConsumerWidget {
  const GamificationQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final gamificationEnabled = state.answers.gamificationEnabled;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Question
          Text(
            OnboardingStrings.q8Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text.rich(
            TextSpan(
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              children: [
                const TextSpan(text: OnboardingStrings.q8SubtitlePart1),
                TextSpan(
                  text: OnboardingStrings.q8SubtitleBold1,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const TextSpan(text: OnboardingStrings.q8SubtitlePart2),
                TextSpan(
                  text: OnboardingStrings.q8SubtitleBold2,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const TextSpan(text: OnboardingStrings.q8SubtitlePart3),
              ],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Options
          SelectionCard(
            emoji: '✅', // Oui
            label: OnboardingStrings.q8YesLabel,
            isSelected: gamificationEnabled == true,
            onTap: () {
              ref.read(onboardingProvider.notifier).selectGamification(true);
            },
          ),

          const SizedBox(height: FacteurSpacing.space3),

          SelectionCard(
            emoji: '🚫', // Non
            label: OnboardingStrings.q8NoLabel,
            subtitle: OnboardingStrings.q8NoSubtitle,
            isSelected: gamificationEnabled == false,
            onTap: () {
              ref.read(onboardingProvider.notifier).selectGamification(false);
            },
          ),

          const Spacer(flex: 3),

          DelayedContinueButton(
            visible: gamificationEnabled != null,
            onPressed: () {
              ref
                  .read(onboardingProvider.notifier)
                  .selectGamification(gamificationEnabled!);
            },
          ),
        ],
      ),
    );
  }
}
