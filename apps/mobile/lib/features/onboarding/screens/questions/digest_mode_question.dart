import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/serein_colors.dart';
import '../../../../config/theme.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/delayed_continue_button.dart';

/// Emotional binary screen: "Rester serein ?" with two buttons.
class DigestModeQuestion extends ConsumerWidget {
  const DigestModeQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedMode = state.answers.digestMode;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          Text(
            '🌿 Rester serein ?',
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text.rich(
            TextSpan(
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.textSecondary),
              children: const [
                TextSpan(text: OnboardingStrings.digestModeSereinPart1),
                TextSpan(
                  text: OnboardingStrings.digestModeSereinBold1,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: OnboardingStrings.digestModeSereinPart2),
                TextSpan(
                  text: OnboardingStrings.digestModeSereinBold2,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: OnboardingStrings.digestModeSereinPart3),
                TextSpan(
                  text: OnboardingStrings.digestModeSereinBold3,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: OnboardingStrings.digestModeSereinPart4),
              ],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          // Primary: Oui, rester serein
          ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(onboardingProvider.notifier).selectDigestMode('serein');
            },
            icon: Icon(SereinColors.sereinIcon, size: 18),
            label: const Text('Oui, rester serein'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SereinColors.sereinColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 24),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FacteurRadius.large),
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // Secondary: Non, tout voir
          OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref
                  .read(onboardingProvider.notifier)
                  .selectDigestMode('pour_vous');
            },
            icon: Icon(SereinColors.normalIcon, size: 18),
            label: const Text('Non, tout voir'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 24),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: colors.textTertiary.withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FacteurRadius.large),
              ),
            ),
          ),

          const Spacer(flex: 3),

          DelayedContinueButton(
            visible: selectedMode != null,
            onPressed: () {
              ref
                  .read(onboardingProvider.notifier)
                  .selectDigestMode(selectedMode!);
            },
          ),
        ],
      ),
    );
  }
}
