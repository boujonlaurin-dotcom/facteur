import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/selection_card.dart';
import '../../onboarding_strings.dart';

/// Q7 : "Tu préfères..."
/// Actualité chaude vs Analyses de fond
class ContentRecencyQuestion extends ConsumerWidget {
  const ContentRecencyQuestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final selectedRecency = state.answers.contentRecency;
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Question
          Text(
            OnboardingStrings.q7Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.q7Subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
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
                    icon: PhosphorIcons.newspaper(
                      PhosphorIconsStyle.bold,
                    ), // Récent -> Journal
                    iconColor: colors.warning, // Orange/Urgent
                    label: OnboardingStrings.q7RecentLabel,
                    subtitle: OnboardingStrings.q7RecentSubtitle,
                    isSelected: selectedRecency == 'recent',
                    onTap: () {
                      ref
                          .read(onboardingProvider.notifier)
                          .selectContentRecency('recent');
                    },
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: BinarySelectionCard(
                    icon: PhosphorIcons.hourglass(
                      PhosphorIconsStyle.bold,
                    ), // Intemporel -> Sablier
                    iconColor: colors.secondary, // Beige/Classique
                    label: OnboardingStrings.q7TimelessLabel,
                    subtitle: OnboardingStrings.q7TimelessSubtitle,
                    isSelected: selectedRecency == 'timeless',
                    onTap: () {
                      ref
                          .read(onboardingProvider.notifier)
                          .selectContentRecency('timeless');
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
