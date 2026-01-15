import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
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
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Question (larger without emoji)
          Text(
            OnboardingStrings.q6Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.q6Subtitle,
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
                    icon: PhosphorIcons.sword(
                      PhosphorIconsStyle.bold,
                    ), // Tranché -> Épée
                    iconColor: colors
                        .error, // Rouge/Action (using error for bold color)
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
                    icon: PhosphorIcons.scales(
                      PhosphorIconsStyle.bold,
                    ), // Nuancé -> Balance
                    iconColor: colors.info, // Bleu/Calme
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

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
