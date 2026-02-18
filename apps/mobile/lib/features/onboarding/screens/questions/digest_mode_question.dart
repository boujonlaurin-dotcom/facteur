import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../digest/models/digest_mode.dart';
import '../../../digest/widgets/digest_mode_card.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';

/// Digest Mode question: Pour vous / Serein / Ouvrir son point de vue
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
            OnboardingStrings.digestModeTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.digestModeSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space8),

          ...DigestMode.values.map((mode) {
            final isSelected = mode.key == selectedMode;
            final modeColor = mode.effectiveColor(colors.primary);

            return Padding(
              padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
              child: DigestModeCard(
                mode: mode,
                isSelected: isSelected,
                modeColor: modeColor,
                colors: colors,
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref
                      .read(onboardingProvider.notifier)
                      .selectDigestMode(mode.key);
                },
              ),
            );
          }),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
